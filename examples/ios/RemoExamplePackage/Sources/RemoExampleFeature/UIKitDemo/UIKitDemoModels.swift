import Foundation
import CoreGraphics

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

struct UIKitDemoCard: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let tintHue: Double
    let aspectWidth: CGFloat
    let aspectHeight: CGFloat
    let column: Int
    let showsFooter: Bool
    let author: String?
    let likes: String?
    let hasPlayIcon: Bool

    init(
        id: String,
        title: String = "",
        subtitle: String? = nil,
        tintHue: Double = 0.55,
        aspectWidth: CGFloat = 3,
        aspectHeight: CGFloat = 4,
        column: Int = 0,
        showsFooter: Bool = false,
        author: String? = nil,
        likes: String? = nil,
        hasPlayIcon: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tintHue = tintHue
        self.aspectWidth = aspectWidth
        self.aspectHeight = aspectHeight
        self.column = column
        self.showsFooter = showsFooter
        self.author = author
        self.likes = likes
        self.hasPlayIcon = hasPlayIcon
    }
}

struct UIKitDemoContact: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let handle: String
    let avatarHue: Double
}

enum UIKitDemoSeed {
    static let cardsByTab: [UIKitDemoTab: [UIKitDemoCard]] = [
        .feed: [
            UIKitDemoCard(
                id: "feed-1",
                title: "Hero Spotlight",
                tintHue: 0.56,
                aspectWidth: 193,
                aspectHeight: 257,
                column: 0
            ),
            UIKitDemoCard(
                id: "feed-2",
                title: "Starter Kit",
                tintHue: 0.07,
                aspectWidth: 193,
                aspectHeight: 189,
                column: 0,
                hasPlayIcon: true
            ),
            UIKitDemoCard(
                id: "feed-3",
                title: "How I hid my ugly HVAC panel without blocking airflow",
                subtitle: "adrianvvlog",
                tintHue: 0.33,
                aspectWidth: 3,
                aspectHeight: 4,
                column: 0,
                showsFooter: true,
                author: "adrianvvlog",
                likes: "1.6K",
                hasPlayIcon: true
            ),
            UIKitDemoCard(
                id: "feed-4",
                title: "Callback Bridge",
                tintHue: 0.75,
                aspectWidth: 193,
                aspectHeight: 250,
                column: 1
            ),
            UIKitDemoCard(
                id: "feed-5",
                title: "Diffable Data",
                tintHue: 0.12,
                aspectWidth: 252,
                aspectHeight: 189,
                column: 1,
                hasPlayIcon: true
            ),
            UIKitDemoCard(
                id: "feed-6",
                title: "Compositional",
                tintHue: 0.95,
                aspectWidth: 3,
                aspectHeight: 4,
                column: 1,
                showsFooter: true,
                hasPlayIcon: true
            ),
        ],
    ]

    static let contacts: [UIKitDemoContact] = [
        .init(id: "c-1", name: "autolayout_ace", handle: "@ace.2042", avatarHue: 0.03),
        .init(id: "c-2", name: "keypath_keeper", handle: "@keeper.5519", avatarHue: 0.58),
        .init(id: "c-3", name: "view_voyager", handle: "@voyager.0077", avatarHue: 0.82),
        .init(id: "c-4", name: "async_alchemist", handle: "@alchemist.3310", avatarHue: 0.01),
        .init(id: "c-5", name: "mainthread_mage", handle: "@mage.8124", avatarHue: 0.34),
        .init(id: "c-6", name: "pixel_pilot", handle: "@pilot.6601", avatarHue: 0.66),
        .init(id: "c-7", name: "debug_buddy", handle: "@buddy.9090", avatarHue: 0.12),
        .init(id: "c-8", name: "swift_wizard", handle: "@wizard.4242", avatarHue: 0.90),
        .init(id: "c-9", name: "compositional_cat", handle: "@cat.1337", avatarHue: 0.48),
    ]

    static func cards(for tab: UIKitDemoTab) -> [UIKitDemoCard] {
        cardsByTab[tab] ?? []
    }
}
