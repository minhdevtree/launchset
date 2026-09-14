import Foundation

public struct AppRef: Codable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    public var lastKnownPath: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String, lastKnownPath: String) {
        self.bundleID = bundleID
        self.name = name
        self.lastKnownPath = lastKnownPath
    }
}

public enum QuitPolicy: String, Codable, CaseIterable, Sendable { case leaveAndNotify, forceQuit }

public struct AppGroup: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String            // SF Symbol
    public var apps: [AppRef]
    public var launchDelaySeconds: Int   // 0...30
    public var hideAfterOpen: Bool
    public var quitPolicy: QuitPolicy

    public init(id: UUID = UUID(), name: String, symbol: String = "square.stack", apps: [AppRef] = [],
                launchDelaySeconds: Int = 0, hideAfterOpen: Bool = false, quitPolicy: QuitPolicy = .leaveAndNotify) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.apps = apps
        self.launchDelaySeconds = launchDelaySeconds
        self.hideAfterOpen = hideAfterOpen
        self.quitPolicy = quitPolicy
    }

    public static let symbols = ["briefcase", "gamecontroller", "book", "hammer", "paintbrush", "music.note",
                                 "film", "message", "chart.bar", "house", "moon", "square.stack"]
}

public enum GroupAction: String, Codable, CaseIterable, Sendable {
    case open, close
    public var label: String { self == .open ? "Open" : "Close" }
}

public struct ScheduleRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var groupID: UUID
    public var action: GroupAction
    public var hour: Int                 // 0...23
    public var minute: Int               // 0...59
    public var weekdays: Set<Int>        // Calendar weekdays: 1 = Sun, 2 = Mon ... 7 = Sat
    public var isEnabled: Bool

    public init(id: UUID = UUID(), groupID: UUID, action: GroupAction, hour: Int, minute: Int,
                weekdays: Set<Int>, isEnabled: Bool = true) {
        self.id = id
        self.groupID = groupID
        self.action = action
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.isEnabled = isEnabled
    }

    public var timeLabel: String { String(format: "%02d:%02d", hour, minute) }
    /// "Mon Tue Wed", in display order (Monday first).
    public var daysLabel: String {
        Schedule.displayWeekdays.filter(weekdays.contains).map(Schedule.weekdayShort).joined(separator: " ")
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var warnBeforeCloseMinutes: Int   // 0 = off
    public var snoozeMinutes: Int
    public var quitTimeoutSeconds: Int
    public var missedGraceMinutes: Int
    public var notifyOnSuccess: Bool
    public var schedulesPaused: Bool

    public init(warnBeforeCloseMinutes: Int = 2, snoozeMinutes: Int = 10, quitTimeoutSeconds: Int = 15,
                missedGraceMinutes: Int = 15, notifyOnSuccess: Bool = false, schedulesPaused: Bool = false) {
        self.warnBeforeCloseMinutes = warnBeforeCloseMinutes
        self.snoozeMinutes = snoozeMinutes
        self.quitTimeoutSeconds = quitTimeoutSeconds
        self.missedGraceMinutes = missedGraceMinutes
        self.notifyOnSuccess = notifyOnSuccess
        self.schedulesPaused = schedulesPaused
    }
}

public struct Config: Codable, Hashable, Sendable {
    public var version: Int
    public var groups: [AppGroup]
    public var rules: [ScheduleRule]
    public var settings: AppSettings

    public init(version: Int = 1, groups: [AppGroup] = [], rules: [ScheduleRule] = [], settings: AppSettings = AppSettings()) {
        self.version = version
        self.groups = groups
        self.rules = rules
        self.settings = settings
    }
}

// MARK: - History

public enum RunSource: String, Codable, Sendable {
    case manual, scheduled
    public var label: String { self == .manual ? "Manual" : "Scheduled" }
}

public enum AppOutcome: String, Codable, Sendable {
    case opened, alreadyRunning, notFound, openFailed, closed, notRunning, notClosed, forceClosed

    public var label: String {
        switch self {
        case .opened: "Opened"
        case .alreadyRunning: "Already running"
        case .notFound: "Not found"
        case .openFailed: "Failed to open"
        case .closed: "Closed"
        case .notRunning: "Not running"
        case .notClosed: "Still open"
        case .forceClosed: "Force quit"
        }
    }

    /// The app ended up in the state the command asked for.
    public var isSuccess: Bool { ![.notFound, .openFailed, .notClosed].contains(self) }
}

public struct AppResult: Codable, Hashable, Sendable {
    public var bundleID: String
    public var name: String
    public var outcome: AppOutcome
    public var error: String?

    public init(bundleID: String, name: String, outcome: AppOutcome, error: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.outcome = outcome
        self.error = error
    }

    public var label: String {
        switch outcome {
        case .openFailed: "Failed to open: \(error ?? "unknown error")"
        case .notClosed: "Still open (it may be waiting for you to save a file)"
        default: outcome.label
        }
    }
}

public struct RunRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var groupID: UUID
    public var groupName: String
    public var action: GroupAction
    public var source: RunSource
    public var results: [AppResult]
    /// Set when the command did not run: missed, or skipped by the user.
    public var note: String?

    public init(id: UUID = UUID(), date: Date, groupID: UUID, groupName: String, action: GroupAction,
                source: RunSource, results: [AppResult] = [], note: String? = nil) {
        self.id = id
        self.date = date
        self.groupID = groupID
        self.groupName = groupName
        self.action = action
        self.source = source
        self.results = results
        self.note = note
    }

    /// "3 closed, 1 still open"
    public var summary: String {
        if let note { return note }
        if results.isEmpty { return "No apps in the group" }
        var counts: [(AppOutcome, Int)] = []
        for r in results {
            if let i = counts.firstIndex(where: { $0.0 == r.outcome }) { counts[i].1 += 1 } else { counts.append((r.outcome, 1)) }
        }
        return counts.map { "\($0.1) \($0.0.label.lowercased())" }.joined(separator: ", ")
    }
}

// MARK: - Shared

public enum Blocklist {
    public static let ownBundleID = "local.minhdevtree.launchset"
    public static let system: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.loginwindow",
        "com.apple.controlcenter", "com.apple.notificationcenterui",
    ]

    /// Why an app cannot be added, or nil when it can.
    public static func reason(bundleID: String, name: String) -> String? {
        if bundleID == ownBundleID { return "You can't add LaunchSet to its own groups." }
        if system.contains(bundleID) { return "You can't add \(name) because macOS needs it running." }
        return nil
    }

    public static func contains(_ bundleID: String) -> Bool { bundleID == ownBundleID || system.contains(bundleID) }
}

public enum JSON {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
