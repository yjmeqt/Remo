# Remo

**Infrastructure for agentic iOS development.**

Remo gives AI coding agents the **eyes** and **hands** they need to autonomously develop iOS apps. Embed the SDK, register capabilities in Swift, and any agent can discover real devices (USB) and simulators, invoke those capabilities, then **verify the result** via screenshot or captured video — closing the write → build → test → fix loop entirely from code.

```
# Agent writes code, triggers a build, then verifies via Remo:

remo devices                                            # discover real devices (USB) & simulators
remo call -a <addr> counter.increment '{"amount":5}'    # invoke a capability
remo screenshot -a <addr> -o after.jpg                  # capture the result
remo mirror -a <addr> --save recording.mp4              # or record video for animation review
# → Agent compares before/after screenshots to confirm the UI is correct
```

The core loop: **agent writes code → builds → calls Remo capabilities → takes a screenshot or reviews captured video → decides if the change is correct → iterates.** No human in the loop.

<!-- TODO: add a demo GIF here showing agent + terminal + simulator side by side -->

## Why Remo?

- **Agent-first.** Every API is designed for programmatic access. Agents discover real devices (USB) and simulators, invoke capabilities, and verify results — enabling fully autonomous write → test → fix cycles for iOS.
- **Extensible capabilities.** Developers register named handlers in Swift. Agents discover and call them at runtime — read CoreData, toggle feature flags, navigate routes, inject test data. If you can write it in Swift, an agent can call it.
- **Visual verification.** Screenshots and captured video let agents **see what the user sees** after every action. Screenshots for static UI checks; video recording for reviewing animations and transitions.
- **Zero-config introspection.** View tree, screenshot, device info, and app info work out of the box — no registration required.
- **Instant feedback.** Capability call → UI update → screenshot capture in milliseconds, over USB or localhost.
- **Debug-only by default.** The SDK compiles to no-ops in Release builds (`#if DEBUG`), so it never ships to production.

## How It Works

```
┌──────────────────────────────────────┐
│  macOS                               │
│  remo CLI / AI agent                 │
│  ├── USB discovery (usbmuxd)        │
│  ├── Simulator discovery (Bonjour)   │
│  └── RPC client                      │
└──────────┬───────────────────────────┘
           │ TCP (USB tunnel / localhost)
┌──────────▼───────────────────────────┐
│  iOS                                 │
│  remo-sdk (Rust static lib)          │
│  ├── TCP server (tokio)              │
│  ├── Capability registry             │
│  ├── Bonjour advertisement           │
│  ├── Built-in: view tree, screenshot │
│  └── ObjC bridge (objc2)             │
│  ── FFI boundary ──                  │
│  RemoSwift (Swift wrapper)           │
│  Your app registers capabilities     │
└──────────────────────────────────────┘
```

The iOS SDK starts a TCP server inside your app. Real devices are discovered via USB (usbmuxd), simulators via Bonjour/mDNS. The macOS CLI (or any AI agent) sends JSON-RPC requests to invoke capabilities. Built-in capabilities (view tree, screenshot, device info) are available automatically. Your app registers additional *capabilities* that agents can call remotely.

## Quick Start

### Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Rust | 1.82+ | Auto-installed via `rust-toolchain.toml` |
| Xcode | 16+ | iOS SDK + Swift 6.1 |

### Build & Run

```bash
# Clone and set up
git clone https://github.com/yi-jiang-applovin/Remo.git && cd Remo
make setup   # Configure git hooks

# Build the CLI
cargo build -p remo-cli

# Build the iOS XCFramework (simulator only — fast)
./build-ios.sh sim

# Open the example app in Xcode, run on simulator, then:
./target/debug/remo devices                    # Auto-discover via Bonjour
./target/debug/remo info -a 127.0.0.1:<port>   # Device & app info
./target/debug/remo tree -a 127.0.0.1:<port>   # View hierarchy
./target/debug/remo screenshot -a 127.0.0.1:<port>  # Take a screenshot
./target/debug/remo call -a 127.0.0.1:<port> counter.increment '{"amount":5}'
```

