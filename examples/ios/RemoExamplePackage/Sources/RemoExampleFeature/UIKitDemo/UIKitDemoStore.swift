import Foundation
import CoreGraphics

final class UIKitDemoStore {
    private let initialCardsByTab: [UIKitDemoTab: [UIKitDemoCard]]
    private var cardsByTab: [UIKitDemoTab: [UIKitDemoCard]]
    private var verticalOffsets: [UIKitDemoTab: CGFloat]

    private(set) var selectedTab: UIKitDemoTab

    init(
        seedCardsByTab: [UIKitDemoTab: [UIKitDemoCard]] = UIKitDemoSeed.cardsByTab,
        selectedTab: UIKitDemoTab = .feed
    ) {
        self.initialCardsByTab = seedCardsByTab
        self.cardsByTab = seedCardsByTab
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

    func resolveTarget(_ target: UIKitDemoTabTarget) throws -> UIKitDemoTab? {
        switch target {
        case .active:
            return selectedTab
        case .all:
            return nil
        case .tab(let tab):
            return tab
        }
    }

    func cards(for tab: UIKitDemoTab) -> [UIKitDemoCard] {
        cardsByTab[tab] ?? []
    }

    func count(for tab: UIKitDemoTab) -> Int {
        cards(for: tab).count
    }

    @discardableResult
    func appendCard(title: String, subtitle: String?, tab: UIKitDemoTabTarget = .active) throws -> UIKitDemoTab {
        guard let resolvedTab = try resolveTarget(tab) else {
            throw UIKitDemoCapabilityError.missingTabIdentifier
        }

        let cards = cardsByTab[resolvedTab] ?? []
        let suffix = cards.count + 1
        let card = UIKitDemoCard(
            id: "\(resolvedTab.id)-\(suffix)",
            title: title,
            subtitle: subtitle
        )
        cardsByTab[resolvedTab, default: []].append(card)
        return resolvedTab
    }

    func reset(tab target: UIKitDemoTabTarget) throws {
        switch target {
        case .all:
            cardsByTab = initialCardsByTab
        case .active:
            cardsByTab[selectedTab] = initialCardsByTab[selectedTab] ?? []
        case .tab(let tab):
            cardsByTab[tab] = initialCardsByTab[tab] ?? []
        }
    }

    func updateVerticalOffset(_ value: CGFloat, for tab: UIKitDemoTab) {
        verticalOffsets[tab] = value
    }

    func verticalOffset(for tab: UIKitDemoTab) -> CGFloat {
        verticalOffsets[tab] ?? 0
    }
}
