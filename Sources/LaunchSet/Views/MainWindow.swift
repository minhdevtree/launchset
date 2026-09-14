import LaunchSetCore
import SwiftUI

enum SidebarItem: Hashable {
    case group(UUID), schedules, history
}

struct MainWindow: View {
    @Environment(AppStore.self) private var store
    @ViewState private var selection: SidebarItem?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(store.config.groups) { group in
                        Label(group.name.isEmpty ? "Untitled" : group.name, systemImage: group.symbol)
                            .tag(SidebarItem.group(group.id))
                            .contextMenu {
                                Button("Force Close…") { store.confirmForceClose(group.id) }
                                .disabled(group.plan(for: .close).quit.isEmpty)
                                Divider()
                                Button("Delete Group…", role: .destructive) { store.deleteGroup(group.id) }
                            }
                    }
                    .onMove { store.config.groups.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    HStack {
                        Text("Groups")
                        Spacer()
                        Button { addGroup() } label: { Image(systemName: "plus") }
                            .buttonStyle(.borderless)
                            .help("New Group")
                    }
                }
                Section {
                    Label("Schedules", systemImage: "calendar").tag(SidebarItem.schedules)
                    Label("History", systemImage: "clock.arrow.circlepath").tag(SidebarItem.history)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                if store.config.rules.contains(where: \.isEnabled), store.loginItemStatus != .enabled {
                    loginBanner
                }
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            store.refreshLoginItem()
            if selection == nil, let first = store.config.groups.first { selection = .group(first.id) }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .group(let id) where store.group(id) != nil:
            GroupDetailView(groupID: id).id(id)
        case .schedules:
            SchedulesView()
        case .history:
            HistoryView()
        default:
            if store.config.groups.isEmpty {
                ContentUnavailableView {
                    Label("No groups yet", systemImage: "square.stack")
                } description: {
                    Text("Create a group to open or close several apps at once.")
                } actions: {
                    Button("Create Group") { addGroup() }
                }
            } else {
                ContentUnavailableView("Select a group", systemImage: "square.stack")
            }
        }
    }

    private var loginBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Schedules only run while LaunchSet is open. Turn on Launch at login so you don't miss any.")
            Spacer()
            Button("Turn On") { store.setLaunchAtLogin(true) }
        }
        .padding(10)
        .background(.orange.opacity(0.12))
    }

    private func addGroup() {
        selection = .group(store.addGroup())
    }
}
