# UIKit Grid Tab Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 3-tab UIKit pager (Featured/Recent/Saved) with a 2-tab Grid screen (Feed + Items), rename the tab to "Grid", move the Items list into the UIKit screen synced to `AppStore.items`, and rename all capabilities to `grid.*`.

**Architecture:** `UIKitDemoFeedPageViewController` (compositional 2-column grid, DiffableDataSource) and `UIKitDemoItemsPageViewController` (list layout, DiffableDataSource<String>) replace the single `UIKitDemoPageViewController`. The SwiftUI bridge (`UIKitDemoScreen`) pushes `AppStore.items` into the VC via `updateUIViewController`. All `uikit.*` capabilities rename to `grid.*`; a new `grid.visible` capability returns visible items from the active page's collection view.

**Tech Stack:** UIKit · UICollectionViewCompositionalLayout · NSDiffableDataSource · CellRegistration · SwiftUI UIViewControllerRepresentable · Swift 6 strict concurrency · Swift Testing

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `UIKitDemoModels.swift` | Modify | Tab enum (`.feed`/`.items`), card seed, `UIKitDemoResponseValue.array` |
| `UIKitDemoCapabilityContract.swift` | Modify | `Names` constants (`grid.*`), `visibleResponse` builder |
| `UIKitDemoStore.swift` | Modify | Default tab → `.feed`, simplified `appendCard` |
| `UIKitDemoFeedPageViewController.swift` | **Create** | 2-column compositional grid page |
| `UIKitDemoItemsPageViewController.swift` | **Create** | List layout page, `apply(items:)`, `visibleItems()` |
| `UIKitDemoPageViewController.swift` | **Delete** | Replaced by two purpose-built VCs above |
| `UIKitDemoViewController.swift` | Modify | Wire new page VCs, rename caps, add `updateItems`, add `grid.visible` |
| `UIKitDemoScreen.swift` | Modify | Accept `AppStore`, push items in `updateUIViewController` |
| `ContentView.swift` | Modify | Remove Items tab, rename to Grid, move `items.*` to `setupRemo` |
| `RemoExampleFeatureTests.swift` | Modify | 4 unit tests covering models + capability names |
| `examples/ios/README.md` | Modify | Updated capabilities table + e2e Try It script |
| `README.md` (root) | Modify | `uikit.*` → `grid.*` in one sentence |

---

## Task 1: Update tab model, seed data, and write unit tests

**Files:**
- Modify: `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoModels.swift`
- Modify: `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/ContentView.swift` (AppStore)
- Modify: `examples/ios/RemoExamplePackage/Tests/RemoExampleFeatureTests/RemoExampleFeatureTests.swift`

- [ ] **Step 1: Write failing tests**

Replace the contents of `RemoExampleFeatureTests.swift`:

```swift
import Testing
import RemoSwift
@testable import RemoExampleFeature

private func requireSendable<T: Sendable>(_: T.Type) {}

@Test func appStoreRemainsSendableForBackgroundCapabilityClosures() async throws {
    requireSendable(AppStore.self)
}

@Test func registerRequiresASendableHandlerContract() async throws {
    let register: (String, @Sendable @escaping ([String: Any]) -> [String: Any]) -> Void = Remo.register
    _ = register
}

@Test func gridTabCasesAreFeedAndItems() {
    #expect(UIKitDemoTab.allCases == [.feed, .items])
}

@Test func gridTabIDsMatchExpected() {
    #expect(UIKitDemoTab.feed.id == "feed")
    #expect(UIKitDemoTab.items.id == "items")
}

@Test func appStoreItemsSeedHasTwentyEntries() {
    #expect(AppStore().items.count == 20)
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd examples/ios/RemoExamplePackage && swift test 2>&1 | grep -E "passed|failed|error:"
```

Expected: compile errors or test failures because `.feed`, `.items` don't exist yet.

- [ ] **Step 3: Update `UIKitDemoTab` and seed in `UIKitDemoModels.swift`**

Replace the existing `UIKitDemoTab` enum, `UIKitDemoSeed`, and the `responseValuePayload` extension:

```swift
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
```

- [ ] **Step 4: Expand `AppStore.items` seed to 20 entries in `ContentView.swift`**

Find the line `public var items: [String] = ["Item A", "Item B", "Item C"]` and replace:

```swift
public var items: [String] = [
    "Morning Standup", "Design Review", "Sprint Planning", "API Integration",
    "Code Review", "Remo Demo", "Release Notes", "User Testing",
    "Launch Prep", "Post-mortem", "Architecture Review", "Performance Audit",
    "Accessibility Pass", "Localization Check", "Security Review", "Dependency Update",
    "Changelog Draft", "Beta Feedback", "Stakeholder Sync", "Ship It",
]
```

- [ ] **Step 5: Run tests — expect 3 new tests to pass**

```bash
cd examples/ios/RemoExamplePackage && swift test 2>&1 | grep -E "passed|failed|error:"
```

Expected: `Test run with 5 tests passed` (all 5 pass including the 3 new ones).

- [ ] **Step 6: Commit**

