import AppKit
import LaunchSetCore
import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    enum Action { case snooze, skip }

    /// Called with the occurrence key when someone taps Snooze or Skip on a warning.
    var onAction: ((String, Action) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    func setUp() {
        center.delegate = self
        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func warn(key: String, groupName: String, appCount: Int, closeAt: Date, snoozeMinutes: Int) {
        // Registered on every warning so the Snooze title follows the current setting.
        center.setNotificationCategories([UNNotificationCategory(
            identifier: "CLOSE_WARNING",
            actions: [UNNotificationAction(identifier: "SNOOZE", title: "Snooze \(snoozeMinutes) min"),
                      UNNotificationAction(identifier: "SKIP", title: "Skip This Time")],
            intentIdentifiers: [])])
        let time = Schedule.relativeParts(closeAt, now: closeAt, calendar: .current).time
        post(id: key, title: "Closing \"\(groupName)\" soon",
             body: "\(appCount) \(appCount == 1 ? "app" : "apps") will close at \(time).",
             category: "CLOSE_WARNING", userInfo: ["key": key])
    }

    func post(id: String = UUID().uuidString, title: String, body: String, category: String = "", userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = userInfo
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func remove(_ id: String) {
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let key = response.notification.request.content.userInfo["key"] as? String
        let actionID = response.actionIdentifier
        await MainActor.run {
            guard let key else { return }
            switch actionID {
            case "SNOOZE": onAction?(key, .snooze)
            case "SKIP": onAction?(key, .skip)
            default: break
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
