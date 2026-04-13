# UIKit Demo Tab Design

## Summary

Add a dedicated `UIKit` tab to `RemoExample` that demonstrates safe Remo usage inside a UIKit-based environment. The tab will host a real `UIViewController` embedded in the existing SwiftUI shell. That controller will present:

- a vertically scrollable page
- a horizontally scrollable tab strip with three tabs
- a horizontally paging content area below the tab strip
- three distinct iOS 17+ `UICollectionView` pages, one per tab

The UIKit demo is explicitly meant to show the correct concurrency pattern for Remo in UIKit: capability callbacks are treated as background callbacks, and all UIKit work is handed off to the main queue.

## Goals

- Provide a first-party UIKit example for Remo users who do not work in a pure SwiftUI environment.
- Demonstrate a realistic UIKit screen rather than a toy label/button sample.
- Show a copyable Remo integration pattern inside a `UIViewController`.
- Demonstrate modern UIKit collection patterns rather than legacy flow-layout-only code.
- Keep the existing SwiftUI example app shell intact.

## Non-Goals

- Rebuild the example app around UIKit navigation.
- Create a second standalone example app target.
- Add complex persistence, networking, or data loading to the UIKit demo.

## Recommended Approach

Keep the current SwiftUI `TabView` and add one dedicated `UIKit` tab. Host a real `UIViewController` via `UIViewControllerRepresentable`.

This is preferred over a separate target or a mostly-SwiftUI wrapper because it demonstrates the migration path many users actually have: a SwiftUI shell with UIKit-based screens, or a codebase that still centers on view controllers.

## UI Structure

The UIKit demo screen should contain:

1. A vertically scrolling root page.
2. A short header describing that this is a UIKit + Remo concurrency demo.
3. A horizontally scrollable tab strip with three tabs.
4. A horizontally paging content area below the tab strip.
5. Three collection-view-backed pages, one per tab.

Interaction rules:

- Tapping a tab scrolls the horizontal pager to the matching page.
- Swiping horizontally between pages updates the active tab.
- Each page has its own vertically scrolling `UICollectionView`.
- The outer page remains vertically scrollable above the pager.
- The header and tab strip scroll away with the outer page; they are not sticky.
- Each tab page preserves its own vertical collection-view scroll offset when switching away and back.
- When the active tab changes by tap, swipe, or Remo command, the selected tab indicator, pager position, and active dataset remain synchronized.
- Horizontal swipes should only change the inner pager. Vertical drags inside a collection view should only scroll that collection view once the pager area is active and visible.

The three tabs must represent three different UIKit collection-view patterns rather than three copies of the same page:

1. `Cards`
   A two-column editorial-style card layout.
2. `Settings`
   A settings-style multi-section inset-grouped list.
3. `Grid`
   A traditional compact multi-column collection grid.

## Component Split

The implementation should avoid adding more UIKit-specific complexity to the existing large SwiftUI file. Add focused files under the example package:

- `UIKitDemoScreen`
  A `UIViewControllerRepresentable` bridge inserted into the SwiftUI tab shell.
- `UIKitDemoViewController`
  Owns Remo integration, tab selection state, pager coordination, and parent page layout.
- `UIKitDemoTabStripView`
  A horizontally scrollable tab selector.
- Three child page controllers
  Each page owns one modern `UICollectionView` configuration, layout, and diffable data source:
  - `UIKitCardsPageViewController`
  - `UIKitSettingsPageViewController`
  - `UIKitGridPageViewController`
- Shared UIKit demo models
  Tab identifiers plus page-specific item and section models scoped to this feature.

Exact file names can vary, but UIKit code should be isolated from the existing SwiftUI screen logic.

## Data Model

Use in-memory demo data only.

Suggested structure:

- `UIKitDemoTab`
  Three fixed tabs, each with a title and identifier.
- `UIKitCardsItem`
  Card-style model used by the two-column layout.
- `UIKitSettingsSection` and `UIKitSettingsItem`
  Settings-style section and row models with stable identifiers.
- `UIKitGridItem`
  Compact tile model for the multi-column grid.
- Per-tab seed data
  Independent arrays or sections keyed by tab.

The controller owns:

- `selectedTab`
- per-tab datasets and per-tab vertical offsets
- references needed to coordinate tab strip, pager, and visible collection view

The store should not force all tabs through one shared item model. Each tab keeps its own native structure so the example remains realistic and the diffable snapshots stay clear.

## Modern UICollectionView Stack

The UIKit demo should intentionally use iOS 17+ collection-view APIs and avoid legacy patterns.

Required stack:

- `UICollectionViewCompositionalLayout`
- `UICollectionViewDiffableDataSource`
- `UICollectionView.CellRegistration`
- `UICollectionView.SupplementaryRegistration`
- `UIListContentConfiguration`
- `UICellAccessory`

Recommended by page:

- `Cards`
  Use a compositional two-column layout with expressive card sizing and spacing.
- `Settings`
  Use `UICollectionLayoutListConfiguration` with an inset-grouped appearance, section headers, and mixed row accessories.
- `Grid`
  Use a compositional fixed-column grid with tighter spacing and a more utility-oriented visual rhythm.

The implementation should avoid:

- `UICollectionViewFlowLayout`
- `UICollectionViewDataSource` / `UICollectionViewDelegateFlowLayout` as the primary rendering path
- `reloadData()` as the primary state update mechanism

Diffable snapshots should be the default update path for append, reset, and tab-specific data refresh.

## Remo Capability Set

Keep the capability set small and demonstrative:

- `uikit.tab.select`
  Select a tab by index or identifier.
- `uikit.items.append`
  Append a demo item to the active tab or a specified tab.
- `uikit.items.reset`
  Reset one tab or all tabs to the original demo data.