```bash
git add examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoModels.swift \
        examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/ContentView.swift \
        examples/ios/RemoExamplePackage/Tests/RemoExampleFeatureTests/RemoExampleFeatureTests.swift
git commit -m "feat: rename UIKitDemoTab to feed/items, expand AppStore seed to 20"
```

---

## Task 2: Update capability contract — `grid.*` names + `grid.visible` support

**Files:**
- Modify: `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoCapabilityContract.swift`
- Modify: `examples/ios/RemoExamplePackage/Tests/RemoExampleFeatureTests/RemoExampleFeatureTests.swift`

- [ ] **Step 1: Write failing test**

Add to `RemoExampleFeatureTests.swift`:

```swift
@Test func capabilityNamesUseGridPrefix() {
    let names = [
        UIKitDemoCapabilityContract.Names.tabSelect,
        UIKitDemoCapabilityContract.Names.feedAppend,
        UIKitDemoCapabilityContract.Names.feedReset,
        UIKitDemoCapabilityContract.Names.scrollVertical,
        UIKitDemoCapabilityContract.Names.scrollHorizontal,
        UIKitDemoCapabilityContract.Names.visible,
    ]
    for name in names {
        #expect(name.hasPrefix("grid."), "\(name) must start with 'grid.'")
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd examples/ios/RemoExamplePackage && swift test 2>&1 | grep -E "passed|failed|error:"
```

Expected: compile error — `UIKitDemoCapabilityContract.Names` does not exist yet.

- [ ] **Step 3: Add `Names` enum, `.array` response value, and `visibleResponse` to `UIKitDemoCapabilityContract.swift`**

At the top of `UIKitDemoCapabilityContract.swift`, replace the existing `UIKitDemoResponseValue` enum:

```swift
indirect enum UIKitDemoResponseValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case array([UIKitDemoResponseValue])
    case object([String: UIKitDemoResponseValue])

    var foundationValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .array(let values): return values.map(\.foundationValue)
        case .object(let value): return value.mapValues(\.foundationValue)
        }
    }
}
```

Inside `enum UIKitDemoCapabilityContract`, add `Names` as the first declaration:

```swift
enum Names {
    static let tabSelect = "grid.tab.select"
    static let feedAppend = "grid.feed.append"
    static let feedReset = "grid.feed.reset"
    static let scrollVertical = "grid.scroll.vertical"
    static let scrollHorizontal = "grid.scroll.horizontal"
    static let visible = "grid.visible"
}
```

Replace `appendResponse`, `resetResponse`, and add `visibleResponse` at the bottom of the contract (keep existing parsers unchanged):

```swift
static func appendResponse(tab: UIKitDemoTab, count: Int) -> UIKitDemoResponse {
    .init(payload: [
        "status": .string("ok"),
        "tab": .string(tab.id),
        "count": .int(count),
    ])
}

static func resetResponse() -> UIKitDemoResponse {
    .init(payload: ["status": .string("ok"), "tab": .string("feed")])
}

static func visibleResponse(
    tab: UIKitDemoTab,
    visible: [UIKitDemoResponseValue],
    total: Int
) -> UIKitDemoResponse {
    .init(payload: [
        "status": .string("ok"),
        "tab": .string(tab.id),
        "visible": .array(visible),
        "count": .int(visible.count),
        "total": .int(total),
    ])
}
```

Note: the old `resetResponse(tab:resolvedTab:)` signature is replaced by the new zero-argument version. The compiler will flag the old call site in `UIKitDemoViewController.swift` — it will be fixed in Task 6.

- [ ] **Step 4: Run tests — expect 6 tests to pass**

```bash
cd examples/ios/RemoExamplePackage && swift test 2>&1 | grep -E "passed|failed|error:"
```

Expected: `Test run with 6 tests passed`.

- [ ] **Step 5: Commit**

```bash
git add examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoCapabilityContract.swift \
        examples/ios/RemoExamplePackage/Tests/RemoExampleFeatureTests/RemoExampleFeatureTests.swift
git commit -m "feat: add grid.* capability names and grid.visible response support"
```

---

## Task 3: Create `UIKitDemoFeedPageViewController`

**Files:**
- Create: `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoFeedPageViewController.swift`

- [ ] **Step 1: Create the file**

