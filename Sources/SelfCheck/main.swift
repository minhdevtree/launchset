import Foundation
import LaunchSetCore

nonisolated(unsafe) var failures = 0
func check(_ cond: Bool, _ name: String) {
    if cond { print("✅ \(name)") } else { failures += 1; print("❌ \(name)") }
}

func calendar(_ tz: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!
    return c
}

func date(_ s: String, _ cal: Calendar) -> Date {
    let f = DateFormatter()
    f.calendar = cal
    f.timeZone = cal.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.date(from: s)!
}

let vn = calendar("Asia/Ho_Chi_Minh")
func vnd(_ s: String) -> Date { date(s, vn) }
let group = UUID()
let weekdays: Set<Int> = [2, 3, 4, 5, 6]
let settings = AppSettings() // warn 2, grace 15
// 2026-09-18 is a Friday, 2026-09-16 a Wednesday.

let close18 = ScheduleRule(groupID: group, action: .close, hour: 18, minute: 0, weekdays: weekdays)
let open18 = ScheduleRule(groupID: group, action: .open, hour: 18, minute: 0, weekdays: weekdays)

// 1-3: nextOccurrence
check(Schedule.nextOccurrence(of: close18, after: vnd("2026-09-18 18:00:00"), calendar: vn) == vnd("2026-09-21 18:00:00"),
      "1. Fri 18:00:00 exactly -> next Mon 18:00")
check(Schedule.nextOccurrence(of: close18, after: vnd("2026-09-18 17:59:00"), calendar: vn) == vnd("2026-09-18 18:00:00"),
      "2. Fri 17:59 -> Fri 18:00")
let weekend = ScheduleRule(groupID: group, action: .open, hour: 9, minute: 0, weekdays: [7, 1])
check(Schedule.nextOccurrence(of: weekend, after: vnd("2026-09-16 10:00:00"), calendar: vn) == vnd("2026-09-19 09:00:00"),
      "3. Weekend rule, after Wed -> Sat")

// 4-9: evaluate
var r = Schedule.evaluate(rules: [close18], settings: settings, from: vnd("2026-09-18 17:59:50"), now: vnd("2026-09-18 18:00:05"), calendar: vn)
check(r.due.contains { $0.kind == .run && $0.occurrence == vnd("2026-09-18 18:00:00") } && r.missed.isEmpty,
      "4. (17:59:50, 18:00:05] has a run in due")

r = Schedule.evaluate(rules: [open18], settings: settings, from: vnd("2026-09-18 17:00:00"), now: vnd("2026-09-18 18:10:00"), calendar: vn)
check(r.due.map(\.kind) == [.run] && r.missed.isEmpty, "5a. Asleep until 18:10, grace 15 -> due")
r = Schedule.evaluate(rules: [open18], settings: settings, from: vnd("2026-09-18 17:00:00"), now: vnd("2026-09-18 18:20:00"), calendar: vn)
check(r.due.isEmpty && r.missed.map(\.kind) == [.run], "5b. Asleep until 18:20, grace 15 -> missed")

let daily = ScheduleRule(groupID: group, action: .open, hour: 9, minute: 0, weekdays: Set(1...7))
r = Schedule.evaluate(rules: [daily], settings: settings, from: vnd("2026-09-16 10:00:00"), now: vnd("2026-09-19 10:00:00"), calendar: vn)
check(r.due.count + r.missed.count == 1 && r.missed.first?.occurrence == vnd("2026-09-19 09:00:00"),
      "6. Asleep 3 days over a daily rule -> exactly 1 event, the latest")

r = Schedule.evaluate(rules: [close18, open18], settings: settings, from: vnd("2026-09-18 17:57:00"), now: vnd("2026-09-18 17:58:30"), calendar: vn)
check(r.due == [DueEvent(ruleID: close18.id, kind: .warn, occurrence: vnd("2026-09-18 18:00:00"), fireAt: vnd("2026-09-18 17:58:00"))],
      "7. Close 18:00 with 2 min warning -> warn at 17:58; open rules never warn")

r = Schedule.evaluate(rules: [close18], settings: settings, from: vnd("2026-09-18 18:10:00"), now: vnd("2026-09-18 17:00:00"), calendar: vn)
check(r.due.isEmpty && r.missed.isEmpty, "8. from > now -> empty")

var disabled = daily
disabled.isEnabled = false
r = Schedule.evaluate(rules: [disabled], settings: settings, from: vnd("2026-09-10 00:00:00"), now: vnd("2026-09-19 10:00:00"), calendar: vn)
check(r.due.isEmpty && r.missed.isEmpty, "9. Disabled rules never appear")

let early = ScheduleRule(groupID: group, action: .open, hour: 17, minute: 59, weekdays: weekdays)
r = Schedule.evaluate(rules: [close18, early], settings: AppSettings(warnBeforeCloseMinutes: 0),
                      from: vnd("2026-09-18 17:50:00"), now: vnd("2026-09-18 18:01:00"), calendar: vn)
check(r.due.map(\.ruleID) == [early.id, close18.id], "9b. Sorted by fireAt")

// 10: conflicts
let weekendClose = ScheduleRule(groupID: group, action: .close, hour: 18, minute: 0, weekdays: [7, 1])
let pairs = Schedule.conflicts(in: [close18, open18, weekendClose])
check(pairs.count == 1 && pairs[0] == (close18.id, open18.id), "10. conflicts finds overlapping days, ignores disjoint days")

