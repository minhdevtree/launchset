import AppKit
import LaunchSetCore

/// Answers the `launchset` command over a Unix socket, so groups can be run over SSH.
/// Commands go through the same store, runner and scheduler as the menu bar.
@MainActor
final class CommandServer {
    private let store: AppStore
    private let scheduler: Scheduler
    private var source: DispatchSourceRead?

    init(store: AppStore, scheduler: Scheduler) {
        self.store = store
        self.scheduler = scheduler
    }

    func start() {
        let fd: Int32
        do {
            fd = try CLI.makeListener()
        } catch {
            return NSLog("LaunchSet: the launchset command won't work, socket setup failed: \(error)")
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
        source.setEventHandler { [weak self] in
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            Task { await self?.serve(client) }
        }
        source.resume()
        self.source = source
    }

    private nonisolated func serve(_ client: Int32) async {
        defer { close(client) }
        // The socket file is already 0600; checking the peer too keeps other users out if its mode changes.
        var uid = uid_t(), gid = gid_t()
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) // a client hitting Ctrl-C must not kill the app
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let response: CLIResponse
        if let request = try? JSON.decoder().decode(CLIRequest.self, from: CLI.readAll(client)) {
            response = await handle(request.args)
        } else {
            response = CLIResponse(output: "LaunchSet couldn't read the request.", exitCode: 2)
        }
        try? CLI.writeAll(client, JSON.encoder().encode(response))
    }

    func handle(_ args: [String]) async -> CLIResponse {
        let command = args.first ?? "status"
        let rest = Array(args.dropFirst())
        switch command {
        case "status":
            return CLIResponse(output: status())
        case "groups":
            return CLIResponse(output: groups())
        case "schedules":
            return CLIResponse(output: schedules())
        case "history":
            return CLIResponse(output: history(count: rest.first.flatMap { Int($0) } ?? 10))
        case "open", "close":
            let force = rest.contains("--force")
            if force, command == "open" { return fail("--force only works with close.") }
            return await run(command == "open" ? .open : .close, name: rest.filter { $0 != "--force" }, force: force)
        case "pause":
            scheduler.setPaused(true)
            return CLIResponse(output: "Schedules paused.")
        case "resume":
            scheduler.setPaused(false)
            return CLIResponse(output: "Schedules resumed. Runs missed while paused won't catch up.")
        case "snooze", "skip":
            return pending(command, name: rest)
        case "help", "-h", "--help":
            return CLIResponse(output: CLI.usage)
        default:
            return fail("Unknown command \"\(command)\".\n\n\(CLI.usage)")
        }
    }

    // MARK: Commands

    private func status() -> String {
        var lines = [store.nextLine(now: .now)]
        for w in scheduler.warnings {
            let name = store.group(w.groupID)?.name ?? ""
            lines.append("Closing \"\(name)\" at \(time(w.closeAt)). Run launchset snooze \(name) or launchset skip \(name).")
        }
        lines.append("")
        if store.config.groups.isEmpty {
            lines.append("No groups yet. Create one in the LaunchSet window.")
        } else {
            lines.append(CLI.table(store.config.groups.map { [$0.name, store.runningLabel($0)] }))
        }
        return lines.joined(separator: "\n")
    }

    private func groups() -> String {
        guard !store.config.groups.isEmpty else { return "No groups yet. Create one in the LaunchSet window." }
        return store.config.groups.map { group in
            let apps = group.apps.map { app in
                let state = store.running.contains(app.bundleID) ? "running" : AppRunner.appURL(app) == nil ? "not found" : "not running"
                return [app.name, app.role.label.lowercased(), state]
            }
            let header = "\(group.name) (\(store.runningLabel(group)))"
            return apps.isEmpty ? "\(header)\n  No apps" : "\(header)\n\(CLI.table(apps, indent: "  "))"
        }.joined(separator: "\n\n")
    }

    private func schedules() -> String {
        guard !store.config.rules.isEmpty else { return "No schedules yet." }
        return CLI.table(store.config.rules.map { rule in
            [rule.isEnabled ? "on" : "off", store.group(rule.groupID)?.name ?? "Deleted group",
             rule.action.label, rule.timeLabel, rule.daysLabel, store.nextLabel(rule)]
        })
    }

    private func history(count: Int) -> String {
        guard !store.history.isEmpty else { return "No history yet." }
        return store.history.prefix(max(1, count)).map { $0.line(now: .now, calendar: .current) }.joined(separator: "\n")
    }

    private func run(_ action: GroupAction, name: [String], force: Bool) async -> CLIResponse {
        let group: AppGroup
        switch find(name) {
        case .success(let g): group = g
        case .failure(let message): return fail(message.text)
        }
        guard let record = await store.run(action, groupID: group.id, source: .manual, force: force) else {
            return fail("\"\(group.name)\" was deleted.")
        }
        let lines = [record.flash] + record.results.map { "  \($0.name): \($0.label)" }
        return CLIResponse(output: lines.joined(separator: "\n"), exitCode: record.results.allSatisfy(\.outcome.isSuccess) ? 0 : 1)
    }

    private func pending(_ command: String, name: [String]) -> CLIResponse {
        let group: AppGroup
        switch find(name) {
        case .success(let g): group = g
        case .failure(let message): return fail(message.text)
        }
        guard let warning = scheduler.warnings.first(where: { $0.groupID == group.id }) else {
            return fail("Nothing is about to close in \"\(group.name)\".")
        }
        if command == "skip" {
            scheduler.skip(warning.key)
            return CLIResponse(output: "Skipped this close of \"\(group.name)\".")
        }
        scheduler.snooze(warning.key)
        let closeAt = scheduler.warnings.first { $0.key == warning.key }?.closeAt ?? warning.closeAt
        return CLIResponse(output: "Snoozed. \"\(group.name)\" now closes at \(time(closeAt)).")
    }

    // MARK: Helpers

    private struct Message: Error { let text: String }

    private func find(_ words: [String]) -> Result<AppGroup, Message> {
        let name = words.joined(separator: " ")
        guard !name.isEmpty else { return .failure(Message(text: "Name a group, for example: launchset open Work")) }
        let matches = store.config.groups.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        switch matches.count {
        case 1: return .success(matches[0])
        case 0:
            let names = store.config.groups.map { "\"\($0.name)\"" }.joined(separator: ", ")
            return .failure(Message(text: "No group is named \"\(name)\". Groups: \(names.isEmpty ? "none yet" : names)"))
        default:
            return .failure(Message(text: "More than one group is named \"\(name)\". Rename one in the LaunchSet window."))
        }
    }

    private func fail(_ text: String) -> CLIResponse { CLIResponse(output: text, exitCode: 2) }

    private func time(_ date: Date) -> String { Schedule.relativeParts(date, now: date, calendar: .current).time }
}