```swift
#if canImport(UIKit)
import UIKit

final class UIKitDemoFeedPageViewController: UIViewController {
    private enum Section { case main }

    private let cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, UIKitDemoCard> {
        cell, _, card in
        var content = UIListContentConfiguration.cell()
        content.text = card.title
        content.secondaryText = card.subtitle
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        cell.contentConfiguration = content

        var background = UIBackgroundConfiguration.listGroupedCell()
        background.cornerRadius = 20
        cell.backgroundConfiguration = background
    }

    private(set) lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.5),
                heightDimension: .estimated(120)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(120)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                subitems: [item, item]
            )
            group.interItemSpacing = .fixed(12)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 12
            section.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 16, bottom: 32, trailing: 16)
            return section
        }
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        return cv
    }()

    private lazy var dataSource = UICollectionViewDiffableDataSource<Section, UIKitDemoCard>(
        collectionView: collectionView
    ) { [cellRegistration] collectionView, indexPath, card in
        collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: card)
    }

    var onVerticalOffsetChange: ((CGFloat) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        collectionView.delegate = self
    }

    func apply(cards: [UIKitDemoCard], restoringOffset: CGFloat) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, UIKitDemoCard>()
        snapshot.appendSections([.main])
        snapshot.appendItems(cards)
        dataSource.apply(snapshot, animatingDifferences: true)
        collectionView.layoutIfNeeded()
        let clamped = max(-collectionView.adjustedContentInset.top, restoringOffset)
        collectionView.setContentOffset(.init(x: 0, y: clamped), animated: false)
    }

    func visibleCards() -> [UIKitDemoCard] {
        collectionView.indexPathsForVisibleItems
            .sorted()
            .compactMap { dataSource.itemIdentifier(for: $0) }
    }

    @discardableResult
    func scroll(to position: UIKitDemoScrollPosition, animated: Bool) -> CGFloat {
        let inset = collectionView.adjustedContentInset
        let visibleHeight = collectionView.bounds.height - inset.top - inset.bottom
        let contentHeight = collectionView.contentSize.height
        let maxOffset = max(-inset.top, contentHeight - visibleHeight)

        let y: CGFloat
        switch position {
        case .top: y = -inset.top
        case .middle: y = max(-inset.top, maxOffset / 2)
        case .bottom: y = maxOffset
        }
        collectionView.setContentOffset(.init(x: 0, y: y), animated: animated)
        onVerticalOffsetChange?(y)
        return y
    }
}

extension UIKitDemoFeedPageViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onVerticalOffsetChange?(scrollView.contentOffset.y)
    }
}
#endif
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
cd examples/ios && xcodebuild build \
  -workspace RemoExample.xcworkspace \
  -scheme RemoExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: errors only from `UIKitDemoViewController.swift` (which still uses old `pages` dict and old cap names — will be fixed in Task 6). The new file itself must not produce errors.

- [ ] **Step 3: Commit**

```bash
git add examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoFeedPageViewController.swift
git commit -m "feat: add UIKitDemoFeedPageViewController with compositional 2-column grid"
```

---

## Task 4: Create `UIKitDemoItemsPageViewController`

**Files:**
- Create: `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoItemsPageViewController.swift`

- [ ] **Step 1: Create the file**

```swift
#if canImport(UIKit)
import UIKit

final class UIKitDemoItemsPageViewController: UIViewController {
    private enum Section { case main }

    private let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, String> {
        cell, _, item in
        var content = cell.defaultContentConfiguration()
        content.text = item
        cell.contentConfiguration = content
    }

    private(set) lazy var collectionView: UICollectionView = {
        var listConfig = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfig.showsSeparators = true
        let layout = UICollectionViewCompositionalLayout.list(using: listConfig)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        return cv
    }()

    private lazy var dataSource = UICollectionViewDiffableDataSource<Section, String>(
        collectionView: collectionView
    ) { [cellRegistration] collectionView, indexPath, item in
        collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
    }

    var onVerticalOffsetChange: ((CGFloat) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        collectionView.delegate = self
    }

    func apply(items: [String], restoringOffset: CGFloat) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items)
        dataSource.apply(snapshot, animatingDifferences: true)
        collectionView.layoutIfNeeded()
        let clamped = max(-collectionView.adjustedContentInset.top, restoringOffset)
        collectionView.setContentOffset(.init(x: 0, y: clamped), animated: false)
    }

    func visibleItems() -> [String] {
        collectionView.indexPathsForVisibleItems
            .sorted()
            .compactMap { dataSource.itemIdentifier(for: $0) }
    }

    @discardableResult
    func scroll(to position: UIKitDemoScrollPosition, animated: Bool) -> CGFloat {
        let inset = collectionView.adjustedContentInset
        let visibleHeight = collectionView.bounds.height - inset.top - inset.bottom
        let contentHeight = collectionView.contentSize.height
        let maxOffset = max(-inset.top, contentHeight - visibleHeight)

        let y: CGFloat
        switch position {
        case .top: y = -inset.top
        case .middle: y = max(-inset.top, maxOffset / 2)
        case .bottom: y = maxOffset
        }
        collectionView.setContentOffset(.init(x: 0, y: y), animated: animated)
        onVerticalOffsetChange?(y)
        return y
    }
}

extension UIKitDemoItemsPageViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onVerticalOffsetChange?(scrollView.contentOffset.y)
    }
}
#endif
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
cd examples/ios && xcodebuild build \
  -workspace RemoExample.xcworkspace \
  -scheme RemoExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: same residual errors from `UIKitDemoViewController.swift` only.

- [ ] **Step 3: Commit**

```bash
git add examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoItemsPageViewController.swift
git commit -m "feat: add UIKitDemoItemsPageViewController with list layout"
```

---

## Task 5: Update `UIKitDemoStore`

**Files:**
- Modify: `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoStore.swift`

- [ ] **Step 1: Update default tab and simplify `appendCard`**

Replace the entire file contents:

```swift
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
```

- [ ] **Step 2: Build to check**