### Build Modes

```bash
./build-ios.sh sim        # arm64 simulator only (fastest, ~16s)
./build-ios.sh device     # arm64 real device only (~16s)
./build-ios.sh release    # all targets, optimized (CI / distribution)
```

### Integrate in Your App

```swift
import RemoSwift

// Just register capabilities — the server starts automatically.
// (Simulator: random port to avoid collisions, Device: port 9930 for USB tunnel)
Remo.register("myFeature.toggle") { params in
    let enabled = params["enabled"] as? Bool ?? false
    FeatureFlags.shared.myFeature = enabled
    return ["toggled": enabled]
}
```

## Crates

| Crate | Description |
|-------|-------------|
| `remo-protocol` | Message types + length-prefixed JSON framing codec |
| `remo-transport` | Bidirectional connection over TCP or Unix socket |
| `remo-usbmuxd` | macOS usbmuxd client — device discovery + USB tunneling |
| `remo-bonjour` | Bonjour/mDNS service registration and discovery |
| `remo-sdk` | iOS embedded server + capability registry + C FFI |
| `remo-objc` | ObjC runtime bridge via `objc2` (view tree, screenshot, device info) |
| `remo-desktop` | macOS library — device manager, RPC client, web dashboard, fMP4 muxer |
| `remo-cli` | CLI tool: `devices`, `dashboard`, `call`, `list`, `watch`, `tree`, `screenshot`, `info`, `mirror` |

## CLI Commands

```bash
remo devices                              # Auto-discover devices (USB + Bonjour)
remo dashboard                            # Web dashboard with multi-device UI
remo call -a <addr> <capability> [params] # Invoke a capability
remo list -a <addr>                       # List registered capabilities
remo watch -a <addr>                      # Stream events from device
remo tree -a <addr>                       # Dump view hierarchy
remo screenshot -a <addr> -o out.jpg      # Take a screenshot
remo info -a <addr>                       # Show device & app info
remo mirror -a <addr> --web               # Live screen mirror (H.264 → fMP4)
```

## Built-in Capabilities

These are registered automatically by the SDK — no setup required:

| Capability | Description |
|------------|-------------|
| `__ping` | Connectivity check |
| `__list_capabilities` | List all registered capabilities |
| `__view_tree` | Snapshot the UIView hierarchy as JSON |
| `__screenshot` | Capture the screen (JPEG/PNG, configurable quality) |
| `__device_info` | Device model, OS version, screen dimensions |
| `__app_info` | Bundle ID, version, build number, display name |
| `__start_mirror` | Start H.264 screen mirror stream |
| `__stop_mirror` | Stop mirror stream |

## Web Dashboard

A browser-based demo page for interacting with iOS devices — useful for demos, manual testing, and reviewing animations. Run `remo dashboard` to open it at `http://127.0.0.1:3030`.

## Project Status

**v0.3.0-dev** — Video streaming, web dashboard, multi-device support. See [SPEC.md](SPEC.md) for the full architecture.

### What works now
- **Agentic workflow**: Discover → connect → invoke capability → screenshot/video verify → iterate
- Real device support via USB (usbmuxd) + simulator support via Bonjour (mDNS)
- Full RPC round-trip: CLI → TCP → iOS SDK → capability handler → response
- Built-in introspection: view tree, screenshot, device info, app info
- Screen capture: screenshots + H.264 video recording for animation review
- Multi-simulator support (auto-assigned ports)
- Debug-only SDK (`#if DEBUG` — no-ops in Release builds)
- Web dashboard for demos and manual interaction
- CI pipeline + automated release pipeline (XCFramework → GitHub Release → SPM)

### Roadmap
- [ ] Auto-reconnection on disconnect
- [ ] macOS GUI (SwiftUI device inspector)
- [ ] View property modification (`__view_set`)
- [ ] Protocol versioning / handshake

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

[MIT](LICENSE)
