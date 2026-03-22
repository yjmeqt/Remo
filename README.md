# Remo

**Infrastructure for AI-driven iOS development.**

Remo bridges macOS and iOS over RPC, giving AI coding agents the eyes and hands they need to autonomously build, test, and debug iOS apps. Embed the SDK, and any agent (or human) can discover the device, inspect the view tree, take screenshots, read state, and invoke custom capabilities — closing the write → test → fix loop without leaving the terminal.

```
$ remo tree -a 127.0.0.1:51363 -m 2
UIWindow (0, 0, 402x874)
  UITransitionView (0, 0, 402x874)
    UIDropShadowView (0, 0, 402x874)
      UILayoutContainerView (0, 0, 402x874) (+42 children)

$ remo screenshot -a 127.0.0.1:51363 -o screen.jpg
Screenshot saved to screen.jpg (
131
 KB, 1206x2622 @3x)

$ remo call -a 127.0.0.1:51363 counter.increment '{"amount":5}'
{"status":"ok","data":{"previous":0,"current":5}}
```

<!-- TODO: add a demo GIF here showing agent + terminal + simulator side by side -->

## Why Remo?

- **Built for AI agents.** Agents can discover devices, invoke capabilities, inspect the UI, and take screenshots — enabling autonomous write → test → fix loops for iOS development. No human interaction needed.
- **Zero-config introspection.** View tree, screenshot, device info, and app info are available out of the box — no registration required. Embed the SDK, and agents can see everything immediately.
- **Extensible.** Register any custom handler — read CoreData, toggle feature flags, navigate routes, trigger deeplinks. If you can write it in Swift, an agent can call it.
- **Instant feedback.** Mutation → UI update in milliseconds, over USB or Wi-Fi.
- **Rust-powered.** Protocol, transport, server, and ObjC bridge are all Rust. Swift is a thin FFI wrapper.
- **Debug-only by default.** The SDK compiles to no-ops in Release builds (`#if DEBUG`), so it never ships to production.

## How It Works

```
┌──────────────────────────────────┐
│  macOS                           │
│  remo CLI (Rust)                 │
│  ├── Device discovery (Bonjour)  │
│  ├── USB discovery (usbmuxd)    │
│  └── RPC client                  │
└──────────┬───────────────────────┘
           │ TCP (USB tunnel / Wi-Fi / localhost)
┌──────────▼───────────────────────┐
│  iOS                             │
│  remo-sdk (Rust static lib)      │
│  ├── TCP server (tokio)          │
│  ├── Capability registry         │
│  ├── Bonjour advertisement       │
│  ├── Built-in introspection      │
│  └── ObjC bridge (objc2)         │
│  ── FFI boundary ──              │
│  RemoSwift (Swift wrapper)       │
│  Your app registers handlers     │
└──────────────────────────────────┘
```

The iOS SDK starts a TCP server inside your app and advertises it via Bonjour. The macOS CLI auto-discovers devices and sends JSON-RPC requests. Built-in capabilities (view tree, screenshot, device info) are available automatically. Your app can register additional *capabilities* that Remo can call remotely.

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
| `remo-desktop` | macOS library — device manager + RPC client |
| `remo-cli` | CLI tool: `devices`, `call`, `list`, `watch`, `tree`, `screenshot`, `info` |

## CLI Commands

```bash
remo devices                              # Auto-discover devices (USB + Bonjour)
remo call -a <addr> <capability> [params] # Invoke a capability
remo list -a <addr>                       # List registered capabilities
remo watch -a <addr>                      # Stream events from device
remo tree -a <addr>                       # Dump view hierarchy
remo screenshot -a <addr> -o out.jpg      # Take a screenshot
remo info -a <addr>                       # Show device & app info
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

## Project Status

**v0.2.0** — Full end-to-end RPC, Bonjour auto-discovery, multi-simulator support, built-in introspection (view tree, screenshot, device/app info), debug-only SDK, CI/CD pipeline with automated release. See [SPEC.md](SPEC.md) for the full architecture.

### What works now
- Full RPC round-trip: CLI → TCP → iOS SDK → capability handler → response
- Built-in introspection: view tree, screenshot, device info, app info
- Bonjour/mDNS auto-discovery for simulators and Wi-Fi devices
- Multi-simulator support (auto-assigned ports)
- USB device discovery + tunnel via usbmuxd
- Debug-only SDK (`#if DEBUG` — no-ops in Release builds)
- GCD main-thread dispatch for safe UIKit access from Rust
- Graceful server shutdown via `remo_stop()`
- Enhanced example app (counter, items, activity log, toast, confetti, accent color)
- CI pipeline (check, lint, test, iOS build + Swift integration)
- Automated release pipeline (XCFramework → GitHub Release → SPM distribution)

### Roadmap
- [ ] Event streaming (iOS → macOS push)
- [ ] Auto-reconnection on disconnect
- [ ] macOS GUI (SwiftUI device inspector)
- [ ] View property modification (`__view_set`)
- [ ] Protocol versioning / handshake

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

[MIT](LICENSE)
