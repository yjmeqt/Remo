# UIKit Grid Tab Redesign

## Summary

Redesign the UIKit demo tab in `RemoExample`:

- Rename the tab from "UIKit" to "Grid"
- Replace the three-tab pager (Featured / Recent / Saved) with a two-tab pager: **Feed** and **Items**
- Feed tab: dual-column card grid backed by `UIKitDemoFeedPageViewController`
- Items tab: inset-grouped list synced to `AppStore.items`, backed by `UIKitDemoItemsPageViewController`
- Remove the SwiftUI `Items` tab from the root `TabView`
- Bottom tab bar becomes: **Home · Grid · Activity · Settings**

## Goals

- Show a richer UIKit demo with two distinct collection-view patterns in one screen.
- Demonstrate live sync between a UIKit list and shared SwiftUI state (`AppStore.items`).
- Keep the existing Remo capability contract intact; move item capabilities to global scope.

## Non-Goals

- Change the Home, Activity, or Settings tabs.
- Add navigation or detail views inside the UIKit Feed or Items pages.
- Add persistence beyond what `AppStore` already provides.

## Screen Structure

The Grid tab retains the existing shell: vertically scrolling root → header → horizontally scrollable tab strip → horizontally paging content area.

| Tab | ID | VC | Layout |
|-----|----|----|--------|
| Feed | `"feed"` | `UIKitDemoFeedPageViewController` | 2-column compositional grid |
| Items | `"items"` | `UIKitDemoItemsPageViewController` | `UICollectionViewCompositionalLayout.list()` |

Tab strip remains horizontally scrollable (ready to add more tabs in the future).

## Data & Sync

### AppStore seed

`AppStore.items` expands from 3 to 10 seed items so the Items page looks populated on first launch:

```swift
public var items: [String] = [
    "Morning Standup", "Design Review", "Sprint Planning", "API Integration",
    "Code Review", "Remo Demo", "Release Notes", "User Testing",
    "Launch Prep", "Post-mortem"
]
```

### Capability ownership

`items.add`, `items.remove`, `items.clear` move from `ListPage.body` (deleted) to `setupRemo` — globally registered at app launch. They continue to mutate `AppStore.items`.

`uikit.items.append` remains Feed-only: appends a `UIKitDemoCard` to the card grid. It does not affect `AppStore.items`.

### UIKit sync path

`UIKitDemoScreen` (`UIViewControllerRepresentable`) accepts `AppStore` and pushes `items` changes in `updateUIViewController`:

```swift
func updateUIViewController(_ uiViewController: UIKitDemoViewController, context: Context) {
    uiViewController.updateItems(store.items)
}
```

`UIKitDemoViewController.updateItems(_:)` forwards to `UIKitDemoItemsPageViewController.apply(items:)`, which applies an animated `NSDiffableDataSourceSnapshot` — no full reload.

## Components

### Files changed

| File | Change |
|------|--------|
| `ContentView.swift` | Remove `ListPage` tab; move `items.*` capabilities to `setupRemo`; rename UIKit tab label to "Grid" |
| `AppStore` (in `ContentView.swift`) | Expand `items` seed to 10 entries |
| `UIKitDemoModels.swift` | Replace `UIKitDemoTab` cases `.featured/.recent/.saved` with `.feed/.items` |
| `UIKitDemoViewController.swift` | Instantiate `UIKitDemoFeedPageViewController` or `UIKitDemoItemsPageViewController` per tab; add `updateItems(_:)` |
| `UIKitDemoScreen.swift` | Accept `AppStore`; implement `updateUIViewController` to push items |

### Files added

| File | Purpose |
|------|---------|
| `UIKitDemoFeedPageViewController.swift` | Dual-column card grid; extracts current `UIKitDemoPageViewController` grid logic |
| `UIKitDemoItemsPageViewController.swift` | `UICollectionViewCompositionalLayout.list()` + `NSDiffableDataSourceSnapshot<Section, String>` |

### Files deleted

| File | Reason |
|------|--------|
| `UIKitDemoPageViewController.swift` | Replaced by the two purpose-built page VCs above |

## Capability Map

| Capability | Scope | Effect |
|-----------|-------|--------|
| `uikit.tab.select` | UIKit tab visible | Select Feed (`"feed"`) or Items (`"items"`) by id or index |
| `uikit.items.append` | UIKit tab visible | Append `UIKitDemoCard` to Feed tab grid |
| `uikit.items.reset` | UIKit tab visible | Reset Feed tab cards to seed data (does not affect `AppStore.items`) |
| `uikit.scroll.vertical` | UIKit tab visible | Scroll active page to top/middle/bottom |
| `uikit.scroll.horizontal` | UIKit tab visible | Navigate between Feed and Items tabs |
| `items.add` | Global | Append string to `AppStore.items` (appears in Items tab) |
| `items.remove` | Global | Remove string from `AppStore.items` |
| `items.clear` | Global | Clear `AppStore.items` |

## Implementation Notes

- `UIKitDemoItemsPageViewController` uses `UICollectionView.CellRegistration<UICollectionViewListCell, String>` with `UIHostingConfiguration` for the row content.
- `UIKitDemoFeedPageViewController` uses `UICollectionView.CellRegistration<UICollectionViewCell, UIKitDemoCard>` with `UIHostingConfiguration` for the card content.
- The parent VC calls `feedPage.apply(cards:)` or `itemsPage.apply(items:)` directly — no shared protocol needed since the two data types differ.
- Per-tab vertical scroll offset preservation remains in `UIKitDemoStore` unchanged.
- The `CapabilityBridge` pattern in `UIKitDemoViewController` is unchanged.
