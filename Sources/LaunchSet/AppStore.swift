import AppKit
import LaunchSetCore
import Observation
import ServiceManagement
import SwiftUI

@Observable @MainActor
final class AppStore {
    var config: Config { didSet { if config != oldValue { scheduleSave() } } }
    private(set) var history: [RunRecord] { didSet { scheduleSave() } }
    /// Bundle IDs of running apps, kept current by workspace notifications.
    private(set) var running: Set<String> = []
    /// Short inline result of a manual run, per group, cleared after 3 seconds.
    private(set) var flash: [UUID: String] = [:]
    private(set) var loginItemStatus = SMAppService.mainApp.status
    /// Set at launch when a data file was unreadable and got renamed.
    var loadNotice: String?
    let runner = AppRunner()

    @ObservationIgnored private let configURL: URL
    @ObservationIgnored private let historyURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Stays false if a damaged file could not be moved aside, so it never gets overwritten.
    @ObservationIgnored private var canSave = true

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchSet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("config.json")
        historyURL = dir.appendingPathComponent("history.json")

        let loadedConfig = Self.load(Config.self, from: configURL)
        let loadedHistory = Self.load([RunRecord].self, from: historyURL)
        config = loadedConfig.value ?? Config()
        history = loadedHistory.value ?? []
        canSave = loadedConfig.moved && loadedHistory.moved
        if let name = loadedConfig.renamedTo {
            loadNotice = "config.json was damaged, so LaunchSet renamed it to \(name) and started with an empty configuration."
        }
        if !canSave {
            loadNotice = "LaunchSet couldn't read or move its data files, so it won't save changes until you fix them in \(dir.path)."
        }

