import SwiftUI
import RemoSwift

public struct ContentView: View {
    @Environment(AppStore.self) private var store

    public var body: some View {
        @Bindable var store = store
        ZStack(alignment: .top) {
            TabView(selection: $store.currentRoute) {
                HomeView()
                    .tag("home")
                    .tabItem { Label("Home", systemImage: "house") }

                UIKitDemoScreen(store: store)
                    .tag("uikit")
                    .tabItem { Label("Grid", systemImage: "square.grid.2x2") }

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
        .task {
            let store = store  // rebind as `let` for @Sendable closures in #remoCap handlers below
            await #Remo {
                struct StatusResponse: Encodable {
                    let status: String = "ok"
                }

                struct RouteResponse: Encodable {
                    let status: String = "ok"
                    let route: String
                }

                struct ColorResponse: Encodable {
                    let status: String = "ok"
                    let color: String
                }

                enum StateValue: Encodable {
                    case int(Int)
                    case string(String)
                    case strings([String])

                    func encode(to encoder: Encoder) throws {
                        var container = encoder.singleValueContainer()
                        switch self {
                        case .int(let value):
                            try container.encode(value)
                        case .string(let value):
                            try container.encode(value)
                        case .strings(let value):
                            try container.encode(value)
                        }
                    }
                }

                struct StateGetResponse: Encodable {
                    let value: StateValue?
                    let error: String?

                    init(value: StateValue) {
                        self.value = value
                        self.error = nil
                    }

                    init(error: String) {
                        self.value = nil
                        self.error = error
                    }
                }

                enum StateSetValue: Decodable {
                    case int(Int)
                    case string(String)
                    case strings([String])

                    init(from decoder: Decoder) throws {
                        let container = try decoder.singleValueContainer()
                        if let value = try? container.decode(Int.self) {
                            self = .int(value)
                        } else if let value = try? container.decode(String.self) {
                            self = .string(value)
                        } else if let value = try? container.decode([String].self) {
                            self = .strings(value)
                        } else {
                            throw DecodingError.typeMismatch(
                                StateSetValue.self,
                                .init(
                                    codingPath: decoder.codingPath,
                                    debugDescription: "Expected Int, String, or [String]"
                                )
                            )
                        }
                    }
                }

                enum Navigate: RemoCapability {
                    static let name = "navigate"

                    struct Request: Decodable {
                        let route: String?
                    }

                    typealias Response = RouteResponse
                }

                enum StateGet: RemoCapability {
                    static let name = "state.get"

                    struct Request: Decodable {
                        let key: String
                    }

                    typealias Response = StateGetResponse
                }

                enum StateSet: RemoCapability {
                    static let name = "state.set"

                    struct Request: Decodable {
                        let key: String
                        let value: StateSetValue
                    }

                    typealias Response = StatusResponse
                }

                enum ShowToast: RemoCapability {
                    static let name = "ui.toast"

                    struct Request: Decodable {
                        let message: String?
                    }

                    typealias Response = StatusResponse
                }

                enum ShowConfetti: RemoCapability {
                    static let name = "ui.confetti"
                }

                enum SetAccentColor: RemoCapability {
                    static let name = "ui.setAccentColor"

                    struct Request: Decodable {
                        let color: String?
                    }

                    typealias Response = ColorResponse
                }

                await #remoScope {
                    #remoCap(Navigate.self) { req in
                        let route = req.route ?? "home"
                        Task { @MainActor in
                            store.currentRoute = route
                        }
                        return RouteResponse(route: route)
                    }

                    #remoCap(StateGet.self) { req in
                        switch req.key {
                        case "counter":
                            return StateGetResponse(value: .int(store.counter))
                        case "username":
                            return StateGetResponse(value: .string(store.username))
                        case "items":
                            return StateGetResponse(value: .strings(store.items))
                        case "currentRoute":
                            return StateGetResponse(value: .string(store.currentRoute))
                        case "accentColor":
                            return StateGetResponse(value: .string(store.accentColorName))
                        default:
                            return StateGetResponse(error: "unknown key: \(req.key)")
                        }
                    }

                    #remoCap(StateSet.self) { req in
                        Task { @MainActor in
                            switch (req.key, req.value) {
                            case ("counter", .int(let value)):
                                store.counter = value
                            case ("username", .string(let value)):
                                store.username = value
                            case ("items", .strings(let value)):
                                store.items = value
                            default:
                                break
                            }
                        }
                        return StatusResponse()
                    }

                    #remoCap(ShowToast.self) { req in
                        let message = req.message ?? "Hello from Remo!"
                        Task { @MainActor in
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
                        return StatusResponse()
                    }

                    #remoCap(ShowConfetti.self) { _ in
                        Task { @MainActor in
                            store.showConfetti = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                store.showConfetti = false
                            }
                        }
                        return RemoOK()
                    }

                    #remoCap(SetAccentColor.self) { req in
                        let color = req.color ?? "blue"
                        Task { @MainActor in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                store.accentColorName = color
                            }
                        }
                        return ColorResponse(color: color)
                    }
                }
            }
        }
    }

    public init() {}
}