```bash
cd examples/ios && xcodebuild build \
  -workspace RemoExample.xcworkspace \
  -scheme RemoExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `UIKitDemoViewController.swift` still has errors (old `pages`, old cap names, old store API calls). Those are fixed in Task 6.

- [ ] **Step 3: Commit**

```bash
git add examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoStore.swift
git commit -m "feat: simplify UIKitDemoStore for two-tab feed/items structure"
```

---

## Task 6: Rewrite `UIKitDemoViewController` and delete `UIKitDemoPageViewController`

**Files:**
- Modify: `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoViewController.swift`
- Delete: `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoPageViewController.swift`

- [ ] **Step 1: Replace the entire `UIKitDemoViewController.swift`**

```swift
#if canImport(UIKit)
import RemoSwift
import UIKit

final class UIKitDemoViewController: UIViewController, UIScrollViewDelegate {
    private final class CapabilityBridge: @unchecked Sendable {
        weak var controller: UIKitDemoViewController?

        init(controller: UIKitDemoViewController) {
            self.controller = controller
        }

        func run(
            _ work: @escaping @MainActor @Sendable (UIKitDemoViewController) -> UIKitDemoResponse
        ) -> [String: Any] {
            if Thread.isMainThread {
                let response = MainActor.assumeIsolated {
                    guard let controller else {
                        return UIKitDemoCapabilityError.controllerDeallocated.response
                    }
                    return work(controller)
                }
                return response.dictionary
            }

            let response = DispatchQueue.main.sync { [weak self] in
                MainActor.assumeIsolated {
                    guard let controller = self?.controller else {
                        return UIKitDemoCapabilityError.controllerDeallocated.response
                    }
                    return work(controller)
                }
            }
            return response.dictionary
        }
    }

    private let store = UIKitDemoStore()
    private let rootScrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let headerStack = UIStackView()
    private let activeTabLabel = UILabel()
    private let tabStripView = UIKitDemoTabStripView()
    private let pagerScrollView = UIScrollView()
    private let pagerStackView = UIStackView()
    private var pagerHeightConstraint: NSLayoutConstraint?

    private var feedPage: UIKitDemoFeedPageViewController?
    private var itemsPage: UIKitDemoItemsPageViewController?
    private var currentItems: [String] = []

    private var hasRegisteredCapabilities = false
    private var capabilityBridge: CapabilityBridge?

    private let capabilityNames = [
        UIKitDemoCapabilityContract.Names.tabSelect,
        UIKitDemoCapabilityContract.Names.feedAppend,
        UIKitDemoCapabilityContract.Names.feedReset,
        UIKitDemoCapabilityContract.Names.scrollVertical,
        UIKitDemoCapabilityContract.Names.scrollHorizontal,
        UIKitDemoCapabilityContract.Names.visible,
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        buildHierarchy()
        configurePages()
        refreshFeedPage()
        syncSelection(animated: false)
        registerCapabilitiesIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let targetHeight = max(420, view.bounds.height - 220)
        pagerHeightConstraint?.constant = targetHeight
    }

    deinit {
        capabilityNames.forEach { Remo.unregister($0) }
    }

    func updateItems(_ items: [String]) {
        currentItems = items
        itemsPage?.apply(items: items, restoringOffset: store.verticalOffset(for: .items))
    }

    private func buildHierarchy() {
        rootScrollView.alwaysBounceVertical = true
        rootScrollView.showsVerticalScrollIndicator = true

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.layoutMargins = .init(top: 24, left: 20, bottom: 24, right: 20)
        contentStack.isLayoutMarginsRelativeArrangement = true

        headerStack.axis = .vertical
        headerStack.spacing = 10

        let titleLabel = UILabel()
        titleLabel.text = "Grid"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle).bold()

        let subtitleLabel = UILabel()
        subtitleLabel.text = "A UIKit Remo demo with Feed and Items tabs, horizontal paging, and explicit main-thread UI updates."
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        activeTabLabel.font = .preferredFont(forTextStyle: .subheadline)
        activeTabLabel.textColor = .secondaryLabel

        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(subtitleLabel)
        headerStack.addArrangedSubview(activeTabLabel)

        tabStripView.onSelection = { [weak self] tab in
            self?.select(tab: tab, animated: true)
        }

        pagerScrollView.isPagingEnabled = true
        pagerScrollView.showsHorizontalScrollIndicator = false
        pagerScrollView.alwaysBounceHorizontal = true
        pagerScrollView.delegate = self

        pagerStackView.axis = .horizontal
        pagerStackView.spacing = 0
        pagerStackView.distribution = .fillEqually

