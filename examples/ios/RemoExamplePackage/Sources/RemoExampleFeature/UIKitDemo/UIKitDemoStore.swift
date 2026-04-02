import Foundation
import CoreGraphics

final class UIKitDemoStore {
    private let initialCards: [UIKitDemoCard]
    private var feedCards: [UIKitDemoCard]
    private var verticalOffsets: [UIKitDemoTab: CGFloat]

    private(set) var selectedTab: UIKitDemoTab

    init(
        seedCards: [UIKitDemoCard] = UIKitDemoSeed.cards(for: .feed),
        selectedTab: UIKitDemoTab = .feed
    ) {
        self.initialCards = seedCards
        self.feedCards = seedCards
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

    func count(for tab: UIKitDemoTab) -> Int {
        cards(for: tab).count
    }

    @discardableResult
    func appendCard(title: String, subtitle: String?) -> UIKitDemoTab {
        let suffix = feedCards.count + 1
        feedCards.append(UIKitDemoCard(id: "feed-\(suffix)", title: title, subtitle: subtitle))
        return .feed
    }

    func resetFeed() {
        feedCards = initialCards
    }

    func updateVerticalOffset(_ value: CGFloat, for tab: UIKitDemoTab) {
        verticalOffsets[tab] = value
    }

    func verticalOffset(for tab: UIKitDemoTab) -> CGFloat {
        verticalOffsets[tab] ?? 0
    }
}
