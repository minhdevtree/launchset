import LaunchSetCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppStore.self) private var store
    @Environment(Scheduler.self) private var scheduler
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(12)
            Divider()
            if store.config.groups.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No groups yet.").foregroundStyle(.secondary)
                    Button("Create Your First Group") { showManager() }
                }
                .padding(12)
            } else {
                VStack(spacing: 2) {
                    ForEach(store.config.groups) { GroupRow(group: $0) }
                }
                .padding(.vertical, 6)
            }
            if !scheduler.warnings.isEmpty {
                Divider()
                warnings.padding(12)
            }
            Divider()
            VStack(spacing: 0) {
                MenuButton("Manage Groups…") { showManager() }
                MenuButton("Settings…") {
                    openSettings()
                    NSApp.activate()
                }
                MenuButton("Quit LaunchSet") { NSApp.terminate(nil) }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("LaunchSet").font(.headline)
                Spacer()
                let paused = store.config.settings.schedulesPaused
                Button {
                    scheduler.setPaused(!paused)
                } label: {
                    Label(paused ? "Resume Schedules" : "Pause Schedules", systemImage: paused ? "play.fill" : "pause.fill")
                }
                .controlSize(.small)
            }
            TimelineView(.everyMinute) { context in
                Text(scheduler.nextLine(now: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(scheduler.warnings) { w in
                VStack(alignment: .trailing, spacing: 6) {
                    Label {
                        let time = Schedule.relativeParts(w.closeAt, now: .now, calendar: .current).time
                        Text("Closing \"\(store.group(w.groupID)?.name ?? "")\" at \(time)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    HStack {
                        Button("Snooze \(store.config.settings.snoozeMinutes) min") { scheduler.snooze(w.key) }
                        Button("Skip This Time") { scheduler.skip(w.key) }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func showManager() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

private struct GroupRow: View {
    @Environment(AppStore.self) private var store
    let group: AppGroup

    var body: some View {
        let busy = store.runner.isBusy(group.id)
        HStack(spacing: 8) {
            Image(systemName: group.symbol).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).lineLimit(1)
                Text(store.flash[group.id] ?? store.runningLabel(group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button("Open") { Task { await store.run(.open, groupID: group.id, source: .manual) } }
                .disabled(busy)
            Button("Close") { Task { await store.run(.close, groupID: group.id, source: .manual) } }
                .disabled(busy)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Force Close…") { store.confirmForceClose(group.id) }
                .disabled(group.plan(for: .close).quit.isEmpty)
        }
    }
}

/// A full-width row that looks like a menu item.
private struct MenuButton: View {
    let title: String
    let action: () -> Void
    @ViewState private var hovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(hovering ? Color.accentColor.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(hovering ? .white : .primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 4)
    }
}
