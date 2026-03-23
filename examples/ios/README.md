# RemoExample

A demo iOS app showcasing the Remo SDK — register capabilities, invoke them from the CLI, and verify the UI.

## Run

```bash
# Option 1: Use published SDK (default)
open RemoExample.xcworkspace

# Option 2: Use local monorepo source (for SDK development)
REMO_LOCAL=1 xcodebuild build -workspace RemoExample.xcworkspace -scheme RemoExample \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Build and run `RemoExample` scheme on a simulator or device.

## Capabilities

The app registers capabilities at different scopes to demonstrate both global and page-level (dynamic) registration.

### Global (always available)

| Capability | Description | Example |
|------------|-------------|---------|
| `navigate` | Switch tab | `remo call navigate '{"route":"items"}'` |
| `state.get` | Read state | `remo call state.get '{"key":"counter"}'` |
| `state.set` | Write state | `remo call state.set '{"key":"username","value":"Alice"}'` |
| `ui.toast` | Show toast | `remo call ui.toast '{"message":"Hello!"}'` |
| `ui.confetti` | Trigger confetti | `remo call ui.confetti '{}'` |
| `ui.setAccentColor` | Change theme | `remo call ui.setAccentColor '{"color":"purple"}'` |

### Home tab (available when Home is visible)

| Capability | Description | Example |
|------------|-------------|---------|
| `counter.increment` | Bump counter | `remo call counter.increment '{"amount":5}'` |

### Items tab (available when Items is visible)

| Capability | Description | Example |
|------------|-------------|---------|
| `items.add` | Add item | `remo call items.add '{"name":"New"}'` |
| `items.remove` | Remove item | `remo call items.remove '{"name":"Item A"}'` |
| `items.clear` | Clear all | `remo call items.clear '{}'` |

### Detail page (available when viewing an item)

| Capability | Description | Example |
|------------|-------------|---------|
| `detail.getInfo` | Get current item | `remo call detail.getInfo '{}'` |

> Page-level capabilities are registered with `Remo.register` in `.task` and unregistered with `Remo.unregister` in `.onDisappear`. Use `remo list` to see which capabilities are currently active.

## Try It

```bash
# 1. Discover the running app
remo devices

# 2. List currently available capabilities
remo list -a <addr>

# 3. Invoke a global capability
remo call -a <addr> ui.toast '{"message":"Hello from CLI!"}'

# 4. Navigate to Items tab, then list again — items.* capabilities appear
remo call -a <addr> navigate '{"route":"items"}'
remo list -a <addr>

# 5. Navigate away — items.* capabilities disappear
remo call -a <addr> navigate '{"route":"home"}'
remo list -a <addr>

# 6. Take a screenshot to verify
remo screenshot -a <addr> -o screen.jpg
```

## Architecture

```
RemoExample.xcworkspace
├── RemoExample/                  # App shell (entry point only)
├── RemoExamplePackage/           # All feature code (SPM)
│   └── Sources/RemoExampleFeature/
│       └── ContentView.swift     # Views + capability registration
├── Config/                       # XCConfig build settings
└── RemoExampleUITests/           # UI automation tests
```

All capabilities are registered in `ContentView.swift`:
- Global capabilities in `setupRemo()` (called once at app launch)
- Page-level capabilities in each view's `.task` / `.onDisappear`
