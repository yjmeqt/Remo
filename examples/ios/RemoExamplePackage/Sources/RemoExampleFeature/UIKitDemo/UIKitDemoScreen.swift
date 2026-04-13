import SwiftUI

#if canImport(UIKit)
import UIKit

struct UIKitDemoScreen: UIViewControllerRepresentable {
    let store: AppStore

    func makeUIViewController(context: Context) -> UIKitDemoViewController {
        UIKitDemoViewController()
    }

    func updateUIViewController(_ uiViewController: UIKitDemoViewController, context: Context) {
        uiViewController.updateItems(store.items)
    }
}
#else
struct UIKitDemoScreen: View {
    let store: AppStore

    var body: some View {
        ContentUnavailableView(
            "Grid Demo",
            systemImage: "square.grid.2x2",
            description: Text("The Grid demo is available on iOS builds.")
        )
    }
}
#endif
