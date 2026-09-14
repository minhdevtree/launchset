import LaunchSetCore
import SwiftUI

struct SchedulesView: View {
    @Environment(AppStore.self) private var store
    @ViewState private var selection: Set<UUID> = []
    @ViewState private var editing: ScheduleRule?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Schedules").font(.title2.bold())
                Spacer()
                Button("Edit…") { edit(selection) }
                    .disabled(selection.count != 1)
                Button("Add Schedule") { addRule() }
                    .disabled(store.config.groups.isEmpty)
            }
            .padding(16)

            if store.config.rules.isEmpty {
                ContentUnavailableView {
                    Label("No schedules yet", systemImage: "calendar")
                } description: {
                    Text("Add a schedule to open or close a group at a set time.")
                }
            } else {
                Table(store.config.rules, selection: $selection) {
                    TableColumn("On") { rule in
                        Toggle("On", isOn: store.enabledBinding(rule.id)).labelsHidden()
                    }
                    .width(32)
                    TableColumn("Group") { rule in Text(store.group(rule.groupID)?.name ?? "Deleted group") }
                    TableColumn("Action") { rule in Text(rule.action.label) }
                        .width(60)
                    TableColumn("Time") { rule in Text(rule.timeLabel).monospacedDigit() }
                        .width(50)
                    TableColumn("Days") { rule in Text(rule.daysLabel) }
                    TableColumn("Next Run") { rule in Text(store.nextLabel(rule)) }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Edit…") { edit(ids) }.disabled(ids.count != 1)
                    Button("Delete", role: .destructive) { store.deleteRules(ids) }
                } primaryAction: { ids in
                    edit(ids)
                }
                .onDeleteCommand { store.deleteRules(selection) }
            }
        }
        .sheet(item: $editing) { RuleEditor(rule: $0) }
    }

    private func edit(_ ids: Set<UUID>) {
        guard ids.count == 1, let id = ids.first else { return }
        editing = store.rule(id)
    }

    private func addRule() {
        guard let group = store.config.groups.first else { return }
        editing = ScheduleRule(groupID: group.id, action: .open, hour: 9, minute: 0, weekdays: [2, 3, 4, 5, 6])
    }
}

struct RuleEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ViewState var rule: ScheduleRule

    var body: some View {
        let isNew = store.rule(rule.id) == nil
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Picker("Group", selection: $rule.groupID) {
                    ForEach(store.config.groups) { Text($0.name).tag($0.id) }
                }
                Picker("Action", selection: $rule.action) {
                    ForEach(GroupAction.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                LabeledContent("Days") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            ForEach(Schedule.displayWeekdays, id: \.self) { day in
                                Toggle(Schedule.weekdayShort(day), isOn: dayBinding(day)).toggleStyle(.button)
                            }
                        }
                        HStack(spacing: 4) {
                            Button("Every Day") { rule.weekdays = Set(1...7) }
                            Button("Weekdays") { rule.weekdays = [2, 3, 4, 5, 6] }
                            Button("Weekends") { rule.weekdays = [7, 1] }
                        }
                        .controlSize(.small)
                        if rule.weekdays.isEmpty {
                            Text("Pick at least one day").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                if let conflict {
                    Label(conflict, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    store.upsertRule(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.weekdays.isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: .now) ?? .now },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                rule.hour = c.hour ?? 0
                rule.minute = c.minute ?? 0
            })
    }

    private func dayBinding(_ day: Int) -> Binding<Bool> {
        Binding(get: { rule.weekdays.contains(day) },
                set: { on in if on { rule.weekdays.insert(day) } else { rule.weekdays.remove(day) } })
    }

    private var conflict: String? {
        let others = store.config.rules.filter { $0.id != rule.id }
        guard let pair = Schedule.conflicts(in: others + [rule]).first(where: { $0.0 == rule.id || $0.1 == rule.id }),
              let other = others.first(where: { $0.id == pair.0 || $0.id == pair.1 })
        else { return nil }
        return "Same time as the \(other.action.label) \(other.timeLabel) schedule for this group."
    }
}
