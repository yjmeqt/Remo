import SwiftUI
import RemoExampleFeature

@main
struct RemoExampleApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
