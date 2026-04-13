import SwiftUI
import RemoSwift

struct ActivityLogView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.activityLog.isEmpty {
                    ContentUnavailableView(
                        "No Activity",
                        systemImage: "waveform.slash",
                        description: Text("RPC calls will appear here in real time.\nTry: remo call __ping '{}' -a 127.0.0.1:\(Remo.port)")
                    )
                } else {
                    List(store.activityLog) { entry in
                        LogEntryRow(entry: entry)
                    }
                    .animation(.default, value: store.activityLog.map(\.id))
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                if !store.activityLog.isEmpty {
                    Button("Clear") {
                        withAnimation { store.activityLog.removeAll() }
                    }
                }
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.capability)
                    .font(.headline.monospaced())
                    .foregroundStyle(.primary)
                Spacer()
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            if entry.params != "{}" {
                Text(entry.params)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text("\u{2192} \(entry.result)")
                .font(.caption.monospaced())
                .foregroundStyle(.green)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
