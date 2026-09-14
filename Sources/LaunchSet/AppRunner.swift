import AppKit
import LaunchSetCore
import Observation

/// Opens and closes app groups. Every command runs one after another through a single queue.
@Observable @MainActor
final class AppRunner {
    private var busy: [UUID: Int] = [:]
    @ObservationIgnored private var tail: Task<Void, Never>?

    func isBusy(_ groupID: UUID) -> Bool { busy[groupID, default: 0] > 0 }

    func run(_ action: GroupAction, group: AppGroup, quitTimeout: Int, force: Bool) async -> [AppResult] {
        busy[group.id, default: 0] += 1
        let previous = tail
        let job = Task {
            await previous?.value
            return action == .open
                ? await open(group)
                : await close(group, timeout: quitTimeout, force: force)
        }
        tail = Task { _ = await job.value }
        let results = await job.value
        busy[group.id, default: 1] -= 1
        if busy[group.id] == 0 { busy[group.id] = nil }
        return results
    }

    static func appURL(_ app: AppRef) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) { return url }
        return FileManager.default.fileExists(atPath: app.lastKnownPath) ? URL(fileURLWithPath: app.lastKnownPath) : nil
    }

    private func open(_ group: AppGroup) async -> [AppResult] {
        var results: [AppResult] = []
        for (i, app) in group.apps.enumerated() {
            func add(_ outcome: AppOutcome, _ error: String? = nil) {
                results.append(AppResult(bundleID: app.bundleID, name: app.name, outcome: outcome, error: error))
            }
            if !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty {
                add(.alreadyRunning)
                continue
            }
            guard let url = Self.appURL(app) else {
                add(.notFound)
                continue
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = group.hideAfterOpen
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                add(.opened)
                if group.launchDelaySeconds > 0, i < group.apps.count - 1 {
                    try? await Task.sleep(for: .seconds(group.launchDelaySeconds))
                }
            } catch {
                add(.openFailed, error.localizedDescription)
            }
        }
        return results
    }

    private func close(_ group: AppGroup, timeout: Int, force: Bool) async -> [AppResult] {
        // Never quit system apps, even if someone edited config.json by hand.
        let apps = group.apps.filter { !Blocklist.contains($0.bundleID) }
        let instances = apps.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID) }
        let all = instances.flatMap { $0 }
        if force {
            all.forEach { $0.forceTerminate() }
        } else {
            all.forEach { $0.terminate() }
            await Self.waitUntilGone(all.map(\.processIdentifier), timeout: timeout)
        }

        return zip(apps, instances).map { app, running in
            let outcome: AppOutcome
            let alive = running.filter { !Self.isGone($0.processIdentifier) }
            if running.isEmpty {
                outcome = .notRunning
            } else if force {
                outcome = .forceClosed
            } else if alive.isEmpty {
                outcome = .closed
            } else if group.quitPolicy == .forceQuit {
                alive.forEach { $0.forceTerminate() }
                outcome = .forceClosed
            } else {
                outcome = .notClosed
            }
            return AppResult(bundleID: app.bundleID, name: app.name, outcome: outcome)
        }
    }

    private static func isGone(_ pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true
    }

    /// Waits for every pid to exit, or for `timeout` seconds. Listens for termination instead of polling.
    private static func waitUntilGone(_ pids: [pid_t], timeout: Int) async {
        let waiter = Task { @MainActor in
            // Subscribe before checking so an app that quits in between still wakes us.
            let it = NSWorkspace.shared.notificationCenter
                .notifications(named: NSWorkspace.didTerminateApplicationNotification).makeAsyncIterator()
            while !pids.allSatisfy(isGone), await it.next() != nil {}
        }
        let timer = Task {
            try? await Task.sleep(for: .seconds(timeout))
            waiter.cancel()
        }
        await waiter.value
        timer.cancel()
    }
}
