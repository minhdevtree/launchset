import LaunchSetCore
import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History").font(.title2.bold())
                Spacer()
                Button("Clear History") { store.clearHistory() }
                    .disabled(store.history.isEmpty)
            }
            .padding(16)

            if store.history.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Every open or close, manual or scheduled, shows up here."))
            } else {
                List(store.history) { record in
                    if record.results.isEmpty {
                        Text(record.line(now: .now, calendar: .current))
                    } else {
                        DisclosureGroup {
                            ForEach(Array(record.results.enumerated()), id: \.offset) { _, result in
                                LabeledContent(result.name, value: result.label)
                            }
                        } label: {
                            Text(record.line(now: .now, calendar: .current))
                        }
                    }
                }
            }
        }
    }
}
