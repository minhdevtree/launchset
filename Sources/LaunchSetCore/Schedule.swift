import Foundation

public struct DueEvent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case run, warn }
    public let ruleID: UUID
    public let kind: Kind
    public let occurrence: Date   // the rule's own time (warn events keep it too)
    public let fireAt: Date       // run: = occurrence; warn: = occurrence - warnBeforeCloseMinutes

    public init(ruleID: UUID, kind: Kind, occurrence: Date, fireAt: Date) {
        self.ruleID = ruleID
        self.kind = kind
        self.occurrence = occurrence
        self.fireAt = fireAt
    }

    /// ruleID + original time, the key for snooze and skip.
    public var occurrenceKey: String { Self.key(ruleID: ruleID, occurrence: occurrence) }

    public static func key(ruleID: UUID, occurrence: Date) -> String {
        "\(ruleID.uuidString)@\(Int(occurrence.timeIntervalSince1970))"
    }
}

public enum Schedule {
    /// Display order, Monday first: [2, 3, 4, 5, 6, 7, 1]
    public static let displayWeekdays = [2, 3, 4, 5, 6, 7, 1]

    private static let shortNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let longNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// Calendar weekday (1 = Sunday) -> "Sun", "Mon" ... "Sat"
    public static func weekdayShort(_ weekday: Int) -> String { shortNames[weekday - 1] }

    /// Calendar weekday (1 = Sunday) -> "Sunday", "Monday" ...
    public static func weekdayLong(_ weekday: Int) -> String { longNames[weekday - 1] }

    /// Next run strictly after `after`.
    public static func nextOccurrence(of rule: ScheduleRule, after: Date, calendar: Calendar) -> Date? {
        rule.weekdays.compactMap { weekday in
            calendar.nextDate(after: after,
                              matching: DateComponents(hour: rule.hour, minute: rule.minute, second: 0, weekday: weekday),
                              matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }.min()
    }

    /// When a rule really runs next: skipped runs are passed over and a snoozed close counts at its snoozed time.
    /// `skipped` and `snoozed` are keyed by `DueEvent.key`; `snoozed` maps to the new close time.
    public static func upcoming(_ rule: ScheduleRule, now: Date, calendar: Calendar,
                                skipped: Set<String> = [], snoozed: [String: Date] = [:]) -> Date? {
        guard rule.isEnabled else { return nil }
        let prefix = "\(rule.id.uuidString)@"
        var candidates = snoozed.filter { $0.key.hasPrefix(prefix) && $0.value > now }.map(\.value)
        var after = now
        while let next = nextOccurrence(of: rule, after: after, calendar: calendar) {
            let key = DueEvent.key(ruleID: rule.id, occurrence: next)
            guard skipped.contains(key) || snoozed[key] != nil else {
                candidates.append(next)
                break
            }
            after = next
        }
        return candidates.min()
    }

    /// Earliest `upcoming` run across all rules.
    public static func nextRun(rules: [ScheduleRule], now: Date, calendar: Calendar,
                               skipped: Set<String> = [], snoozed: [String: Date] = [:]) -> (rule: ScheduleRule, date: Date)? {
        rules.compactMap { rule in
            upcoming(rule, now: now, calendar: calendar, skipped: skipped, snoozed: snoozed).map { (rule, $0) }
        }.min { $0.1 < $1.1 }
    }

    /// Events whose fireAt falls in (from, now]. Only the latest one per (rule, kind).
    /// `due`: late by <= graceMinutes. `missed`: only kind == .run, late by more than grace.
    /// Disabled rules are ignored. Sorted by fireAt; ties keep the order of `rules`.
    public static func evaluate(rules: [ScheduleRule], settings: AppSettings,
                                from: Date, now: Date, calendar: Calendar)
        -> (due: [DueEvent], missed: [DueEvent]) {
        guard from < now else { return ([], []) }
        var events: [(event: DueEvent, index: Int)] = []
        let warn = TimeInterval(settings.warnBeforeCloseMinutes * 60)
        for (index, rule) in rules.enumerated() where rule.isEnabled {
            if let o = latestOccurrence(of: rule, after: from, upTo: now, calendar: calendar) {
                events.append((DueEvent(ruleID: rule.id, kind: .run, occurrence: o, fireAt: o), index))
            }
            if rule.action == .close, warn > 0,
               let o = latestOccurrence(of: rule, after: from + warn, upTo: now + warn, calendar: calendar) {
                events.append((DueEvent(ruleID: rule.id, kind: .warn, occurrence: o, fireAt: o - warn), index))
            }
        }
        events.sort { ($0.event.fireAt, $0.index) < ($1.event.fireAt, $1.index) }
        let grace = TimeInterval(settings.missedGraceMinutes * 60)
        let due = events.map(\.event).filter { now.timeIntervalSince($0.fireAt) <= grace }
        let missed = events.map(\.event).filter { $0.kind == .run && now.timeIntervalSince($0.fireAt) > grace }
        return (due, missed)
    }

    /// Latest run in (after, upTo].
    static func latestOccurrence(of rule: ScheduleRule, after: Date, upTo: Date, calendar: Calendar) -> Date? {
        // A weekly rule always has a run within any 8 days, so a longer window adds nothing.
        var cursor = max(after, upTo - 8 * 86_400)
        var last: Date?
        while let next = nextOccurrence(of: rule, after: cursor, calendar: calendar), next <= upTo {
            last = next
            cursor = next
        }
        return last
    }

    /// Pairs of rules with the same group and hour:minute, at least one shared weekday, and different actions.
    public static func conflicts(in rules: [ScheduleRule]) -> [(UUID, UUID)] {
        var pairs: [(UUID, UUID)] = []
        for i in rules.indices {
            for j in rules.indices where j > i {
                let a = rules[i], b = rules[j]
                if a.groupID == b.groupID, a.hour == b.hour, a.minute == b.minute,
                   a.action != b.action, !a.weekdays.isDisjoint(with: b.weekdays) {
                    pairs.append((a.id, b.id))
                }
            }
        }
        return pairs
    }

    /// Day part is "Today", "Tomorrow", a weekday name within the week, or "Sep 25"; time is "18:00".
    public static func relativeParts(_ date: Date, now: Date, calendar: Calendar) -> (day: String, time: String) {
        let time = String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let day = switch days {
        case 0: "Today"
        case 1: "Tomorrow"
        case 2..<7: weekdayLong(calendar.component(.weekday, from: date))
        default: "\(months[calendar.component(.month, from: date) - 1]) \(calendar.component(.day, from: date))"
        }
        return (day, time)
    }

    /// "Today, 18:00" / "Monday, 08:30"
    public static func relativeLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let parts = relativeParts(date, now: now, calendar: calendar)
        return "\(parts.day), \(parts.time)"
    }
}
