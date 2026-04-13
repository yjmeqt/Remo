#if canImport(SwiftUI)
import SwiftUI
import RemoSwift

@MainActor
final class TaskProbeStore: ObservableObject {
    @Published var currentRoute = "home"
}

struct TaskProbeView: View {
    @StateObject private var store = TaskProbeStore()

    var body: some View {
        Text(store.currentRoute)
            .task {
                await #Remo {
                    enum Navigate: RemoCapability {
                        static let name = "navigate"

                        struct Request: Decodable {
                            let route: String?
                        }

                        typealias Response = RemoOK
                    }

                    await #remoScope {
                        #remoCap(Navigate.self) { req in
                            Task { @MainActor in
                                store.currentRoute = req.route ?? "home"
                            }
                            return RemoOK()
                        }
                    }
                }
            }
    }
}
#endif