        view.addSubview(rootScrollView)
        rootScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rootScrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            rootScrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            rootScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            rootScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        rootScrollView.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: rootScrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: rootScrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: rootScrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: rootScrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: rootScrollView.frameLayoutGuide.widthAnchor),
        ])

        contentStack.addArrangedSubview(headerStack)

        let tabContainer = UIView()
        tabContainer.addSubview(tabStripView)
        tabStripView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabStripView.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor),
            tabStripView.trailingAnchor.constraint(equalTo: tabContainer.trailingAnchor),
            tabStripView.topAnchor.constraint(equalTo: tabContainer.topAnchor),
            tabStripView.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor),
            tabStripView.heightAnchor.constraint(equalToConstant: 44),
        ])
        contentStack.addArrangedSubview(tabContainer)

        let pagerContainer = UIView()
        pagerContainer.layer.cornerRadius = 28
        pagerContainer.layer.masksToBounds = true
        pagerContainer.backgroundColor = .systemBackground

        pagerContainer.addSubview(pagerScrollView)
        pagerScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pagerScrollView.leadingAnchor.constraint(equalTo: pagerContainer.leadingAnchor),
            pagerScrollView.trailingAnchor.constraint(equalTo: pagerContainer.trailingAnchor),
            pagerScrollView.topAnchor.constraint(equalTo: pagerContainer.topAnchor),
            pagerScrollView.bottomAnchor.constraint(equalTo: pagerContainer.bottomAnchor),
        ])

        pagerScrollView.addSubview(pagerStackView)
        pagerStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pagerStackView.leadingAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.leadingAnchor),
            pagerStackView.trailingAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.trailingAnchor),
            pagerStackView.topAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.topAnchor),
            pagerStackView.bottomAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.bottomAnchor),
            pagerStackView.heightAnchor.constraint(equalTo: pagerScrollView.frameLayoutGuide.heightAnchor),
        ])

        contentStack.addArrangedSubview(pagerContainer)
        pagerContainer.translatesAutoresizingMaskIntoConstraints = false
        let heightConstraint = pagerContainer.heightAnchor.constraint(equalToConstant: 500)
        heightConstraint.isActive = true
        pagerHeightConstraint = heightConstraint
    }

    private func configurePages() {
        let feed = UIKitDemoFeedPageViewController()
        feed.onVerticalOffsetChange = { [weak self] offset in
            self?.store.updateVerticalOffset(offset, for: .feed)
        }
        addChild(feed)
        pagerStackView.addArrangedSubview(feed.view)
        feed.view.translatesAutoresizingMaskIntoConstraints = false
        feed.view.widthAnchor.constraint(equalTo: pagerScrollView.frameLayoutGuide.widthAnchor).isActive = true
        feed.didMove(toParent: self)
        feedPage = feed

        let items = UIKitDemoItemsPageViewController()
        items.onVerticalOffsetChange = { [weak self] offset in
            self?.store.updateVerticalOffset(offset, for: .items)
        }
        addChild(items)
        pagerStackView.addArrangedSubview(items.view)
        items.view.translatesAutoresizingMaskIntoConstraints = false
        items.view.widthAnchor.constraint(equalTo: pagerScrollView.frameLayoutGuide.widthAnchor).isActive = true
        items.didMove(toParent: self)
        itemsPage = items
    }

    private func registerCapabilitiesIfNeeded() {
        guard !hasRegisteredCapabilities else { return }
        hasRegisteredCapabilities = true

        let bridge = CapabilityBridge(controller: self)
        capabilityBridge = bridge

        Remo.register(UIKitDemoCapabilityContract.Names.tabSelect) { params in
            do {
                let selection = try UIKitDemoCapabilityContract.parseTabSelect(params)
                return bridge.run { controller in controller.handleTabSelect(selection) }
            } catch let error as UIKitDemoCapabilityError {
                return error.response.dictionary
            } catch {
                return UIKitDemoCapabilityError.unexpectedError.response.dictionary
            }
        }

        Remo.register(UIKitDemoCapabilityContract.Names.feedAppend) { params in
            do {
                let request = try UIKitDemoCapabilityContract.parseAppend(params)
                return bridge.run { controller in controller.handleAppend(request) }
            } catch let error as UIKitDemoCapabilityError {
                return error.response.dictionary
            } catch {
                return UIKitDemoCapabilityError.unexpectedError.response.dictionary
            }
        }

        Remo.register(UIKitDemoCapabilityContract.Names.feedReset) { _ in
            bridge.run { controller in controller.handleReset() }
        }

        Remo.register(UIKitDemoCapabilityContract.Names.scrollVertical) { params in
            do {
                let request = try UIKitDemoCapabilityContract.parseVerticalScroll(params)
                return bridge.run { controller in controller.handleVerticalScroll(request) }
            } catch let error as UIKitDemoCapabilityError {
                return error.response.dictionary
            } catch {
                return UIKitDemoCapabilityError.unexpectedError.response.dictionary
            }
        }

        Remo.register(UIKitDemoCapabilityContract.Names.scrollHorizontal) { params in
            do {
                let request = try UIKitDemoCapabilityContract.parseHorizontalScroll(params)
                return bridge.run { controller in controller.handleHorizontalScroll(request) }
            } catch let error as UIKitDemoCapabilityError {
                return error.response.dictionary
            } catch {
                return UIKitDemoCapabilityError.unexpectedError.response.dictionary
            }
        }

        Remo.register(UIKitDemoCapabilityContract.Names.visible) { _ in
            bridge.run { controller in controller.handleVisible() }
        }
    }

    private func handleTabSelect(_ selection: UIKitDemoTabSelection) -> UIKitDemoResponse {
        do {
            let tab = try store.resolveSelection(selection)
            select(tab: tab, animated: true)
            return UIKitDemoCapabilityContract.tabSelectResponse(for: tab)
        } catch let error as UIKitDemoCapabilityError {
            return error.response
        } catch {
            return UIKitDemoCapabilityError.unexpectedError.response
        }
    }

    private func handleAppend(_ request: UIKitDemoAppendRequest) -> UIKitDemoResponse {
        let resolvedTab = store.appendCard(title: request.title, subtitle: request.subtitle)
        refreshFeedPage()
        return UIKitDemoCapabilityContract.appendResponse(tab: resolvedTab, count: store.count(for: resolvedTab))
    }

    private func handleReset() -> UIKitDemoResponse {
        store.resetFeed()
        feedPage?.apply(cards: store.cards(for: .feed), restoringOffset: 0)
        return UIKitDemoCapabilityContract.resetResponse()
    }

    private func handleVerticalScroll(_ request: UIKitDemoVerticalScrollRequest) -> UIKitDemoResponse {
        let tab = store.selectedTab
        switch tab {
        case .feed: feedPage?.scroll(to: request.position, animated: true)
        case .items: itemsPage?.scroll(to: request.position, animated: true)
        }
        return UIKitDemoCapabilityContract.verticalScrollResponse(position: request.position, tab: tab)
    }

    private func handleHorizontalScroll(_ request: UIKitDemoHorizontalScrollRequest) -> UIKitDemoResponse {
        do {
            let tab = try store.resolveHorizontalTarget(request.target)
            select(tab: tab, animated: true)
            return UIKitDemoCapabilityContract.tabSelectResponse(for: tab)
        } catch let error as UIKitDemoCapabilityError {
            return error.response
        } catch {
            return UIKitDemoCapabilityError.unexpectedError.response
        }
    }

    private func handleVisible() -> UIKitDemoResponse {
        let tab = store.selectedTab
        switch tab {
        case .feed:
            let visible = feedPage?.visibleCards() ?? []
            return UIKitDemoCapabilityContract.visibleResponse(
                tab: tab,
                visible: visible.map { .object(["id": .string($0.id), "title": .string($0.title)]) },
                total: store.count(for: .feed)
            )
        case .items:
            let visible = itemsPage?.visibleItems() ?? []
            return UIKitDemoCapabilityContract.visibleResponse(
                tab: tab,
                visible: visible.map { .string($0) },
                total: currentItems.count
            )
        }
    }

    private func select(tab: UIKitDemoTab, animated: Bool) {
        store.select(tab)
        syncSelection(animated: animated)
    }

    private func syncSelection(animated: Bool) {
        let selectedTab = store.selectedTab
        activeTabLabel.text = "Active tab: \(selectedTab.title)"
        tabStripView.updateTabs(UIKitDemoTab.allCases, selected: selectedTab)

        if selectedTab == .feed {
            refreshFeedPage()
        } else {
            itemsPage?.apply(items: currentItems, restoringOffset: store.verticalOffset(for: .items))
        }

        let index = CGFloat(UIKitDemoTab.allCases.firstIndex(of: selectedTab) ?? 0)
        let targetOffset = CGPoint(x: index * pagerScrollView.bounds.width, y: 0)
        if pagerScrollView.bounds.width > 0 {
            pagerScrollView.setContentOffset(targetOffset, animated: animated)
        }
    }

    private func refreshFeedPage() {
        feedPage?.apply(cards: store.cards(for: .feed), restoringOffset: store.verticalOffset(for: .feed))
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        syncSelectionFromPager()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        syncSelectionFromPager()
    }

    private func syncSelectionFromPager() {
        guard pagerScrollView.bounds.width > 0 else { return }
        let rawIndex = pagerScrollView.contentOffset.x / pagerScrollView.bounds.width
        let index = max(0, min(Int(round(rawIndex)), UIKitDemoTab.allCases.count - 1))
        let tab = UIKitDemoTab.allCases[index]
        store.select(tab)
        activeTabLabel.text = "Active tab: \(tab.title)"
        tabStripView.updateTabs(UIKitDemoTab.allCases, selected: tab)
        if tab == .feed {
            refreshFeedPage()
        } else {
            itemsPage?.apply(items: currentItems, restoringOffset: store.verticalOffset(for: .items))
        }
    }
}

