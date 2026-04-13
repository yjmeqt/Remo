import SwiftUI
import RemoSwift

struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                ConnectionBadge()

                Spacer()

                Text("Hello, \(store.username)!")
                    .font(.title2.weight(.medium))

                Text("\(store.counter)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(store.counter)))
                    .animation(.snappy, value: store.counter)

                Text("Counter")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.5)

                HStack(spacing: 16) {
                    CounterButton(label: "\u{2212}", color: .red) {
                        withAnimation { store.counter -= 1 }
                    }
                    CounterButton(label: "+", color: .green) {
                        withAnimation { store.counter += 1 }
                    }
                    CounterButton(label: "Reset", color: .secondary) {
                        withAnimation { store.counter = 0 }
                    }
                }

                Spacer()

                if store.currentRoute != "home" {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        Text(store.currentRoute)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding()
            .navigationTitle("Remo")
            .task {
                await #Remo {
                    struct CounterIncrementResponse: Encodable {
                        let status: String = "ok"
                        let amount: Int
                    }

                    enum CounterIncrement: RemoCapability {
                        static let name = "counter.increment"

                        struct Request: Decodable {
                            let amount: Int?
                        }

                        typealias Response = CounterIncrementResponse
                    }

                    await #remoScope {
                        #remoCap(CounterIncrement.self) { req in
                            let amount = req.amount ?? 1
                            Task { @MainActor in
                                withAnimation {
                                    store.counter += amount
                                }
                            }
                            return CounterIncrementResponse(amount: amount)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct CounterButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.title3.weight(.semibold))
                .frame(minWidth: 56, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }
}

struct ConnectionBadge: View {
    var body: some View {
        let port = Remo.port

        HStack(spacing: 8) {
            Circle()
                .fill(port > 0 ? .green : .red)
                .frame(width: 8, height: 8)

            if port > 0 {
                Text("Remo on port \(port)")
            } else {
                Text("Remo offline")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
