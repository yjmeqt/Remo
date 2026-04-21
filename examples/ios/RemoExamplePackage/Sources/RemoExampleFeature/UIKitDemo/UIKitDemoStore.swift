import Foundation
import CoreGraphics

final class UIKitDemoStore {
    private let initialCards: [UIKitDemoCard]
    private var feedCards: [UIKitDemoCard]
    private let initialContacts: [UIKitDemoContact]
    private var contacts: [UIKitDemoContact]
    private var verticalOffsets: [UIKitDemoTab: CGFloat]

    private(set) var selectedTab: UIKitDemoTab

    init(
        seedCards: [UIKitDemoCard] = UIKitDemoSeed.cards(for: .feed),
        seedContacts: [UIKitDemoContact] = UIKitDemoSeed.contacts,
        selectedTab: UIKitDemoTab = .feed
    ) {
        self.initialCards = seedCards
        self.feedCards = seedCards
        self.initialContacts = seedContacts
        self.contacts = seedContacts
        self.verticalOffsets = [:]
        self.selectedTab = selectedTab
    }

    func select(_ tab: UIKitDemoTab) {
        selectedTab = tab
    }

    func resolveSelection(_ selection: UIKitDemoTabSelection) throws -> UIKitDemoTab {
        switch selection {
        case .index(let index):
            guard UIKitDemoTab.allCases.indices.contains(index) else {
                throw UIKitDemoCapabilityError.tabIndexOutOfRange(index)
            }
            return UIKitDemoTab.allCases[index]
        case .tab(let tab):
            return tab
        }
    }

    func resolveHorizontalTarget(_ target: UIKitDemoHorizontalTarget) throws -> UIKitDemoTab {
        switch target {
        case .next:
            guard let currentIndex = UIKitDemoTab.allCases.firstIndex(of: selectedTab) else {
                return selectedTab
            }
            let nextIndex = currentIndex + 1
            guard UIKitDemoTab.allCases.indices.contains(nextIndex) else {
                throw UIKitDemoCapabilityError.alreadyAtLastTab
            }
            return UIKitDemoTab.allCases[nextIndex]
        case .previous:
            guard let currentIndex = UIKitDemoTab.allCases.firstIndex(of: selectedTab) else {
                return selectedTab
            }
            let previousIndex = currentIndex - 1
            guard UIKitDemoTab.allCases.indices.contains(previousIndex) else {
                throw UIKitDemoCapabilityError.alreadyAtFirstTab
            }
            return UIKitDemoTab.allCases[previousIndex]
        case .index(let index):
            guard UIKitDemoTab.allCases.indices.contains(index) else {
                throw UIKitDemoCapabilityError.tabIndexOutOfRange(index)
            }
            return UIKitDemoTab.allCases[index]
        case .tab(let tab):
            return tab
        }
    }

    func cards(for tab: UIKitDemoTab) -> [UIKitDemoCard] {
        tab == .feed ? feedCards : []
    }

    func contacts(for tab: UIKitDemoTab) -> [UIKitDemoContact] {
        tab == .items ? contacts : []
    }

    func count(for tab: UIKitDemoTab) -> Int {
        switch tab {
        case .feed: return feedCards.count
        case .items: return contacts.count
        }
    }

    @discardableResult
    func appendCard(title: String, subtitle: String?) -> UIKitDemoTab {
        let suffix = feedCards.count + 1
        let column = suffix % 2
        feedCards.append(
            UIKitDemoCard(
                id: "feed-\(suffix)",
                title: title,
                subtitle: subtitle,
                tintHue: (Double(suffix) * 0.318).truncatingRemainder(dividingBy: 1.0),
                aspectWidth: 3,
                aspectHeight: 4,
                column: column,
                showsFooter: subtitle != nil,
                author: subtitle,
                likes: nil,
                hasPlayIcon: false
            )
        )
        return .feed
    }

    func resetFeed() {
        feedCards = initialCards
        contacts = initialContacts
    }

    func updateVerticalOffset(_ value: CGFloat, for tab: UIKitDemoTab) {
        verticalOffsets[tab] = value
    }

    func verticalOffset(for tab: UIKitDemoTab) -> CGFloat {
        verticalOffsets[tab] ?? 0
    }
}
