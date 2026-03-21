# Remo

**Remotely inspect and control any iOS app from your Mac — in real time.**

Remo is a lightweight bridge between macOS and iOS. Embed the SDK in your app, and you can read state, mutate values, navigate routes, and inspect the view hierarchy — all from a terminal command. The iOS UI reacts instantly.

```
$ remo call 127.0.0.1:9930 state.set '{"key":"username","value":"Remo"}'
{ "status": "ok", "data": { "key": "username", "value": "Remo" } }
# The iOS app immediately shows "Hello, Remo!"
```

<!-- TODO: add a demo GIF here showing terminal + simulator side by side -->

## Why Remo?

- **No Xcode instruments, no Appium, no accessibility hacks.** Your app registers named *capabilities* — typed RPC handlers — and Remo calls them by name.
- **Instant feedback.** Mutation → UI update in milliseconds, over USB or Wi-Fi.
- **Rust-powered.** Protocol, transport, server, and ObjC bridge are all Rust. Swift is a thin FFI wrapper. ~2 000 lines total.
- **Extensible.** Register any handler you want — read CoreData, toggle feature flags, dump analytics state, trigger deeplinks. If you can write it in Swift, Remo can call it.

## How It Works

```
┌─────────────────────────────────┐
│  macOS                          │
│  remo CLI (Rust)                │
│  ├── Device discovery (usbmuxd) │
│  └── RPC client                 │
└──────────┬──────────────────────┘
           │ TCP (USB tunnel / Wi-Fi / localhost)
┌──────────▼──────────────────────┐
│  iOS                            │
│  remo-sdk (Rust static lib)     │
│  ├── TCP server (tokio)         │
│  ├── Capability registry        │
│  └── ObjC bridge (objc2)        │
│  ── FFI boundary ──             │
│  RemoSwift (Swift wrapper)      │
│  Your app registers handlers    │
└─────────────────────────────────┘
```

The iOS SDK starts a TCP server inside your app. The macOS CLI connects and sends JSON-RPC requests. Your app handles them via registered *capabilities* and returns results. Events can flow the other direction too.

## Quick Start

### Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Rust | 1.82+ | Auto-installed via `rust-toolchain.toml` |
| Xcode | 16+ | iOS SDK + Swift 6.1 |
| cbindgen | 0.27+ | Optional — `cargo install cbindgen` |

### Build & Run

```bash
# Clone and build the CLI
git clone https://github.com/yi-jiang-applovin/Remo.git && cd remo
cargo build -p remo-cli

# Build the iOS static library for simulator
./build-ios.sh debug

# Open the example app in Xcode, run on simulator, then:
./target/debug/remo list -a 127.0.0.1:9930
./target/debug/remo call 127.0.0.1:9930 __ping
./target/debug/remo call 127.0.0.1:9930 counter.increment '{"amount":5}'
./target/debug/remo call 127.0.0.1:9930 state.get '{"key":"counter"}'
```

### Integrate in Your App

```swift
import RemoSwift

// In your app's init:
Remo.start(port: 9930)

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
| `remo-sdk` | iOS embedded server + capability registry + C FFI |
| `remo-objc` | ObjC runtime bridge via `objc2` (view tree inspection) |
| `remo-desktop` | macOS library — device manager + RPC client |
| `remo-cli` | CLI tool: `devices`, `call`, `list`, `watch` |

## CLI Commands

```bash
remo devices                              # List USB-connected iOS devices
remo call <addr> <capability> [params]    # Invoke a capability
remo list -a <addr>                       # List registered capabilities
remo watch -a <addr>                      # Stream events from device
```

## Project Status

**v0.1.0-alpha** — Core RPC loop works end-to-end (CLI ↔ simulator). USB tunneling and graceful shutdown are implemented. See [SPEC.md](SPEC.md) for the full architecture and roadmap.

### What works now
- Full RPC round-trip: CLI → TCP → iOS SDK → capability handler → response
- Built-in capabilities: `__ping`, `__list_capabilities`
- USB device discovery via usbmuxd
- USB tunnel support (direct framed I/O over usbmuxd)
- Graceful server shutdown via `remo_stop()`
- View tree inspection via ObjC runtime
- Example app with 4 demo capabilities

### Roadmap
- [ ] Event streaming (iOS → macOS push)
- [ ] Auto-reconnection on disconnect
- [ ] Bonjour/mDNS Wi-Fi discovery
- [ ] macOS GUI (SwiftUI device inspector)
- [ ] Enhanced ObjC bridge (accessibility tree, layer properties)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

[MIT](LICENSE)
