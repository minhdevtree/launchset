import AppKit
import LaunchSetCore
import SwiftUI

struct GroupDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(Scheduler.self) private var scheduler
    let groupID: UUID
    @ViewState private var selectedApps: Set<String> = []
    @ViewState private var editingRule: ScheduleRule?
    @ViewState private var errorMessage: String?

    private var group: Binding<AppGroup> {
        Binding(get: { store.group(groupID) ?? AppGroup(name: "") }, set: { store.updateGroup($0) })
    }

    var body: some View {
        let g = group.wrappedValue
        VStack(spacing: 0) {
            header(g).padding(16)
            List(selection: $selectedApps) {
                appsSection(g)
                optionsSection
                schedulesSection
            }
            .onDeleteCommand { removeApps(selectedApps) }
            .dropDestination(for: URL.self) { urls, _ in
                errorMessage = store.addApps(urls: urls, to: groupID)
                return true
            }
        }
        .sheet(item: $editingRule) { RuleEditor(rule: $0) }
        .alert("Some apps weren't added", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func header(_ g: AppGroup) -> some View {
        HStack(spacing: 10) {
            Picker("Icon", selection: group.symbol) {
                ForEach(AppGroup.symbols, id: \.self) { Image(systemName: $0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            TextField("Group name", text: group.name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .frame(maxWidth: 280)
            Spacer()
            if let flash = store.flash[groupID] {
                Text(flash).foregroundStyle(.secondary)
            }
            let busy = store.runner.isBusy(groupID)
            if busy { ProgressView().controlSize(.small) }
            Button("Open Group") { Task { await store.run(.open, groupID: groupID, source: .manual) } }
                .disabled(busy)
            Button("Close Group") { Task { await store.run(.close, groupID: groupID, source: .manual) } }
                .disabled(busy)
        }
    }

    private func appsSection(_ g: AppGroup) -> some View {
        Section {
            ForEach(g.apps) { app in
                AppRow(app: app, role: roleBinding(app.bundleID), isRunning: store.running.contains(app.bundleID))
                    .contextMenu {
                        Button("Remove from Group") {
                            removeApps(selectedApps.contains(app.bundleID) ? selectedApps : [app.bundleID])
                        }
                    }
            }
            .onMove { group.wrappedValue.apps.move(fromOffsets: $0, toOffset: $1) }
            Text(g.apps.isEmpty ? "Drop .app files here, or use the buttons above." : "Drop .app files here to add more.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .selectionDisabled()
            if g.apps.contains(where: { $0.role != .openAndClose }) {
                Text("Open only apps keep running when you close the group. Close on open apps quit when the group opens and stay untouched when it closes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
        } header: {
            HStack {
                Text("Apps")
                Spacer()
                Button("Add App…") { chooseApps() }
                Menu("Add Running App") {
                    ForEach(AppStore.runningAppRefs()) { ref in
                        Button(ref.name) { errorMessage = store.addApps([ref], to: groupID) }
                    }
                }
                .fixedSize()
            }
            .controlSize(.small)
        }
    }

    private var optionsSection: some View {
        Section("Options") {
            HStack {
                Text("Wait between app launches")
                Spacer()
                let delay = Binding(get: { group.wrappedValue.launchDelaySeconds },
                                    set: { group.wrappedValue.launchDelaySeconds = min(30, max(0, $0)) })
                TextField("", value: delay, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                Stepper("", value: delay, in: 0...30).labelsHidden()
                Text("seconds")
            }
            .selectionDisabled()
            Toggle("Hide apps after opening", isOn: group.hideAfterOpen)
                .selectionDisabled()
            Picker("If an app won't quit", selection: group.quitPolicy) {
                Text("Leave it open and tell me").tag(QuitPolicy.leaveAndNotify)
                Text("Force quit (unsaved changes are lost)").tag(QuitPolicy.forceQuit)
            }
            .selectionDisabled()
        }
    }

    private var schedulesSection: some View {
        Section {
            let rules = store.config.rules.filter { $0.groupID == groupID }
            if rules.isEmpty {
                Text("No schedules yet. Add one to open or close this group at a set time.")
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
            ForEach(rules) { rule in
                HStack {
                    Toggle("On", isOn: store.enabledBinding(rule.id)).labelsHidden()
                    Text(rule.action.label).frame(width: 44, alignment: .leading)
                    Text(rule.timeLabel).monospacedDigit().frame(width: 48, alignment: .leading)
                    Text(rule.daysLabel)
                    Spacer()
                    Text(rule.isEnabled ? "Next: \(scheduler.nextLabel(rule))" : "Off").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { editingRule = rule }
                .contextMenu {
                    Button("Edit…") { editingRule = rule }
                    Button("Delete", role: .destructive) { store.deleteRules([rule.id]) }
                }
                .selectionDisabled()
            }
        } header: {
            HStack {
                Text("Schedules for this group")
                Spacer()
                Button("Add Schedule") {
                    editingRule = ScheduleRule(groupID: groupID, action: .open, hour: 9, minute: 0, weekdays: [2, 3, 4, 5, 6])
                }
                .controlSize(.small)
            }
        }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK else { return }
        errorMessage = store.addApps(urls: panel.urls, to: groupID)
    }

    private func roleBinding(_ bundleID: String) -> Binding<AppRole> {
        Binding(get: { group.wrappedValue.apps.first { $0.bundleID == bundleID }?.role ?? .openAndClose },
                set: { role in
                    guard let i = group.wrappedValue.apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
                    group.wrappedValue.apps[i].role = role
                })
    }

    private func removeApps(_ ids: Set<String>) {
        group.wrappedValue.apps.removeAll { ids.contains($0.bundleID) }
        selectedApps.subtract(ids)
    }
}

private struct AppRow: View {
    let app: AppRef
    @Binding var role: AppRole
    let isRunning: Bool

    var body: some View {
        let url = AppRunner.appURL(app)
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Image(nsImage: NSWorkspace.shared.icon(forFile: url?.path ?? app.lastKnownPath))
                .resizable()
                .frame(width: 20, height: 20)
            Text(app.name).frame(minWidth: 120, alignment: .leading)
            Text(app.bundleID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Picker("Role", selection: $role) {
                ForEach(AppRole.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            .help("What the group's Open and Close do to this app")
            if isRunning {
                Label("Running", systemImage: "circle.fill").foregroundStyle(.green)
            } else if url == nil {
                Label("Not found", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Can't find this app. It may have been deleted or moved.")
            } else {
                Label("Not running", systemImage: "circle").foregroundStyle(.secondary)
            }
        }
        .labelStyle(StatusLabelStyle())
    }
}

private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title.foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
