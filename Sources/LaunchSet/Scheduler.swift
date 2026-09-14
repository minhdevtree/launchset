import AppKit
import LaunchSetCore
import Observation

/// Checks the schedule every 15 seconds and on wake or clock changes, then runs what is due.
@Observable @MainActor
final class Scheduler {
    /// A close that is about to happen. Visible in the menu bar until it runs or is skipped.
    struct Warning: Identifiable {
        let key: String
        let ruleID: UUID
        let groupID: UUID
        let occurrence: Date
        /// Equals `occurrence` until snoozed.
        var closeAt: Date
        var id: String { key }
    }

    // ponytail: snooze and skip state lives in memory and is lost on restart; persist it if that turns out to matter.
    private(set) var warnings: [Warning] = []
    private var skipped: Set<String> = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastCheckedAt = Date() {
        didSet { UserDefaults.standard.set(lastCheckedAt, forKey: "lastCheckedAt") }
    }

    private let store: AppStore
    private let notifier: Notifier

    init(store: AppStore, notifier: Notifier) {
        self.store = store
        self.notifier = notifier
    }

    func start() {
        let now = Date()
        let saved = UserDefaults.standard.object(forKey: "lastCheckedAt") as? Date ?? .distantPast
        lastCheckedAt = max(saved, now - TimeInterval(store.config.settings.missedGraceMinutes * 60))

        notifier.onAction = { [weak self] key, action in
            if action == .snooze { self?.snooze(key) } else { self?.skip(key) }
        }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observe(NSWorkspace.shared.notificationCenter, [NSWorkspace.didWakeNotification]) { [weak self] in self?.check() }
        observe(NotificationCenter.default, [.NSSystemClockDidChange, .NSSystemTimeZoneDidChange]) { [weak self] in self?.check() }
        check()
    }

    func setPaused(_ paused: Bool) {
        store.config.settings.schedulesPaused = paused
        // Resuming starts from now, so runs skipped during the pause don't catch up.
        lastCheckedAt = Date()
        if paused { warnings.removeAll() }
    }

    func check() {
        let now = Date()
        let settings = store.config.settings
        if settings.schedulesPaused {
            lastCheckedAt = now
            warnings.removeAll()
            return
        }
        if now < lastCheckedAt {
            lastCheckedAt = now
            return
        }
        let calendar = Calendar.current
        let (due, missed) = Schedule.evaluate(rules: store.config.rules, settings: settings,
                                              from: lastCheckedAt, now: now, calendar: calendar)
        lastCheckedAt = now

        for event in missed {
            guard let rule = store.rule(event.ruleID), let group = store.group(rule.groupID) else { continue }
            let time = Schedule.relativeParts(event.occurrence, now: now, calendar: calendar).time
            store.addHistory(RunRecord(date: now, groupID: group.id, groupName: group.name, action: rule.action, source: .scheduled,
                                       note: "Missed the \(time) schedule (the Mac was asleep or LaunchSet wasn't running)"))
        }

        var jobs: [(GroupAction, UUID)] = []
        for event in due {
            guard let rule = store.rule(event.ruleID), let group = store.group(rule.groupID) else { continue }
            let key = event.occurrenceKey
            switch event.kind {
            case .warn:
                let appCount = group.plan(for: .close).quit.count
                // A warning for a close that already happened, or one that quits nothing, is useless.
                guard event.occurrence > now, appCount > 0, !skipped.contains(key),
                      !warnings.contains(where: { $0.key == key }) else { continue }
                warnings.append(Warning(key: key, ruleID: rule.id, groupID: group.id, occurrence: event.occurrence, closeAt: event.occurrence))
                notifier.warn(key: key, groupName: group.name, appCount: appCount, closeAt: event.occurrence,
                              snoozeMinutes: settings.snoozeMinutes)
            case .run:
                if skipped.remove(key) != nil {
                    recordSkip(group: group)
                    continue
                }
                if let w = warnings.first(where: { $0.key == key }), w.closeAt > w.occurrence { continue } // snoozed
                warnings.removeAll { $0.key == key }
                notifier.remove(key)
                jobs.append((rule.action, group.id))
            }
        }

        // Snoozed closes whose time has come. Unsnoozed leftovers (rule deleted or disabled) are dropped.
        for w in warnings where w.closeAt <= now {
            warnings.removeAll { $0.key == w.key }
            notifier.remove(w.key)
            if w.closeAt > w.occurrence, store.rule(w.ruleID)?.isEnabled == true {
                jobs.append((.close, w.groupID))
            }
        }

        guard !jobs.isEmpty else { return }
        Task {
            for (action, groupID) in jobs { await runScheduled(action, groupID: groupID) }
        }
    }