- `uikit.scroll.vertical`
  Scroll the active collection view to top, middle, or bottom.
- `uikit.scroll.horizontal`
  Move to next/previous tab or to a specified tab.

Capability contract:

- `uikit.tab.select`
  Request:
  `{"index": 0}` or `{"id": "recent"}`
  Success:
  `{"status": "ok", "selectedTab": {"index": 0, "id": "featured"}}`
  Failure:
  `{"error": "missing tab identifier"}`
  `{"error": "unknown tab: recent"}`
  `{"error": "tab index out of range: 9"}`

- `uikit.items.append`
  Request:
  `{"tab": "active", "title": "New Card"}`
  or `{"tab": "favorites", "title": "New Card", "subtitle": "Added by Remo"}`
  Success:
  `{"status": "ok", "tab": "favorites", "count": 8}`
  Failure:
  `{"error": "missing title"}`
  `{"error": "unknown tab: favorites"}`

- `uikit.items.reset`
  Request:
  `{"tab": "active"}`
  or `{"tab": "all"}`
  Success:
  `{"status": "ok", "tab": "all"}`
  Failure:
  `{"error": "unknown tab: favorites"}`

- `uikit.scroll.vertical`
  Request:
  `{"position": "top"}`
  `{"position": "middle"}`
  `{"position": "bottom"}`
  Success:
  `{"status": "ok", "position": "bottom", "tab": "featured"}`
  Failure:
  `{"error": "unknown position: center"}`

- `uikit.scroll.horizontal`
  Request:
  `{"direction": "next"}`
  or `{"index": 2}`
  or `{"id": "favorites"}`
  Success:
  `{"status": "ok", "selectedTab": {"index": 2, "id": "favorites"}}`
  Failure:
  `{"error": "already at last tab"}`
  `{"error": "missing scroll target"}`
  `{"error": "unknown tab: favorites"}`

Default resolution rules:

- `tab: "active"` means the currently visible tab.
- Omitting `tab` for `uikit.items.append` and `uikit.items.reset` targets the active tab.
- For `uikit.tab.select`, providing both `index` and `id` is invalid.
- For `uikit.scroll.horizontal`, exactly one of `direction`, `index`, or `id` is allowed.
- All error payloads should use a stable top-level `error` string for easy CLI assertions.

These capabilities are sufficient to demonstrate:

- Remo-driven UIKit state mutation
- horizontal page switching
- vertical scrolling inside a collection view
- diffable snapshot updates across three different collection styles
- synchronization between visual state and Remo commands

Behavior by page:

- `Cards`
  `uikit.items.append` adds a new card to the two-column card feed.
- `Settings`
  `uikit.items.append` adds a new row to a stable target section or a default section for the demo.
- `Grid`
  `uikit.items.append` adds a new tile to the compact grid.

## Concurrency Contract

This UIKit tab must serve as the canonical example of safe Remo usage in UIKit.

Requirements:

- Register UIKit demo capabilities exactly once in `viewDidLoad`.
- Use a local `hasRegisteredCapabilities` guard so repeated lifecycle transitions cannot duplicate registrations.
- Treat Remo callbacks as background callbacks.
- Do not touch UIKit directly inside the callback body.
- Parse input and form result payloads off-main when practical.
- Dispatch UIKit work to the main queue explicitly.
- Keep the UIKit demo capabilities registered for the lifetime of the hosted view controller instance.
- Unregister all UIKit demo capabilities in `deinit`.
- Do not register and unregister on every appearance transition; SwiftUI `TabView` hosting can keep the controller alive while changing visibility, so appearance callbacks are not the lifecycle boundary for capability ownership.
- Apply collection-view mutations by building and applying diffable snapshots on the main thread.

The code should make this pattern obvious through local comments and naming, not just through README text.

## Documentation Updates

Update the example docs so users can discover the UIKit demo quickly:

- `examples/ios/README.md`
  Mention the new `UIKit` tab and what it demonstrates.
- `README.md`
  Optionally point to the example app’s UIKit tab as the canonical UIKit integration demo if the wording stays concise.

The docs should explain that this tab is specifically intended to help users understand Remo usage in UIKit-based environments.

## Verification

At minimum, verify:

1. The example app builds and runs with the new `UIKit` tab.
2. The `UIKit` tab appears inside the existing SwiftUI shell.
3. Tab taps, horizontal swipes, and Remo-driven tab changes stay in sync.
4. The header and tab strip scroll with the outer page rather than sticking.
5. Each collection view scrolls vertically as expected, and returning to a tab restores its previous vertical offset.
6. Horizontal swipe gestures change the pager without breaking vertical collection scrolling.
7. The `Cards` tab renders as a two-column card layout rather than a single-column list.
8. The `Settings` tab renders as an inset-grouped multi-section list with headers and row accessories.
9. The `Grid` tab renders as a compact multi-column grid with uniform tile sizing.
10. The Remo capabilities can switch tabs, append items, reset items, and scroll using the documented request/response shapes.
11. Invalid Remo payloads return stable error JSON instead of silently no-oping.
12. The UIKit demo controller does not duplicate capability registration across tab switches or appearance transitions.

If feasible, add at least lightweight verification that the new UIKit demo wiring compiles cleanly under the current Swift 6 strict-concurrency example setup.

## Risks

- Nested scrolling and sizing can become fragile if the outer vertical page and inner collection views fight for gesture ownership.
- Three independent diffable collection implementations can drift stylistically if the visual system is not coordinated.
- Pager state can become harder to reason about if too much per-page logic is centralized in one controller.
- Registering capabilities at the wrong lifecycle boundary can lead to duplicate registrations or stale handlers.

The implementation should prefer the simplest controller structure that preserves clear ownership and predictable registration/unregistration behavior.
