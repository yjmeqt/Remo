import Foundation

enum UIKitDemoTab: String, CaseIterable, Identifiable, Sendable {
    case feed
    case items

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .items: return "Items"
        }
    }
}

struct UIKitDemoCard: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
}

enum UIKitDemoSeed {
    static let cardsByTab: [UIKitDemoTab: [UIKitDemoCard]] = [
        .feed: [
            .init(id: "feed-1", title: "Hero Spotlight", subtitle: "Pinned by the demo"),
            .init(id: "feed-2", title: "Starter Kit", subtitle: "Ready to copy"),
            .init(id: "feed-3", title: "UIKit Example", subtitle: "Built for Remo"),
            .init(id: "feed-4", title: "Callback Bridge", subtitle: "Background safe"),
            .init(id: "feed-5", title: "Diffable Data", subtitle: "Animated diffs"),
            .init(id: "feed-6", title: "Compositional", subtitle: "Flexible layouts"),
        ],
    ]

    static func cards(for tab: UIKitDemoTab) -> [UIKitDemoCard] {
        cardsByTab[tab] ?? []
    }
}

extension UIKitDemoTab {
    var responseValuePayload: [String: UIKitDemoResponseValue] {
        [
            "index": .int(UIKitDemoTab.allCases.firstIndex(of: self) ?? 0),
            "id": .string(id),
        ]
    }
}
