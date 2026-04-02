# UIKit Grid Tab Redesign

## Summary

Redesign the UIKit demo tab in `RemoExample`:

- Rename the tab from "UIKit" to "Grid"
- Replace the three-tab pager (Featured / Recent / Saved) with a two-tab pager: **Feed** and **Items**
- Feed tab: dual-column card grid backed by `UIKitDemoFeedPageViewController`
- Items tab: inset-grouped list synced to `AppStore.items`, backed by `UIKitDemoItemsPageViewController`
- Remove the SwiftUI `Items` tab from the root `TabView`
- Bottom tab bar becomes: **Home · Grid · Activity · Settings**
- All Grid capabilities use the `grid.*` prefix

## Goals

- Show a richer UIKit demo with two distinct collection-view patterns in one screen.
- Demonstrate live sync between a UIKit list and shared SwiftUI state (`AppStore.items`).
- Demonstrate viewport introspection: `grid.visible` returns the currently visible items at any scroll position.
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

`AppStore.items` expands from 3 to 20 seed items so the Items page has enough content to demonstrate scrolling and the `grid.visible` capability:

```swift
public var items: [String] = [
    "Morning Standup", "Design Review", "Sprint Planning", "API Integration",
    "Code Review", "Remo Demo", "Release Notes", "User Testing",
    "Launch Prep", "Post-mortem", "Architecture Review", "Performance Audit",
    "Accessibility Pass", "Localization Check", "Security Review", "Dependency Update",
    "Changelog Draft", "Beta Feedback", "Stakeholder Sync", "Ship It"
]
```

### Capability ownership

`items.add`, `items.remove`, `items.clear` move from `ListPage.body` (deleted) to `setupRemo` — globally registered at app launch. They continue to mutate `AppStore.items`.

`grid.feed.append` is Feed-only: appends a `UIKitDemoCard` to the card grid. It does not affect `AppStore.items`.

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
| `ContentView.swift` | Remove `ListPage` tab; move `items.*` capabilities to `setupRemo`; rename UIKit tab label to "Grid" with icon `square.grid.2x2` |
| `AppStore` (in `ContentView.swift`) | Expand `items` seed to 20 entries |
| `UIKitDemoModels.swift` | Replace `UIKitDemoTab` cases `.featured/.recent/.saved` with `.feed/.items`; rename seed data |
| `UIKitDemoViewController.swift` | Instantiate `UIKitDemoFeedPageViewController` or `UIKitDemoItemsPageViewController` per tab; add `updateItems(_:)`; rename all capability strings from `uikit.*` to `grid.*` |
| `UIKitDemoCapabilityContract.swift` | Rename capability constants and parsers from `uikit.*` to `grid.*` |
| `UIKitDemoScreen.swift` | Accept `AppStore`; implement `updateUIViewController` to push items |
| `examples/ios/README.md` | Update tab bar description, capabilities table, and "Try It" e2e script for `grid.*` |
| `README.md` (root) | Update `uikit.*` reference to `grid.*` |
| `RemoExampleFeatureTests.swift` | Add unit tests for new tab structure and `grid.*` capabilities |

### Files added

| File | Purpose |
|------|---------|
| `UIKitDemoFeedPageViewController.swift` | Dual-column card grid; extracts current `UIKitDemoPageViewController` grid logic |
| `UIKitDemoItemsPageViewController.swift` | `UICollectionViewCompositionalLayout.list()` + `NSDiffableDataSourceSnapshot<Section, String>` |

### Files deleted

| File | Reason |
|------|--------|
| `UIKitDemoPageViewController.swift` | Replaced by the two purpose-built page VCs above |

## Testing

### Unit tests (`RemoExampleFeatureTests.swift`)

- `gridTabCasesAreFeedAndItems` — `UIKitDemoTab.allCases` equals `[.feed, .items]`
- `gridTabIDsMatchExpected` — `UIKitDemoTab.feed.id == "feed"`, `UIKitDemoTab.items.id == "items"`
- `appStoreItemsSeedHasTwentyEntries` — `AppStore().items.count == 20`
- `capabilityNamesUseGridPrefix` — `UIKitDemoCapabilityContract` exposes `grid.*` name constants; no `uikit.*` names present

