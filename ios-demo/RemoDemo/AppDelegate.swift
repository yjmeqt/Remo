import UIKit

// FFI bridge to the Rust remo-agent static library.
// The actual C function is exposed via a bridging header.
//
// extern "C" fn remo_agent_start(port: u16);
//
// In a real project, you would:
// 1. Build remo-agent as a staticlib for aarch64-apple-ios
// 2. Add the .a file to Xcode's Link Binary With Libraries
// 3. Create a bridging header with: void remo_agent_start(uint16_t port);

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Start the Remo agent on a background thread
        DispatchQueue.global(qos: .utility).async {
            // remo_agent_start(9876)
            print("[Remo] Agent would start on port 9876")
        }

        window = UIWindow(frame: UIScreen.main.bounds)
        let nav = UINavigationController(rootViewController: HomeViewController())
        window?.rootViewController = nav
        window?.makeKeyAndVisible()

        return true
    }
}
