import AppKit
import LaunchSetCore
import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @ViewState private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { store.loginItemStatus == .enabled },
                                                        set: { store.setLaunchAtLogin($0) }))
                if store.loginItemStatus == .requiresApproval {
                    HStack {
                        Text("Allow LaunchSet in Login Items to finish turning this on.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }

            Section("Notifications") {
                LabeledContent("Permission") {
                    HStack {
                        Text(permissionLabel)
                        if notificationStatus == .denied {
                            Button("Open System Settings") {
                                let url = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Blocklist.ownBundleID)"
                                NSWorkspace.shared.open(URL(string: url)!)
                            }
                        }
                    }
                }
                Toggle("Also notify when a scheduled run succeeds", isOn: $store.config.settings.notifyOnSuccess)
            }

            Section("Schedules") {
                Picker("Warn before closing", selection: $store.config.settings.warnBeforeCloseMinutes) {
                    Text("Off").tag(0)
                    ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Snooze for", selection: $store.config.settings.snoozeMinutes) {
                    ForEach([5, 10, 15], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Wait for apps to quit", selection: $store.config.settings.quitTimeoutSeconds) {
                    ForEach([5, 15, 30, 60], id: \.self) { Text("\($0) sec").tag($0) }
                }
                Picker("Catch up on missed schedules up to", selection: $store.config.settings.missedGraceMinutes) {
                    ForEach([5, 15, 30, 60], id: \.self) { Text("\($0) min late").tag($0) }
                }
            }

            Section("Configuration") {
                HStack {
                    Button("Export Configuration…") { store.exportConfig() }
                    Button("Import Configuration…") { store.importConfig() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private var permissionLabel: String {
        switch notificationStatus {
        case .authorized, .provisional: "Allowed"
        case .denied: "Turned off"
        default: "Not asked yet"
        }
    }

    private func refresh() async {
        notificationStatus = await Notifier.authorizationStatus()
        store.refreshLoginItem()
    }
}