### e2e script (documented in `examples/ios/README.md`)

The "Try It" section serves as the manual e2e script. It covers:

1. Launch app, discover device: `remo devices`
2. List capabilities: `remo list` — confirm `grid.*` present, no `uikit.*`
3. Switch to Grid tab: `remo call navigate '{"route":"uikit"}'`
4. Check visible items: `remo call grid.visible '{}'` — returns first ~8 of 20 items
5. Scroll to bottom: `remo call grid.scroll.vertical '{"position":"bottom"}'`
6. Check visible again — different slice of items
7. Add an item: `remo call items.add '{"name":"Hot Fix"}'` — appears in Items tab
8. Switch to Items tab: `remo call grid.tab.select '{"id":"items"}'`
9. Switch to Feed: `remo call grid.tab.select '{"id":"feed"}'`
10. Append a card: `remo call grid.feed.append '{"title":"Pinned","subtitle":"Added from CLI"}'`

## Capability Map

| Capability | Scope | Effect |
|-----------|-------|--------|
| `grid.tab.select` | Grid tab visible | Select `"feed"` or `"items"` by `id` or `index` |
| `grid.feed.append` | Grid tab visible | Append `UIKitDemoCard` to Feed grid |
| `grid.feed.reset` | Grid tab visible | Reset Feed cards to seed data (does not affect `AppStore.items`) |
| `grid.scroll.vertical` | Grid tab visible | Scroll active page to `top`/`middle`/`bottom` |
| `grid.scroll.horizontal` | Grid tab visible | Navigate between Feed ↔ Items tabs |
| `grid.visible` | Grid tab visible | Return currently visible items in the active tab |
| `items.add` | Global | Append string to `AppStore.items` (appears in Items tab) |
| `items.remove` | Global | Remove string from `AppStore.items` |
| `items.clear` | Global | Clear `AppStore.items` |

### `grid.visible` response format

For Items tab:
```json
{ "tab": "items", "visible": ["Morning Standup", "Design Review", "Sprint Planning"], "count": 8, "total": 20 }
```

For Feed tab:
```json
{ "tab": "feed", "visible": [{"id": "feed-1", "title": "Hero Spotlight"}], "count": 4, "total": 6 }
```

Implementation: `collectionView.indexPathsForVisibleItems` → look up identifiers from the diffable data source snapshot, sorted by index path.

### Demo story

```bash
# 1. See what's visible on load
remo call grid.visible '{}'
# → items 1-8 visible, total 20

# 2. Scroll to middle
remo call grid.scroll.vertical '{"position":"middle"}'
remo call grid.visible '{}'
# → items 9-16 visible

# 3. Add a new item and watch it appear
remo call items.add '{"name":"Hot Fix"}'

# 4. Switch to Feed tab
remo call grid.tab.select '{"id":"feed"}'
remo call grid.visible '{}'
# → feed cards visible
```

## Implementation Notes

- `UIKitDemoItemsPageViewController` uses `UICollectionView.CellRegistration<UICollectionViewListCell, String>` with `UIHostingConfiguration` for the row content.
- `UIKitDemoFeedPageViewController` uses `UICollectionView.CellRegistration<UICollectionViewCell, UIKitDemoCard>` with `UIHostingConfiguration` for the card content.
- The parent VC calls `feedPage.apply(cards:)` or `itemsPage.apply(items:)` directly — no shared protocol needed since the two data types differ.
- `grid.visible` calls `collectionView.indexPathsForVisibleItems` on the active page VC's collection view and maps index paths to identifiers from the snapshot.
- Per-tab vertical scroll offset preservation remains in `UIKitDemoStore` unchanged.
- The `CapabilityBridge` pattern in `UIKitDemoViewController` is unchanged.
