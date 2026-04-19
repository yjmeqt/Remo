# RemoExample

A demo iOS app showcasing the Remo SDK under Swift 6 strict concurrency. It registers background `@Sendable` capabilities, invokes them from the CLI, and verifies the UI.

The app includes both SwiftUI and UIKit integration examples:
- SwiftUI tabs that register page-scoped capabilities in `.task`
- A dedicated **Grid** tab backed by a real `UIViewController`
- A UIKit callback bridge that hands UI work back to the main queue explicitly

## Run

```bash
# Option 1: Use local monorepo SDK (default)
open RemoExample.xcworkspace

# Option 2: Opt into the published SDK
REMO_USE_REMOTE=1 xcodebuild build -workspace RemoExample.xcworkspace -scheme RemoExample \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

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

```bash
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

# 6. Switch to Items tab and verify the seeded list
remo call -a <addr> grid.tab.select '{"id":"items"}'
remo call -a <addr> grid.visible '{}'

# 7. Switch back to Feed
remo call -a <addr> grid.tab.select '{"id":"feed"}'

# 8. Append a card to the Feed grid
remo call -a <addr> grid.feed.append '{"title":"Pinned","subtitle":"Added from CLI"}'

# 9. Take a screenshot to verify
remo screenshot -a <addr> -o screen.jpg
```

## Architecture

```
RemoExample.xcworkspace
├── RemoExample/                  # App shell (entry point only)
├── RemoExamplePackage/           # All feature code (SPM)
│   └── Sources/RemoExampleFeature/
│       ├── ContentView.swift     # SwiftUI views + global capability registration
│       └── UIKitDemo/            # Grid tab: pager, feed, items list, and bridge
├── Config/                       # XCConfig build settings
└── RemoExampleUITests/           # UI automation tests
```

Global capabilities (navigation, state, and UI) are registered as local typed `RemoCapability` enums inside a single `await #Remo { ... }` block on the root `ContentView.task {}`. The `await #remoScope { ... }` wrapper keeps them registered for the task lifetime and strips the whole island from release builds. The Grid tab (`UIKitDemoViewController`) now keeps its UIKit-only Remo bridge and capability contract together in a dedicated debug-only extension file, while `#remoScope(scopedTo: self)` tracks those `grid.*` capabilities for unregister-on-disappear behavior. `AppStore.items` is still pushed into the Grid tab via `UIKitDemoScreen.updateUIViewController` whenever the array changes.
