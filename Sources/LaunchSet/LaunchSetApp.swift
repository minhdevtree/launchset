import AppKit
import SwiftUI

// The macOS 27 SDK declares @State as a macro, but Command Line Tools ship without the SwiftUIMacros plugin,
// so `@State` fails to build there. The alias reaches the plain property wrapper on every SDK.
typealias ViewState = SwiftUI.State

@main
struct LaunchSetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        MenuBarExtra("LaunchSet", systemImage: "square.stack.3d.up") {
            MenuBarView()
                .environment(app.store)
                .environment(app.scheduler)
        }
        .menuBarExtraStyle(.window)

        Window("LaunchSet", id: "main") {
            MainWindow()
                .environment(app.store)
                .environment(app.scheduler)
                .showsInDock()
        }
        .defaultSize(width: 860, height: 600)

        Settings {
            SettingsView()
                .environment(app.store)
                .environment(app.scheduler)
                .showsInDock()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AppStore()
    let notifier = Notifier()
    lazy var scheduler = Scheduler(store: store, notifier: notifier)
    lazy var commandServer = CommandServer(store: store, scheduler: scheduler)

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The delegate has to be in place before launch finishes to receive taps that launched the app.
        notifier.setUp()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        scheduler.start()
        commandServer.start()
        if let notice = store.loadNotice {
            // Deferred: a modal started inside didFinishLaunching gets cancelled while SwiftUI sets up its scenes.
            Task { showAlert("LaunchSet couldn't read its configuration", notice) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }
}

/// The app has no Dock icon until a window is open, then it shows up in the Dock and in Command-Tab.
@MainActor
private enum DockPresence {
    static var openWindows = 0
}

extension View {
    func showsInDock() -> some View {
        onAppear {
            DockPresence.openWindows += 1
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            DockPresence.openWindows = max(0, DockPresence.openWindows - 1)
            if DockPresence.openWindows == 0 { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