    // MARK: Next run

    private var snoozed: [String: Date] {
        Dictionary(warnings.filter { $0.closeAt > $0.occurrence }.map { ($0.key, $0.closeAt) }, uniquingKeysWith: max)
    }

    /// "Today, 18:00" for one rule, or "Off" / "None".
    func nextLabel(_ rule: ScheduleRule) -> String {
        guard rule.isEnabled else { return "Off" }
        guard let next = Schedule.upcoming(rule, now: .now, calendar: .current, skipped: skipped, snoozed: snoozed) else { return "None" }
        return Schedule.relativeLabel(next, now: .now, calendar: .current)
    }

    /// "Next: Close "Work" at 18:00 today", shown in the menu bar and by `launchset status`.
    func nextLine(now: Date) -> String {
        if store.config.settings.schedulesPaused { return "All schedules are paused" }
        guard let next = Schedule.nextRun(rules: store.config.rules, now: now, calendar: .current, skipped: skipped, snoozed: snoozed),
              let group = store.group(next.rule.groupID)
        else { return "No schedules turned on" }
        let parts = Schedule.relativeParts(next.date, now: now, calendar: .current)
        let day = ["Today", "Tomorrow"].contains(parts.day) ? parts.day.lowercased() : "on \(parts.day)"
        return "Next: \(next.rule.action.label) \"\(group.name)\" at \(parts.time) \(day)"
    }

    // MARK: Snooze and skip

    func snooze(_ key: String) {
        guard let i = warnings.firstIndex(where: { $0.key == key }) else { return }
        // Push the planned close back, never earlier than it already was.
        warnings[i].closeAt = max(Date(), warnings[i].closeAt) + TimeInterval(store.config.settings.snoozeMinutes * 60)
        notifier.remove(key)
    }

    func skip(_ key: String) {
        guard let w = warnings.first(where: { $0.key == key }) else { return }
        warnings.removeAll { $0.key == key }
        notifier.remove(key)
        if w.occurrence <= Date() {
            // Original time already passed while snoozed, so no run event will come to log it.
            if let group = store.group(w.groupID) { recordSkip(group: group) }
        } else {
            skipped.insert(key)
        }
    }

    private func recordSkip(group: AppGroup) {
        store.addHistory(RunRecord(date: .now, groupID: group.id, groupName: group.name, action: .close,
                                   source: .scheduled, note: "Skipped this time"))
    }

    private func runScheduled(_ action: GroupAction, groupID: UUID) async {
        guard let record = await store.run(action, groupID: groupID, source: .scheduled) else { return }
        let failed = record.results.filter { !$0.outcome.isSuccess }
        if failed.isEmpty, store.config.settings.notifyOnSuccess {
            notifier.post(title: "\(action == .open ? "Opened" : "Closed") \"\(record.groupName)\"", body: record.summary)
        }
        // Open can quit apps too (Close on open), so both kinds of failure can show up for either action.
        let stillOpen = failed.filter { $0.outcome == .notClosed }
        if !stillOpen.isEmpty {
            let one = stillOpen.count == 1
            notifier.post(title: "Some apps didn't close",
                          body: "\(stillOpen.map(\.name).joined(separator: ", ")) \(one ? "is" : "are") still open after \(store.config.settings.quitTimeoutSeconds) seconds. \(one ? "It" : "They") may be waiting for you to save a file.")
        }
        let notOpened = failed.filter { $0.outcome != .notClosed }
        if !notOpened.isEmpty {
            notifier.post(title: "Some apps in \"\(record.groupName)\" didn't open",
                          body: notOpened.map { "\($0.name): \($0.label)" }.joined(separator: "\n"))
        }
    }
}
