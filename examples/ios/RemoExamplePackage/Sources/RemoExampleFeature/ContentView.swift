import SwiftUI
import RemoSwift

// MARK: - Models

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let capability: String
    let params: String
    let result: String
}

// MARK: - App Store

@Observable
public final class AppStore: @unchecked Sendable {
    public var counter: Int = 0
    public var username: String = "Guest"
    public var items: [String] = ["Item A", "Item B", "Item C"]
    public var currentRoute: String = "home"

    var accentColorName: String = "blue"
    var toastMessage: String?
    var showConfetti: Bool = false
    var activityLog: [LogEntry] = []

    public init() {}

    var accentColor: Color {
        switch accentColorName {
        case "red": .red
        case "green": .green
        case "orange": .orange
        case "purple": .purple
        case "pink": .pink
        case "yellow": .yellow
        case "mint": .mint
        case "teal": .teal
        default: .blue
        }
    }

    func log(capability: String, params: String, result: String) {
        let entry = LogEntry(
            timestamp: .now,
            capability: capability,
            params: params,
            result: result
        )
        DispatchQueue.main.async { [self] in
            activityLog.insert(entry, at: 0)
            if activityLog.count > 200 {
                activityLog = Array(activityLog.prefix(200))
            }
        }
    }
}

// MARK: - Page-Level Capability Helpers

/// Register page-level capabilities from a non-isolated context.
/// Avoids Swift 6 MainActor isolation issues when Remo handlers
/// are invoked from background threads.
func registerHomeCapabilities(store: AppStore) {
    Remo.register("counter.increment") { params in
        let amount = params["amount"] as? Int ?? 1
        DispatchQueue.main.async { store.counter += amount }
        return ["status": "ok", "amount": amount]
    }
}

func registerItemsCapabilities(store: AppStore) {
    Remo.register("items.add") { params in
        let name = params["name"] as? String ?? "New Item"
        DispatchQueue.main.async {
            withAnimation { store.items.append(name) }
        }
        return ["status": "ok", "name": name]
    }
    Remo.register("items.remove") { params in
        let name = params["name"] as? String ?? ""
        DispatchQueue.main.async {
            withAnimation {
                if let idx = store.items.firstIndex(of: name) {
                    store.items.remove(at: idx)
                }
            }
        }
        return ["status": "ok", "name": name]
    }
    Remo.register("items.clear") { _ in
        DispatchQueue.main.async {
            withAnimation { store.items.removeAll() }
        }
        return ["status": "ok"]
    }
}

func registerDetailCapabilities(item: String) {
    Remo.register("detail.getInfo") { _ in
        return ["item": item]
    }
}

// MARK: - Remo Setup

public func setupRemo(store: AppStore) {
    func logged(
        _ name: String,
        handler: @escaping ([String: Any]) -> [String: Any]
    ) {
        Remo.register(name) { params in
            let paramsJSON = (try? JSONSerialization.data(withJSONObject: params))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let result = handler(params)
            let resultJSON = (try? JSONSerialization.data(withJSONObject: result))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            store.log(capability: name, params: paramsJSON, result: resultJSON)
            return result
        }
    }

    // -- Existing capabilities ------------------------------------------------

    logged("navigate") { params in
        let route = params["route"] as? String ?? "home"
        DispatchQueue.main.async { store.currentRoute = route }
        return ["status": "ok", "route": route]
    }

    logged("state.get") { params in
        let key = params["key"] as? String ?? ""
        switch key {
        case "counter": return ["value": store.counter]
        case "username": return ["value": store.username]
        case "items": return ["value": store.items]
        case "currentRoute": return ["value": store.currentRoute]
        case "accentColor": return ["value": store.accentColorName]
        default: return ["error": "unknown key: \(key)"]
        }
    }

    logged("state.set") { params in
        let key = params["key"] as? String ?? ""
        let intValue = params["value"] as? Int
        let stringValue = params["value"] as? String
        let arrayValue = params["value"] as? [String]
        DispatchQueue.main.async {
            switch key {
            case "counter": if let v = intValue { store.counter = v }
            case "username": if let v = stringValue { store.username = v }
            case "items": if let v = arrayValue { store.items = v }
            default: break
            }
        }
        return ["status": "ok"]
    }

    // -- UI effect capabilities -----------------------------------------------

    logged("ui.toast") { params in
        let message = params["message"] as? String ?? "Hello from Remo!"
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 0.4)) {
                store.toastMessage = message
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.3)) {
                    if store.toastMessage == message {
                        store.toastMessage = nil
                    }
                }
            }
        }
        return ["status": "ok"]
    }

    logged("ui.confetti") { _ in
        DispatchQueue.main.async {
            store.showConfetti = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                store.showConfetti = false
            }
        }
        return ["status": "ok"]
    }

    logged("ui.setAccentColor") { params in
        let color = params["color"] as? String ?? "blue"
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                store.accentColorName = color
            }
        }
        return ["status": "ok", "color": color]
    }

}

// MARK: - Root View

public struct ContentView: View {
    @Environment(AppStore.self) private var store