private extension UIFont {
    func bold() -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
```

- [ ] **Step 2: Delete `UIKitDemoPageViewController.swift`**

```bash
git rm examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoPageViewController.swift
```

- [ ] **Step 3: Build — expect clean**

```bash
cd examples/ios && xcodebuild build \
  -workspace RemoExample.xcworkspace \
  -scheme RemoExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **` with no errors.

- [ ] **Step 4: Commit**

```bash
git add examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoViewController.swift
git commit -m "feat: wire UIKitDemoViewController to new feed/items page VCs and grid.* capabilities"
```

---

## Task 7: Update `UIKitDemoScreen` and `ContentView`

**Files:**
- Modify: `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoScreen.swift`
- Modify: `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/ContentView.swift`

- [ ] **Step 1: Update `UIKitDemoScreen.swift` to accept and push `AppStore`**

Replace file contents:

```swift
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
```

- [ ] **Step 2: Update `ContentView.swift`**

**2a. Move `items.add`, `items.remove`, `items.clear` into `setupRemo`**

In `setupRemo(store:)`, add after the `ui.setAccentColor` block:

```swift
logged(store: store, "items.add") { params in
    let name = params["name"] as? String ?? "New Item"
    DispatchQueue.main.async {
        withAnimation { store.items.append(name) }
    }
    return ["status": "ok", "name": name]
}

logged(store: store, "items.remove") { params in
    let name = params["name"] as? String ?? ""
    DispatchQueue.main.async {
        withAnimation {
            if let idx = store.items.firstIndex(of: name) {
                store.items.remove(at: idx)
            }
        }
    }
    return ["status": "ok", "name": name]
}

logged(store: store, "items.clear") { _ in
    DispatchQueue.main.async {
        withAnimation { store.items.removeAll() }
    }
    return ["status": "ok"]
}
```

**2b. In `TabView`, remove `ListPage` and rename the UIKit tab to "Grid"**

Find the `TabView` body in `ContentView` and replace it with:

```swift
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
```

**2c. Remove `ListPage.body`'s capability registration**

Delete the `.task` and `.onDisappear` modifiers from `ListPage` that registered `items.add`, `items.remove`, `items.clear` (those three `logged(store:...)` calls and the `.onDisappear` block that unregisters them). Keep the list UI unchanged. The `ListPage` struct itself is deleted entirely since its tab was removed — delete the entire `// MARK: - Items` section (`ListPage`, `DetailPage`).

- [ ] **Step 3: Build and run on simulator**

```bash
cd examples/ios && xcodebuild build \
  -workspace RemoExample.xcworkspace \
  -scheme RemoExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

Then launch on the booted simulator:

```bash
xcrun simctl install "97D18D39-5270-46DD-97A1-A09089D52845" \
  ~/Library/Developer/Xcode/DerivedData/RemoExample-fqerhbgknzsdoteogkixohoqprzt/Build/Products/Debug-iphonesimulator/RemoExample.app
xcrun simctl launch "97D18D39-5270-46DD-97A1-A09089D52845" com.remo.example
```

Verify visually: bottom tab bar shows Home · Grid · Activity · Settings. Tap Grid — see Feed and Items tabs in the pager. Items tab shows 20 items.

- [ ] **Step 4: Commit**

```bash
git add examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/UIKitDemo/UIKitDemoScreen.swift \
        examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/ContentView.swift
git commit -m "feat: wire AppStore.items into Grid tab, remove SwiftUI Items tab"
```

---

## Task 8: Update docs

**Files:**
- Modify: `examples/ios/README.md`
- Modify: `README.md`

- [ ] **Step 1: Update `examples/ios/README.md`**

Replace the file with the following (keep the Run section and Architecture section structure, update everything else):

```markdown
# RemoExample

A demo iOS app showcasing the Remo SDK under Swift 6 strict concurrency. It registers background `@Sendable` capabilities, invokes them from the CLI, and verifies the UI.

The app includes both SwiftUI and UIKit integration examples:
- SwiftUI tabs that register page-scoped capabilities in `.task`
- A dedicated **Grid** tab backed by a real `UIViewController`
- A UIKit callback bridge that hands UI work back to the main queue explicitly

## Run

\`\`\`bash
# Option 1: Use published SDK (default)
open RemoExample.xcworkspace

# Option 2: Use local monorepo source (for SDK development)
REMO_LOCAL=1 xcodebuild build -workspace RemoExample.xcworkspace -scheme RemoExample \
  -destination 'platform=iOS Simulator,name=iPhone 17'
\`\`\`

Build and run `RemoExample` scheme on a simulator or device.

The app target is configured for Swift 6 with strict concurrency checking. `Remo.register` handlers therefore compile under the same contract expected by downstream SDK users: background callback execution with `@Sendable` closures.

## Capabilities

The app registers capabilities at different scopes to demonstrate both global and page-level (dynamic) registration.

### Global (always available)

| Capability | Description | Example |
|------------|-------------|---------|
| `navigate` | Switch tab | `remo call navigate '{"route":"uikit"}'` |
| `state.get` | Read state | `remo call state.get '{"key":"counter"}'` |
| `state.set` | Write state | `remo call state.set '{"key":"username","value":"Alice"}'` |
| `ui.toast` | Show toast | `remo call ui.toast '{"message":"Hello!"}'` |
| `ui.confetti` | Trigger confetti | `remo call ui.confetti '{}'` |
| `ui.setAccentColor` | Change theme | `remo call ui.setAccentColor '{"color":"purple"}'` |
| `items.add` | Add item | `remo call items.add '{"name":"New"}'` |
| `items.remove` | Remove item | `remo call items.remove '{"name":"Morning Standup"}'` |
| `items.clear` | Clear all items | `remo call items.clear '{}'` |

### Home tab (available when Home is visible)

| Capability | Description | Example |
|------------|-------------|---------|
| `counter.increment` | Bump counter | `remo call counter.increment '{"amount":5}'` |

### Grid tab (available when Grid is visible)

| Capability | Description | Example |
|------------|-------------|---------|
| `grid.tab.select` | Select Feed or Items tab | `remo call grid.tab.select '{"id":"items"}'` |
| `grid.feed.append` | Append a card to the Feed grid | `remo call grid.feed.append '{"title":"Pinned","subtitle":"Added from CLI"}'` |
| `grid.feed.reset` | Reset Feed cards to seed | `remo call grid.feed.reset '{}'` |
| `grid.scroll.vertical` | Scroll active page | `remo call grid.scroll.vertical '{"position":"bottom"}'` |
| `grid.scroll.horizontal` | Navigate between tabs | `remo call grid.scroll.horizontal '{"direction":"next"}'` |
| `grid.visible` | Return currently visible items | `remo call grid.visible '{}'` |

> The Grid tab uses the same background callback contract. Its `UIViewController` registers `grid.*` capabilities and synchronizes the tab strip, horizontal pager, and per-tab collection views by dispatching UIKit work back to the main queue.

## Try It

\`\`\`bash
# 1. Discover the running app
remo devices

# 2. List currently available capabilities
remo list -a <addr>

# 3. Navigate to Grid tab
remo call -a <addr> navigate '{"route":"uikit"}'

# 4. See which items are visible on load (~8 of 20)
remo call -a <addr> grid.visible '{}'

# 5. Scroll to bottom — a different slice becomes visible
remo call -a <addr> grid.scroll.vertical '{"position":"bottom"}'
remo call -a <addr> grid.visible '{}'

# 6. Add an item — it appears in the Items tab immediately
remo call -a <addr> items.add '{"name":"Hot Fix"}'

# 7. Switch to Items tab and verify
remo call -a <addr> grid.tab.select '{"id":"items"}'
remo call -a <addr> grid.visible '{}'

# 8. Switch back to Feed
remo call -a <addr> grid.tab.select '{"id":"feed"}'

# 9. Append a card to the Feed grid
remo call -a <addr> grid.feed.append '{"title":"Pinned","subtitle":"Added from CLI"}'

# 10. Take a screenshot to verify
remo screenshot -a <addr> -o screen.jpg
\`\`\`

## Architecture

\`\`\`
RemoExample.xcworkspace
├── RemoExample/                  # App shell (entry point only)
├── RemoExamplePackage/           # All feature code (SPM)
│   └── Sources/RemoExampleFeature/
│       ├── ContentView.swift     # SwiftUI views + global capability registration
│       └── UIKitDemo/            # Grid tab: pager, feed, items list, and bridge
├── Config/                       # XCConfig build settings
└── RemoExampleUITests/           # UI automation tests
\`\`\`

Global capabilities (`items.add`, `items.remove`, `items.clear`, navigation, UI) are registered once at app launch in `setupRemo()`. The Grid tab (`UIKitDemoViewController`) registers `grid.*` capabilities while it is alive and unregisters them on `deinit`. `AppStore.items` is pushed into the Grid tab via `UIKitDemoScreen.updateUIViewController` whenever the array changes.
```

- [ ] **Step 2: Update root `README.md`**

Find the line:
```
The iOS example app includes a dedicated UIKit tab that demonstrates this pattern in a `UIViewController` with nested scrolling, a horizontal pager, and `uikit.*` capabilities wired through the same background callback contract.
```

Replace with:
```
The iOS example app includes a dedicated Grid tab that demonstrates this pattern in a `UIViewController` with nested scrolling, a horizontal pager, and `grid.*` capabilities wired through the same background callback contract.
```

- [ ] **Step 3: Commit**

```bash
git add examples/ios/README.md README.md
git commit -m "docs: update README for Grid tab and grid.* capabilities"
```

---

## Task 9: Final build, test, and verify

- [ ] **Step 1: Run all unit tests**

```bash
cd examples/ios/RemoExamplePackage && swift test 2>&1 | grep -E "passed|failed|error:"
```

Expected: `Test run with 6 tests passed`.

- [ ] **Step 2: Full build**

```bash
cd examples/ios && xcodebuild build \
  -workspace RemoExample.xcworkspace \
  -scheme RemoExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "error:|warning:.*error|BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run e2e smoke test on simulator**

```bash
# Install and launch
xcrun simctl install "97D18D39-5270-46DD-97A1-A09089D52845" \
  ~/Library/Developer/Xcode/DerivedData/RemoExample-fqerhbgknzsdoteogkixohoqprzt/Build/Products/Debug-iphonesimulator/RemoExample.app
xcrun simctl launch "97D18D39-5270-46DD-97A1-A09089D52845" com.remo.example
```

Then with `remo` CLI (substituting `<addr>` from `remo devices`):

```bash
remo call -a <addr> navigate '{"route":"uikit"}'
remo call -a <addr> grid.visible '{}'
# → {"tab":"feed","visible":[...],"count":N,"total":6}

remo call -a <addr> grid.tab.select '{"id":"items"}'
remo call -a <addr> grid.visible '{}'
# → {"tab":"items","visible":[...],"count":N,"total":20}

remo call -a <addr> grid.scroll.vertical '{"position":"bottom"}'
remo call -a <addr> grid.visible '{}'
# → different slice of items

remo call -a <addr> items.add '{"name":"Smoke Test Item"}'
remo call -a <addr> grid.visible '{}'
# → total is now 21

remo list -a <addr> | grep uikit
# → no results (uikit.* should not appear)
```

- [ ] **Step 4: Commit if anything was fixed during verification**

```bash
git add -p
git commit -m "fix: address issues found during e2e verification"
```