// 11: weekday map
check(Schedule.displayWeekdays == [2, 3, 4, 5, 6, 7, 1], "11. displayWeekdays")
check(Schedule.displayWeekdays.map(Schedule.weekdayShort) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], "11b. weekdayShort")
check(ScheduleRule(groupID: group, action: .open, hour: 8, minute: 5, weekdays: [1, 2, 7]).daysLabel == "Mon Sat Sun", "11c. daysLabel")

// 12: Config roundtrip
let config = Config(groups: [AppGroup(id: group, name: "Work", symbol: "briefcase",
                                      apps: [AppRef(bundleID: "com.apple.TextEdit", name: "TextEdit", lastKnownPath: "/System/Applications/TextEdit.app", role: .closeOnOpen)],
                                      launchDelaySeconds: 3, hideAfterOpen: true, quitPolicy: .forceQuit)],
                    rules: [close18, weekend], settings: AppSettings(warnBeforeCloseMinutes: 5, schedulesPaused: true))
let decoded = try! JSON.decoder().decode(Config.self, from: try! JSON.encoder().encode(config))
check(decoded == config, "12. Config survives encode/decode unchanged")

// 13: DST
let ny = calendar("America/New_York")
let dst = ScheduleRule(groupID: group, action: .open, hour: 2, minute: 30, weekdays: Set(1...7))
let first = Schedule.nextOccurrence(of: dst, after: date("2027-03-14 00:00:00", ny), calendar: ny)
let second = first.flatMap { Schedule.nextOccurrence(of: dst, after: $0, calendar: ny) }
check(first.map { ny.component(.day, from: $0) } == 14 && second.map { ny.component(.day, from: $0) } == 15,
      "13. DST 2027-03-14 02:30 -> exactly once that day")
let fallBack = ScheduleRule(groupID: group, action: .open, hour: 1, minute: 30, weekdays: Set(1...7))
let fb1 = Schedule.nextOccurrence(of: fallBack, after: date("2027-11-07 00:00:00", ny), calendar: ny)
let fb2 = fb1.flatMap { Schedule.nextOccurrence(of: fallBack, after: $0, calendar: ny) }
check(fb1.map { ny.component(.day, from: $0) } == 7 && fb2.map { ny.component(.day, from: $0) } == 8,
      "13b. Repeated hour 2027-11-07 01:30 -> first one only")

// 17: app roles
let te = AppRef(bundleID: "te", name: "TextEdit", lastKnownPath: "")
let csm = AppRef(bundleID: "csm", name: "Claude Session Manager", lastKnownPath: "", role: .openOnly)
let slack = AppRef(bundleID: "slack", name: "Slack", lastKnownPath: "", role: .closeOnOpen)
let mixed = AppGroup(name: "Agent", apps: [csm, te, slack])
check(mixed.plan(for: .open).open.map(\.bundleID) == ["csm", "te"] && mixed.plan(for: .open).quit.map(\.bundleID) == ["slack"],
      "17a. Open opens open-only and default apps, quits close-on-open apps")
check(mixed.plan(for: .close).open.isEmpty && mixed.plan(for: .close).quit.map(\.bundleID) == ["te"],
      "17b. Close quits only default apps")
let oldJSON = #"{"bundleID":"com.apple.TextEdit","name":"TextEdit","lastKnownPath":"/System/Applications/TextEdit.app"}"#
check((try? JSON.decoder().decode(AppRef.self, from: Data(oldJSON.utf8)))?.role == .openAndClose, "17c. AppRef without role decodes as open and close")
let focus = RunRecord(date: .now, groupID: group, groupName: "Agent", action: .open, source: .manual, results: [
    AppResult(bundleID: "csm", name: "CSM", outcome: .opened), AppResult(bundleID: "slack", name: "Slack", outcome: .closed),
    AppResult(bundleID: "mail", name: "Mail", outcome: .notClosed),
])
check(focus.flash == "Opened 1 of 1, closed 1 of 2", "17d. flash for Open that also closes apps")
check(RunRecord(date: .now, groupID: group, groupName: "A", action: .close, source: .manual,
                results: [AppResult(bundleID: "a", name: "A", outcome: .closed), AppResult(bundleID: "b", name: "B", outcome: .notClosed)]).flash
      == "Closed 1 of 2 apps", "17e. flash for plain Close")

// Labels
check(Schedule.relativeLabel(vnd("2026-09-18 18:00:00"), now: vnd("2026-09-18 09:00:00"), calendar: vn) == "Today, 18:00", "14a. Today")
check(Schedule.relativeLabel(vnd("2026-09-21 08:30:00"), now: vnd("2026-09-18 19:00:00"), calendar: vn) == "Monday, 08:30", "14b. Weekday")
let record = RunRecord(date: .now, groupID: group, groupName: "Work", action: .close, source: .scheduled, results: [
    AppResult(bundleID: "a", name: "A", outcome: .closed), AppResult(bundleID: "b", name: "B", outcome: .notClosed),
    AppResult(bundleID: "c", name: "C", outcome: .closed),
])
check(record.summary == "2 closed, 1 still open", "15. RunRecord.summary")
check(Blocklist.reason(bundleID: "com.apple.finder", name: "Finder") == "You can't add Finder because macOS needs it running."
      && Blocklist.reason(bundleID: "com.apple.TextEdit", name: "TextEdit") == nil, "16. Blocklist")

if failures == 0 { print("All checks passed") } else { print("\(failures) check(s) failed") }
exit(failures == 0 ? 0 : 1)