    public var body: some View {
        @Bindable var store = store
        ZStack(alignment: .top) {
            TabView(selection: $store.currentRoute) {
                HomeView()
                    .tag("home")
                    .tabItem { Label("Home", systemImage: "house") }

                ListPage()
                    .tag("items")
                    .tabItem { Label("Items", systemImage: "list.bullet") }

                ActivityLogView()
                    .tag("activity")
                    .tabItem { Label("Activity", systemImage: "waveform") }

                SettingsPage()
                    .tag("settings")
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
            .tint(store.accentColor)

            ToastOverlay()

            if store.showConfetti {
                ConfettiOverlay()
            }
        }
    }

    public init() {}
}

// MARK: - Home

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
                    CounterButton(label: "−", color: .red) {
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
                registerHomeCapabilities(store: store)
            }
            .onDisappear {
                Remo.unregister("counter.increment")
            }
        }
    }
}

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

// MARK: - Items

struct ListPage: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "tray",
                        description: Text("Add items remotely:\nremo call items.add '{\"name\": \"Hello\"}'")
                    )
                } else {
                    List {
                        ForEach(store.items, id: \.self) { item in
                            NavigationLink(item) {
                                DetailPage(item: item)
                            }
                        }
                        .onDelete { indexSet in
                            withAnimation { store.items.remove(atOffsets: indexSet) }
                        }
                    }
                    .animation(.default, value: store.items)
                }
            }
            .navigationTitle("Items (\(store.items.count))")
            .toolbar {
                if !store.items.isEmpty {
                    Button("Clear") {
                        withAnimation { store.items.removeAll() }
                    }
                }
            }
            .task {
                registerItemsCapabilities(store: store)
            }
            .onDisappear {
                Remo.unregister("items.add")
                Remo.unregister("items.remove")
                Remo.unregister("items.clear")
            }
        }
    }
}

struct DetailPage: View {
    let item: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.box")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(item)
                .font(.title)
            Text("Detail view for \(item)")
                .foregroundStyle(.secondary)
        }
        .navigationTitle(item)
        .task {
            registerDetailCapabilities(item: item)
        }
        .onDisappear {
            Remo.unregister("detail.getInfo")
        }
    }
}

// MARK: - Activity Log

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

            Text("→ \(entry.result)")
                .font(.caption.monospaced())
                .foregroundStyle(.green)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings

struct SettingsPage: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    @Bindable var s = store
                    TextField("Username", text: $s.username)
                }

                Section("Appearance") {
                    let colors = ["blue", "purple", "red", "green", "orange", "pink", "teal", "mint"]
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(colors, id: \.self) { name in
                            ColorDot(
                                name: name,
                                isSelected: store.accentColorName == name
                            ) {
                                withAnimation { store.accentColorName = name }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Remo") {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Remo.port > 0 ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(Remo.port > 0 ? "Running" : "Stopped")
                        }
                    }
                    LabeledContent("Port", value: "\(Remo.port)")
                    LabeledContent("Capabilities") {
                        Text("\(Remo.listCapabilities().count)")
                    }
                }

                Section("Try It") {
                    CopyableCommand(
                        label: "Toast",
                        command: "remo call -a 127.0.0.1:\(Remo.port) ui.toast '{\"message\": \"Hello!\"}'"
                    )
                    CopyableCommand(
                        label: "Confetti",
                        command: "remo call -a 127.0.0.1:\(Remo.port) ui.confetti '{}'"
                    )
                    CopyableCommand(
                        label: "Add Item",
                        command: "remo call -a 127.0.0.1:\(Remo.port) items.add '{\"name\": \"Remote\"}'"
                    )
                    CopyableCommand(
                        label: "Recolor",
                        command: "remo call -a 127.0.0.1:\(Remo.port) ui.setAccentColor '{\"color\": \"purple\"}'"
                    )
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct ColorDot: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    private var color: Color {
        switch name {
        case "red": .red
        case "green": .green
        case "orange": .orange
        case "purple": .purple
        case "pink": .pink
        case "yellow": .yellow
        case "mint": .mint
        case "teal": .teal
        default: .blue
        }
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.gradient)
                .frame(width: 36, height: 36)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}

struct CopyableCommand: View {
    let label: String
    let command: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.medium))
            Text(command)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            UIPasteboard.general.string = command
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { copied = false }
            }
        }
        .overlay(alignment: .trailing) {
            if copied {
                Text("Copied!")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }
}

// MARK: - Overlays

struct ToastOverlay: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let message = store.toastMessage {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.white.opacity(0.8))
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial.opacity(0.9))
            .background(Color.accentColor.opacity(0.85))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.top, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(100)
        }
    }
}

struct ConfettiOverlay: View {
    @State private var particles: [ConfettiParticle] = []

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
                    .opacity(particle.opacity)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear { startConfetti() }
    }

    private func startConfetti() {
        particles = (0..<80).map { _ in
            ConfettiParticle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: -20
                ),
                color: [Color.red, .blue, .green, .yellow, .purple, .orange, .pink].randomElement()!,
                size: CGFloat.random(in: 6...12),
                opacity: 1.0
            )
        }

        for i in particles.indices {
            let delay = Double.random(in: 0...0.5)
            let targetY = CGFloat.random(in: 200...UIScreen.main.bounds.height + 100)
            let targetX = particles[i].position.x + CGFloat.random(in: -80...80)

            withAnimation(.easeOut(duration: Double.random(in: 1.5...2.5)).delay(delay)) {
                particles[i].position = CGPoint(x: targetX, y: targetY)
                particles[i].opacity = 0
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    let color: Color
    let size: CGFloat
    var opacity: Double
}