        refreshRunning()
        observe(NSWorkspace.shared.notificationCenter,
                [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]) { [weak self] in
            self?.refreshRunning()
        }
    }

    // MARK: Persistence

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> (value: T?, renamedTo: String?, moved: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, nil, true) }
        do {
            return (try JSON.decoder().decode(T.self, from: Data(contentsOf: url)), nil, true)
        } catch {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let name = "\(url.deletingPathExtension().lastPathComponent).corrupt-\(f.string(from: .now)).json"
            do {
                try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent(name))
                return (nil, name, true)
            } catch {
                return (nil, nil, false)
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard canSave else { return }
        do {
            try JSON.encoder().encode(config).write(to: configURL, options: .atomic)
            try JSON.encoder().encode(history).write(to: historyURL, options: .atomic)
        } catch {
            NSLog("LaunchSet: save failed: \(error)")
        }
    }

    // MARK: Groups and apps

    func group(_ id: UUID) -> AppGroup? { config.groups.first { $0.id == id } }
    func rule(_ id: UUID) -> ScheduleRule? { config.rules.first { $0.id == id } }

    func updateGroup(_ group: AppGroup) {
        guard let i = config.groups.firstIndex(where: { $0.id == group.id }) else { return }
        config.groups[i] = group
    }

    func addGroup() -> UUID {
        let group = AppGroup(name: "New Group")
        config.groups.append(group)
        return group.id
    }

    func deleteGroup(_ id: UUID) {
        guard let g = group(id),
              confirm(title: "Delete \"\(g.name)\"?", message: "Its schedules will be deleted too.", ok: "Delete", destructive: true)
        else { return }
        config.groups.removeAll { $0.id == id }
        config.rules.removeAll { $0.groupID == id }
    }

    /// Returns the reasons some apps were refused, or nil when every app was added.
    func addApps(_ refs: [AppRef], to groupID: UUID) -> String? {
        guard var g = group(groupID) else { return nil }
        var errors: [String] = []
        for ref in refs {
            if let reason = Blocklist.reason(bundleID: ref.bundleID, name: ref.name) {
                errors.append(reason)
            } else if !g.apps.contains(where: { $0.bundleID == ref.bundleID }) {
                g.apps.append(ref)
            }
        }
        updateGroup(g)
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func addApps(urls: [URL], to groupID: UUID) -> String? {
        var refs: [AppRef] = []
        var errors: [String] = []
        for url in urls {
            if url.pathExtension == "app", let id = Bundle(url: url)?.bundleIdentifier {
                refs.append(AppRef(bundleID: id, name: url.deletingPathExtension().lastPathComponent, lastKnownPath: url.path))
            } else {
                errors.append("\(url.lastPathComponent) isn't an app.")
            }
        }
        if let blocked = addApps(refs, to: groupID) { errors.append(blocked) }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    static func runningAppRefs() -> [AppRef] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let url = app.bundleURL else { return nil }
                return AppRef(bundleID: id, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, lastKnownPath: url.path)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func refreshRunning() {
        running = Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
    }

    func runningCount(_ group: AppGroup) -> Int { group.apps.filter { running.contains($0.bundleID) }.count }

    // MARK: Schedules

    func upsertRule(_ rule: ScheduleRule) {
        if let i = config.rules.firstIndex(where: { $0.id == rule.id }) { config.rules[i] = rule } else { config.rules.append(rule) }
    }

    func deleteRules(_ ids: Set<UUID>) { config.rules.removeAll { ids.contains($0.id) } }

    func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { self.rule(id)?.isEnabled ?? false }, set: { on in
            guard let i = self.config.rules.firstIndex(where: { $0.id == id }) else { return }
            self.config.rules[i].isEnabled = on
        })
    }

    func nextLabel(_ rule: ScheduleRule) -> String {
        guard rule.isEnabled else { return "Off" }
        guard let next = Schedule.nextOccurrence(of: rule, after: .now, calendar: .current) else { return "None" }
        return Schedule.relativeLabel(next, now: .now, calendar: .current)
    }

    /// Earliest upcoming run across enabled rules.
    func nextRun(now: Date) -> (rule: ScheduleRule, date: Date)? {
        config.rules.filter(\.isEnabled)
            .compactMap { r in Schedule.nextOccurrence(of: r, after: now, calendar: .current).map { (r, $0) } }
            .min { $0.1 < $1.1 }
    }

    // MARK: Running groups

    @discardableResult
    func run(_ action: GroupAction, groupID: UUID, source: RunSource, force: Bool = false) async -> RunRecord? {
        guard let g = group(groupID) else { return nil }
        let start = Date()
        let results = await runner.run(action, group: g, quitTimeout: config.settings.quitTimeoutSeconds, force: force)
        let record = RunRecord(date: start, groupID: g.id, groupName: g.name, action: action, source: source, results: results)
        addHistory(record)
        if source == .manual {
            let ok = results.filter { $0.outcome.isSuccess }.count
            showFlash("\(action == .open ? "Opened" : "Closed") \(ok) of \(results.count) apps", for: g.id)
        }
        return record
    }

    func confirmForceClose(_ groupID: UUID) {
        guard let g = group(groupID),
              confirm(title: "Force quit \(g.apps.count) apps in \"\(g.name)\"?",
                      message: "Unsaved changes in these apps will be lost.", ok: "Force Quit", destructive: true)
        else { return }
        Task { await run(.close, groupID: groupID, source: .manual, force: true) }
    }

    private func showFlash(_ text: String, for id: UUID) {
        flash[id] = text
        Task {
            try? await Task.sleep(for: .seconds(3))
            if flash[id] == text { flash[id] = nil }
        }
    }

    // MARK: History

    func addHistory(_ record: RunRecord) {
        history.insert(record, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
    }

    func clearHistory() { history.removeAll() }

    // MARK: Settings

    func refreshLoginItem() { loginItemStatus = SMAppService.mainApp.status }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            showAlert("Couldn't change Launch at login", error.localizedDescription)
        }
        refreshLoginItem()
    }

    func exportConfig() {
        NSApp.activate()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LaunchSet.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try JSON.encoder().encode(config).write(to: url, options: .atomic)
        } catch {
            showAlert("Couldn't export", error.localizedDescription)
        }
    }

    func importConfig() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let imported: Config
        do {
            imported = try JSON.decoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            return showAlert("Couldn't import", "\(url.lastPathComponent) isn't a LaunchSet configuration file.")
        }
        guard confirm(title: "Importing replaces all your current groups and schedules.", message: "",
                      ok: "Import and Replace", destructive: true) else { return }
        config = imported
    }
}

// MARK: - Helpers

/// Runs `handler` on the main actor every time one of `names` is posted.
@MainActor
func observe(_ center: NotificationCenter, _ names: [Notification.Name], _ handler: @escaping @MainActor () -> Void) {
    for name in names {
        Task {
            for await _ in center.notifications(named: name) { handler() }
        }
    }
}

/// NSAlert instead of SwiftUI .alert because the menu bar popover can't reliably host one.
@MainActor
func confirm(title: String, message: String, ok: String, destructive: Bool = false) -> Bool {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: ok).hasDestructiveAction = destructive
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
}

@MainActor
func showAlert(_ title: String, _ message: String) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.runModal()
}
