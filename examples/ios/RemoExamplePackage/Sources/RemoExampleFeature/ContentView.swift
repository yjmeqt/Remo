import SwiftUI
import RemoSwift

// MARK: - App Store

@Observable
public final class AppStore: @unchecked Sendable {
    public var counter: Int = 0
    public var username: String = "Guest"
    public var items: [String] = ["Item A", "Item B", "Item C"]
    public var currentRoute: String = "/"

    public init() {}
}

// MARK: - Remo Setup

public func setupRemo(store: AppStore) {
    Remo.start()

    Remo.register("navigate") { params in
        let route = params["route"] as? String ?? "/"
        DispatchQueue.main.async {
            store.currentRoute = route
        }
        return ["status": "ok", "route": route]
    }

    Remo.register("state.get") { params in
        let key = params["key"] as? String ?? ""
        switch key {
        case "counter":
            return ["value": store.counter]
        case "username":
            return ["value": store.username]
        case "items":
            return ["value": store.items]
        case "currentRoute":
            return ["value": store.currentRoute]
        default:
            return ["error": "unknown key: \(key)"]
        }
    }

    Remo.register("state.set") { params in
        let key = params["key"] as? String ?? ""
        // Extract typed values before crossing concurrency boundary
        let intValue = params["value"] as? Int
        let stringValue = params["value"] as? String
        let arrayValue = params["value"] as? [String]

        DispatchQueue.main.async {
            switch key {
            case "counter":
                if let v = intValue { store.counter = v }
            case "username":
                if let v = stringValue { store.username = v }
            case "items":
                if let v = arrayValue { store.items = v }
            default:
                break
            }
        }
        return ["status": "ok"]
    }

    Remo.register("counter.increment") { params in
        let amount = params["amount"] as? Int ?? 1
        DispatchQueue.main.async {
            store.counter += amount
        }
        return ["status": "ok", "counter": store.counter + (params["amount"] as? Int ?? 1)]
    }

    Remo.start()
}

// MARK: - Views

public struct ContentView: View {
    @Environment(AppStore.self) private var store

    public var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            ListPage()
                .tabItem { Label("Items", systemImage: "list.bullet") }

            SettingsPage()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }

    public init() {}
}

struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Hello, \(store.username)!")
                    .font(.title)

                Text("Counter: \(store.counter)")
                    .font(.largeTitle)
                    .monospacedDigit()

                HStack(spacing: 16) {
                    Button("-") { store.counter -= 1 }
                        .buttonStyle(.bordered)
                    Button("+") { store.counter += 1 }
                        .buttonStyle(.bordered)
                    Button("Reset") { store.counter = 0 }
                        .buttonStyle(.borderedProminent)
                }

                Text("Route: \(store.currentRoute)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Remo Example")
        }
    }
}

struct ListPage: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.items, id: \.self) { item in
                    NavigationLink(item) {
                        DetailPage(item: item)
                    }
                }
            }
            .navigationTitle("Items")
        }
    }
}

struct DetailPage: View {
    let item: String

    var body: some View {
        VStack(spacing: 16) {
            Text(item)
                .font(.title)
            Text("Detail view for \(item)")
                .foregroundStyle(.secondary)
        }
        .navigationTitle(item)
    }
}

struct SettingsPage: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    @Bindable var s = store
                    TextField("Username", text: $s.username)
                }

                Section("Debug") {
                    LabeledContent("Port", value: "\(Remo.defaultPort)")
                    LabeledContent("Capabilities") {
                        Text(Remo.listCapabilities().joined(separator: ", "))
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
