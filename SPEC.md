# Remo — Project Specification

> Version: 0.3.0-dev
> Last updated: 2026-03-22

## 1. Vision

Remo is infrastructure for AI-driven iOS development. It bridges macOS and iOS over RPC, giving AI coding agents the eyes and hands they need to autonomously build, test, and debug iOS apps — closing the write → test → fix loop that has historically required human interaction on the iOS platform.

The iOS app embeds a lightweight SDK that starts a TCP server and advertises itself via Bonjour. Any client — an AI agent, a CLI tool, or a future GUI — can discover the device, inspect the view hierarchy, take screenshots, read/write state, and invoke custom capabilities. The agent writes code, triggers a build, then uses Remo to verify the result on a real simulator or device — all without leaving the terminal.

### 1.1 Core principles

- **Agent-first**: Every design decision prioritizes programmatic access. CLI commands, JSON-RPC protocol, auto-discovery, and zero-config introspection are all built so that AI agents can operate iOS apps without human assistance.
- **Rust-heavy**: All protocol, transport, server, registry, and ObjC bridge logic is written in Rust. Swift is a thin shell for UI and FFI callbacks.
- **Capability-oriented**: iOS apps don't expose a fixed API. Instead, developers register named handlers at runtime. Agents (or humans) discover and call them.
- **Multi-device**: A single macOS process can manage multiple iOS devices (real or simulated) simultaneously through independent connections.
- **Transport-agnostic**: USB (via usbmuxd), simulator (localhost TCP), and Wi-Fi (Bonjour discovery) all converge on the same framed TCP protocol.

### 1.2 Key use cases

1. **AI Agent development loop**: Agents discover devices, invoke capabilities, inspect UI via view tree, and take screenshots — enabling autonomous write → build → test → fix cycles for iOS development without human interaction.
2. **Remote state manipulation**: Read/write values in an app's `@Observable` store from the Mac. Change a counter, swap a username, inject test data — the iOS UI reacts immediately.
3. **Remote navigation**: Push a route, pop a stack, switch tabs — all from a CLI command or agent call.
4. **Visual verification**: Take screenshots and inspect the view hierarchy as JSON for automated UI validation — essential for agents to confirm their code changes produce the correct visual output.
5. **Custom capabilities**: App developers register arbitrary handlers. Agents can call any of them to exercise app-specific behavior.
6. **Event streaming**: iOS pushes events (state changes, navigation events, logs) to macOS in real time.

---

## 2. Architecture

### 2.1 System layers

```
┌───────────────────────────────────────────┐
│  macOS — Rust binary                      │
│  ┌──────────┐ ┌───────────┐ ┌──────────┐ │
│  │ remo CLI │ │ Device    │ │ RPC      │ │
│  │ (clap)   │ │ Manager   │ │ Client   │ │
│  └────┬─────┘ └─────┬─────┘ └────┬─────┘ │
│       │      ┌───────┼───────┐    │       │
│       │      │ Bonjour│usbmuxd│    │       │
│       │      │ browse │tunnel │    │       │
│       └──────┴───────┴───┬───┴────┘       │
│              ┌───────────┴──┐              │
│              │  transport   │              │
│              └───────┬──────┘              │
└──────────────────────┼────────────────────┘
                       │ USB tunnel / Wi-Fi / localhost
┌──────────────────────┼────────────────────┐
│  iOS — Rust static lib + Swift shell      │
│              ┌───────┴──────┐              │
│              │  transport   │              │
│              └───────┬──────┘              │
│       ┌──────────────┼──────────────┐      │
│  ┌────┴─────┐ ┌──────┴──────┐ ┌────┴───┐  │
│  │ RPC      │ │ Capability  │ │ ObjC   │  │
│  │ Server   │ │ Registry    │ │ Bridge │  │
│  └──────────┘ └──────┬──────┘ └────────┘  │
│       ┌──────────────┼──────────────┐      │
│  ┌────┴───┐ ┌────────┴────┐ ┌──────┴───┐  │
│  │Bonjour │ │ Built-in    │ │ Custom   │  │
│  │advertise│ │ view_tree   │ │ handlers │  │
│  │        │ │ screenshot  │ │ (Swift)  │  │
│  │        │ │ device_info │ │          │  │
│  └────────┘ └─────────────┘ └──────────┘  │
│                                            │
│  ─ ─ ─ ─ ─ ─ FFI boundary (C ABI) ─ ─ ─  │
│                                            │
│  ┌────────────────────────────────────┐    │
│  │ Swift host app (SwiftUI/UIKit)     │    │
│  │ RemoSwift wrapper + App stores     │    │
│  └────────────────────────────────────┘    │
└────────────────────────────────────────────┘
```

### 2.2 Crate topology

| Crate | Platform | Description | Key dependencies |
|---|---|---|---|
| `remo-protocol` | Cross | Message types (`Request`, `Response`, `Event`) + length-prefixed framing codec with JSON (0x00) and binary (0x01) frame types | serde, tokio-util, uuid |
| `remo-transport` | Cross | `Connection` (framed bidirectional TCP pipe) + `Listener` (async accept) | remo-protocol, tokio |
| `remo-usbmuxd` | macOS | usbmuxd Unix socket client: device discovery, TCP tunnel creation | plist, tokio |
| `remo-bonjour` | Cross* | Bonjour/mDNS service registration (iOS) and discovery (macOS) | dns-sd C API |
| `remo-sdk` | iOS | Embedded TCP server + capability registry + built-in capabilities + C ABI FFI layer | remo-protocol, remo-transport, remo-objc, remo-bonjour, base64, dashmap |
| `remo-objc` | iOS* | ObjC runtime bridge: view tree, screenshot, device/app info, GCD main-thread dispatch | objc2, objc2-foundation, objc2-ui-kit |
| `remo-desktop` | macOS | Device manager, RPC client, web dashboard, fMP4 muxer, stream receiver | remo-protocol, remo-transport, remo-usbmuxd, remo-bonjour, axum |
| `remo-cli` | macOS | CLI tool: `devices`, `dashboard`, `call`, `list`, `watch`, `tree`, `screenshot`, `info`, `mirror` | remo-desktop, clap, base64 |

*`remo-objc` compiles on all platforms with stubs; real UIKit access requires the `uikit` feature and an Apple target.

### 2.3 Swift layer

| Component | Role |
|---|---|
| `remo.h` | Manually maintained C header for the FFI boundary |
| `CRemo` module | SPM binary target wrapping `RemoSDK.xcframework` |
| `RemoSwift` package | Thin Swift wrapper with zero-config auto-start: `Remo.register("name") { ... }`. Debug-only (`#if DEBUG`). Server starts automatically on first API access (random port on simulator, 9930 on device). |
| `RemoExample` app | Demo app: 4 tabs (Home, Items, Activity Log, Settings), 10+ capabilities. |

---

## 3. Wire protocol

### 3.1 Framing

Every message on the wire is:

```
┌──────────┬──────────┬─────────────────────────────────────┐
│ len (4B) │ type(1B) │           payload                   │
│ u32 BE   │          │           (len - 1 bytes)           │
└──────────┴──────────┴─────────────────────────────────────┘
```

The `len` field gives the number of bytes that follow (type byte + payload). The type byte selects the frame kind:

**Type 0x00 — JSON frame.** The payload is a UTF-8 JSON object — a `Request`, `Response`, or `Event` (see section 3.2).

**Type 0x01 — Binary frame.** The payload is structured as:

```
┌────────────────┬─────────────────────────┬──────────────────────┐
│ meta_len (4B)  │ JSON metadata           │ raw binary data      │
│ u32 BE         │ (meta_len bytes, UTF-8) │ (remaining bytes)    │
└────────────────┴─────────────────────────┴──────────────────────┘
```

The metadata JSON contains:
- `id` — UUID matching the originating request.
- `metadata` — Capability-specific fields (e.g., image format, dimensions).

Binary frames are used for large payloads (screenshots, file transfers) where base64 encoding would be wasteful.

**Type 0x02 — Stream frame.** The payload is a video/audio stream frame:

```
┌───────────┬─────────────────┬──────────────────────┐
│ flags(1B) │ timestamp_us(8B)│ NAL data             │
│           │ u64 BE          │ (remaining bytes)    │
└───────────┴─────────────────┴──────────────────────┘
```

Flags: `0x01` = keyframe, `0x02` = codec config (SPS/PPS), `0x80` = stream end.

Maximum frame size: 64 MiB. Frames exceeding this are rejected at the codec level.

### 3.2 Message types

All messages are JSON with a `"type"` discriminator:

**Request** (macOS → iOS):
```json
{
  "type": "request",
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "capability": "navigate",
  "params": { "route": "/detail/42" }
}
```

**Response** (iOS → macOS):
```json
{
  "type": "response",
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "ok",
  "data": { "route": "/detail/42" }
}
```

```json
{
  "type": "response",
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "error",
  "code": "not_found",
  "message": "capability 'foo' not found"
}
```

**Event** (iOS → macOS, unsolicited push):
```json
{
  "type": "event",
  "kind": "state_changed",
  "payload": { "key": "counter", "value": 42 }
}
```

### 3.3 Error codes

| Code | Meaning |
|---|---|
| `not_found` | Capability not registered |
| `invalid_params` | Parameters failed validation |
| `internal` | Handler threw an error |
| `timeout` | Request timed out (client-side) |

### 3.4 Built-in capabilities

These are registered automatically by `RemoServer::new()` — no Swift code required:

| Name | Params | Returns | Description |
|---|---|---|---|
| `__ping` | none | `{"pong": true}` | Connectivity check |
| `__list_capabilities` | none | `["navigate", "state.get", ...]` | Discovery |
| `__view_tree` | `{"max_depth": N}` (optional) | `ViewNode` tree (JSON) | Snapshot the UIView hierarchy |
| `__screenshot` | `{"format": "jpeg"\|"png", "quality": 0.8}` | **BinaryResponse** (type 0x01 frame): raw image bytes. Metadata: `{"format", "width", "height", "scale", "size"}` | Capture the screen |
| `__device_info` | none | `{"name", "model", "system_name", "system_version", "screen_width", "screen_height", "screen_scale"}` | Device model and screen |
| `__app_info` | none | `{"bundle_id", "version", "build", "display_name"}` | App bundle metadata |
| `__start_mirror` | `{"fps": 30, "codec": "h264"}` | `{"stream_id": 1}` | Start screen mirror; frames arrive as Type 0x02 stream frames |
| `__stop_mirror` | `{"stream_id": 1}` | `{}` | Stop mirror session |

---

## 4. Transport layer

### 4.1 Simulator / Wi-Fi

Direct TCP to `<host>:<port>`. Port 0 (auto-assign) is recommended; each app instance gets a unique port advertised via Bonjour. For simulator, `host` is `127.0.0.1`.

### 4.2 USB via usbmuxd

The macOS usbmuxd daemon (`/var/run/usbmuxd`) multiplexes TCP connections over USB.

**Protocol flow:**

1. Connect to Unix domain socket `/var/run/usbmuxd`
2. Send `Listen` plist command → receive device attach/detach events
3. For each device, open a new Unix socket connection
4. Send `Connect` plist command with `DeviceID` + `PortNumber` (big-endian)
5. On success (result code 0), the socket becomes a raw TCP tunnel to the device's port
6. Run the Remo framing protocol over this tunnel

**Message format**: 16-byte header (all fields little-endian u32):

| Offset | Field | Value |
|---|---|---|
| 0 | length | Total message length including header |
| 4 | version | 1 (plist protocol) |
| 8 | msg_type | 8 (plist) |
| 12 | tag | Incrementing request tag |

Payload is XML plist.

### 4.3 Bonjour / mDNS

The `remo-bonjour` crate wraps the Apple dns_sd C API for zero-config networking:

- **iOS (server side)**: The server auto-starts on first API access and registers a Bonjour service of type `_remo._tcp` with the actual bound port. The service is de-advertised on `remo_stop()`.
- **macOS (client side)**: `remo devices` browses for `_remo._tcp` services, resolves hostnames to addresses, and lists discovered simulators/devices alongside USB devices.

Port 0 (auto-assign) is recommended for multi-simulator setups — each simulator gets a unique port, and Bonjour advertises the correct one.

---

## 5. iOS SDK (`remo-sdk`)

### 5.1 Capability registry

A concurrent `DashMap<String, BoxedHandler>` mapping capability names to async or sync handler functions.

```rust
type BoxedHandler = Arc<dyn Fn(Value) -> Pin<Box<dyn Future<Output = HandlerResult> + Send>> + Send + Sync>;
```

Handlers return `Result<serde_json::Value, HandlerError>`.

### 5.2 FFI boundary

The Rust static library exposes 5 C functions:

| Function | Signature | Description |
|---|---|---|
| `remo_start` | `(port: u16)` | Start tokio runtime + TCP server. Idempotent — auto-called by Swift wrapper on first API access. |
| `remo_stop` | `()` | Graceful shutdown |
| `remo_register_capability` | `(name: *const c_char, context: *mut c_void, callback: fn)` | Register a Swift handler |
| `remo_free_string` | `(ptr: *mut c_char)` | Free a Rust-allocated string |
| `remo_list_capabilities` | `() -> *mut c_char` | Return JSON array of names |

**Callback convention**: Swift allocates the return string with `strdup()`. Rust reads it and calls `free()`. The `context` pointer is an `Unmanaged<HandlerBox>.toOpaque()` that Swift retains.

### 5.3 Threading model

- `remo_start()` is idempotent (guarded by `AtomicBool`). The Swift wrapper auto-calls it on first API access via a lazy `static let`. It initializes a global `tokio::runtime::Runtime` (multi-thread) stored in a `OnceLock<Mutex<RemoGlobal>>`.
- The TCP server and all connection handlers run on tokio's thread pool.
- Built-in capabilities that require UIKit access (view tree, screenshot, device info) use `remo_objc::run_on_main_sync()` to dispatch work to the main thread via GCD `dispatch_sync_f`.
- FFI capability callbacks (user-registered) are invoked on a tokio worker thread. For UI mutations, the Swift handler must dispatch to `DispatchQueue.main`.

### 5.4 ObjC bridge (`remo-objc`)

Uses `objc2` + `objc2-ui-kit` to inspect the ObjC runtime directly from Rust.

**Modules**:

| Module | Description |
|---|---|
| `main_thread` | GCD dispatch utility: `run_on_main_sync()` dispatches closures to the main queue via `dispatch_sync_f`. Detects if already on main thread to avoid deadlock. |
| `view_tree` | `snapshot_view_tree()`: Walk the key window's UIView hierarchy and serialize to `ViewNode` JSON (class name, frame, alpha, hidden, tag, accessibility identifier, children). |
| `screenshot` | `capture_screenshot(format, quality)`: Capture the key window using `UIGraphicsBeginImageContextWithOptions` + `drawViewHierarchyInRect:afterScreenUpdates:`. Returns raw JPEG/PNG bytes. |
| `device_info` | `get_device_info()`: Read `UIDevice.currentDevice` properties (name, model, systemVersion) and `UIScreen.mainScreen` properties (bounds, scale). `get_app_info()`: Read `NSBundle.mainBundle` info dictionary (bundleIdentifier, version, build, displayName). |

**Reachable via ObjC runtime** (not yet implemented):
- `performSelector:` on arbitrary ObjC objects
- Read/write UIView layer properties (cornerRadius, borderWidth, backgroundColor)
- Accessibility tree traversal

**Not reachable from ObjC runtime** (must go through FFI callbacks):
- Swift structs, enums, generics
- `@Observable` / `@Published` properties
- SwiftUI `NavigationPath` manipulation
- Any Swift-only type that doesn't bridge to ObjC

---

## 6. macOS desktop (`remo-desktop` + `remo-cli`)

### 6.1 Device manager

Maintains a `DashMap<u32, DeviceHandle>` of discovered devices. Supports three discovery modes:

- **USB**: Connects to usbmuxd, sends `Listen`, processes `Attached`/`Detached` events.
- **Bonjour**: Browses for `_remo._tcp` services, resolves hostnames, and adds discovered simulators/Wi-Fi devices.
- **Direct**: Connect to a known `host:port` (for simulators or Wi-Fi with known IP).

### 6.2 RPC client

Each device connection gets an `RpcClient` instance:

- Sends `Request` messages and matches `Response` by UUID using a `HashMap<MessageId, oneshot::Sender>`.
- Events are forwarded to a `mpsc::Sender<Event>` channel.
- Supports configurable timeout per call (default: 10s).

### 6.3 CLI commands

| Command | Description | Example |
|---|---|---|
| `remo devices` | Auto-discover devices (USB + Bonjour) | `remo devices` |
| `remo dashboard` | Web dashboard with multi-device UI | `remo dashboard --port 8080` |
| `remo call -a <addr> <cap> [params]` | Invoke a capability | `remo call -a 127.0.0.1:51363 navigate '{"route":"/home"}'` |
| `remo list -a <addr>` | List registered capabilities | `remo list -a 127.0.0.1:51363` |
| `remo watch -a <addr>` | Stream events from device | `remo watch -a 127.0.0.1:51363` |
| `remo tree -a <addr>` | Dump view hierarchy | `remo tree -a 127.0.0.1:51363 -m 3` |
| `remo screenshot -a <addr>` | Capture screenshot to file | `remo screenshot -a 127.0.0.1:51363 -o shot.jpg` |
| `remo info -a <addr>` | Show device and app info | `remo info -a 127.0.0.1:51363` |
| `remo mirror -a <addr>` | Live screen mirror | `remo mirror -a 127.0.0.1:51363 --web --port 8090` |

### 6.4 Web dashboard

The `remo dashboard` command starts an axum HTTP/WebSocket server with an embedded single-page web UI.

**Architecture**: The dashboard holds a `DashboardState` with a `DeviceManager` for discovery, an optional `ActiveConnection` for the currently connected device, and broadcast channels for streaming video frames and push events.

**REST endpoints**:

| Endpoint | Method | Description |
|---|---|---|
| `/api/devices` | GET | List all discovered devices (USB + Bonjour) |
| `/api/connect` | POST | Connect to device (`{"id": "usb:15"}` or `{"id": "bonjour:Name"}`) |
| `/api/disconnect` | POST | Disconnect from current device |
| `/api/connection` | GET | Check connection status |
| `/api/info` | GET | Device + app info |
| `/api/capabilities` | GET | List registered capabilities |
| `/api/call` | POST | Invoke a capability (`{"name": "...", "params": {...}}`) |
| `/api/screenshot` | POST | Capture screenshot (returns JPEG bytes) |
| `/api/mirror/start` | POST | Start screen mirror (`{"fps": 30}`) |
| `/api/mirror/stop` | POST | Stop screen mirror |

**WebSocket endpoints**:

| Endpoint | Description |
|---|---|
| `/ws/stream` | Binary stream of video frames (`[flags(1B)][timestamp_us(8B)][nal_data]`) |
| `/ws/events` | JSON push events (device added/removed, connection established/lost, RPC events) |

**Device ID format**: `usb:<numeric_id>` for USB devices, `bonjour:<service_name>` for Bonjour devices.

### 6.5 Video streaming pipeline

Screen mirroring flows through:

1. **iOS**: `RPScreenRecorder` captures `CMSampleBuffer` → VideoToolbox H.264 encoder → Annex-B NAL units
2. **Wire**: NAL units sent as Type 0x02 stream frames (flags + timestamp + data)
3. **Desktop**: `StreamReceiver` collects frames → `Mp4Muxer` wraps in fMP4 (init segment + moof/mdat) → WebSocket binary to browser
4. **Browser**: MSE `MediaSource` API appends fMP4 segments to `<video>` element

---

## 7. Example app (`RemoExample`)

A SwiftUI app demonstrating full SDK integration:

**Pages**: Home (counter + toast + confetti), Items (list with add/delete), Activity Log (real-time log), Settings (accent color picker + debug info).

The example app demonstrates both built-in and custom capabilities. Built-in capabilities (`__view_tree`, `__screenshot`, `__device_info`, `__app_info`) are available automatically. Custom registered capabilities include:

| Capability | Params | Effect |
|---|---|---|
| `counter.increment` | `{"amount": 5}` | Increments counter by amount |
| `counter.reset` | none | Resets counter to 0 |
| `state.get` | `{"key": "counter"}` | Returns the current value |
| `state.set` | `{"key": "counter", "value": 42}` | Mutates the store |
| `items.add` | `{"item": "..."}` | Add item to list |
| `items.remove` | `{"index": 0}` | Remove item by index |
| `items.list` | none | List all items |
| `toast.show` | `{"message": "..."}` | Show a toast overlay |
| `confetti.fire` | none | Trigger confetti animation |
| `accentColor.set` | `{"color": "red"}` | Change app accent color |

---

## 8. Build & integration

### 8.1 macOS CLI

```bash
cargo build -p remo-cli --release
# Binary: target/release/remo
```

### 8.2 iOS static library

```bash
# Fast local development:
./build-ios.sh sim        # arm64 simulator only (debug)
./build-ios.sh device     # arm64 device only (debug)

# Full build:
./build-ios.sh release    # all targets (arm64 device, arm64 sim, x86_64 sim) + universal sim binary
```

Outputs an XCFramework at `swift/RemoSDK.xcframework/`.

### 8.3 SPM distribution

The release CI pipeline (`release.yml`) builds the XCFramework, zips it, and pushes to the [`remo-spm`](https://github.com/yi-jiang-applovin/remo-spm) repo as a binary SPM package. Consumer apps add the dependency:

```swift
.package(url: "https://github.com/yi-jiang-applovin/remo-spm.git", from: "0.2.0")
```

### 8.4 Xcode integration

1. Add the `remo-spm` SPM package dependency (or the local `RemoSwift` package for development).
2. Register custom capabilities via `Remo.register(...)`. The server auto-starts on first API access — no explicit `Remo.start()` needed.
3. Built-in capabilities (view tree, screenshot, device/app info) are available immediately — no registration needed.

### 8.5 Tests

```bash
cargo test --workspace    # Unit tests (codec, registry) + integration test
```

The integration test spins up a `RemoServer` on localhost, connects an `RpcClient`, and verifies:
- `echo` capability round-trip
- `add` capability with params
- `__ping` built-in
- `__list_capabilities` built-in
- Unknown capability returns `not_found`

CI also runs `xcodebuild test` for the Swift package to verify the XCFramework + Swift wrapper compile and link correctly.

---

## 9. Current status & known gaps

### 9.1 What is implemented (v0.2.0)

| Component | Status |
|---|---|
| `remo-protocol` (messages + codec + tests) | Complete |
| `remo-transport` (Connection + Listener) | Complete |
| `remo-usbmuxd` (client, types, Listen, Connect) | Complete |
| `remo-bonjour` (service registration + discovery) | Complete |
| `remo-sdk` (server, registry, built-in capabilities, FFI) | Complete |
| `remo-objc` (view tree, screenshot, device/app info, main-thread dispatch) | Complete |
| `remo-desktop` (device manager w/ USB + Bonjour, RPC client) | Complete |
| `remo-cli` (devices, call, list, watch, tree, screenshot, info) | Complete |
| `RemoSwift` (FFI wrapper, debug-only) | Complete |
| `RemoExample` (demo app w/ 4 tabs, 10+ capabilities) | Complete |
| Integration test | Complete |
| CI/CD pipeline (check, lint, test, build, release) | Complete |
| SPM distribution (`remo-spm` binary package) | Complete |

### 9.2 Resolved TODOs

| ID | Issue | Resolution |
|---|---|---|
| T-001 | `remo_stop()` is a no-op | **Fixed.** Shutdown via broadcast channel. |
| T-002 | USB tunnel not wired to RPC | **Fixed.** `remo-transport` supports `UnixStream` via `IoStream` enum. |
| T-005 | Only view tree implemented in `remo-objc` | **Fixed.** Added screenshot, device info, app info, main-thread dispatch. |
| T-006 | No Bonjour/mDNS discovery | **Fixed.** `remo-bonjour` crate: iOS advertises, macOS browses. |
| T-008 | `staticlib` not in Cargo.toml | **Fixed.** Feature-gated `crate-type = ["staticlib"]` in `remo-sdk`. |
| T-012 | No CI pipeline | **Fixed.** GitHub Actions: check, fmt, clippy, test, iOS build, Swift integration. |

### 9.3 Open TODOs

#### P1 — Needed for full product

| ID | Component | Issue | Detail |
|---|---|---|---|
| T-003 | `remo-transport` | No reconnection logic | If a device disconnects, the client should auto-reconnect with exponential backoff. |
| T-004 | `remo-sdk` | No event push from iOS | The `Event` message type is defined but nothing sends events yet. Need `remo_emit_event()` in FFI. |
| T-007 | `remo-cli` | `devices` command requires usbmuxd | Fails on machines without usbmuxd (Linux CI). Should gracefully handle missing socket. |

#### P2 — Nice to have

| ID | Component | Issue | Detail |
|---|---|---|---|
| T-009 | `remo-desktop` | No macOS GUI | A SwiftUI macOS app with device list, view tree visualizer, and state inspector. |
| T-010 | `remo-sdk` | Capability middleware / hooks | Pre/post hooks on capability invocation (logging, auth, rate limiting). |
| ~~T-011~~ | `remo-protocol` | ~~No binary protocol option~~ | **Fixed.** Binary frame type (0x01) added to wire protocol for raw payloads (screenshots). |
| T-013 | `remo-objc` | No SwiftUI view identity mapping | UIView tree doesn't map well to SwiftUI's declarative hierarchy. |
| T-014 | `remo-sdk` | Thread safety audit for FFI callbacks | `SendPtr` wrapper needs documentation or replacement. |
| T-015 | `remo-protocol` | No versioning / handshake | Client and server don't negotiate protocol version. |
| T-016 | `remo-objc` | View property modification | `__view_set` to modify UIView properties remotely (frame, hidden, alpha, etc.). |

---

## 10. Dependency inventory

### 10.1 Rust (workspace)

| Crate | Version | Used for |
|---|---|---|
| `serde` + `serde_json` | 1.x | Message serialization |
| `tokio` | 1.x (full) | Async runtime, TCP, timers |
| `tokio-util` | 0.7 | `Framed` codec adapter |
| `bytes` | 1.x | Zero-copy buffer management |
| `uuid` | 1.x (v4, serde) | Request ID generation |
| `thiserror` | 2.x | Error derive macros |
| `anyhow` | 1.x | CLI error handling |
| `clap` | 4.x (derive) | CLI argument parsing |
| `plist` | 1.x | usbmuxd plist encoding |
| `tracing` + `tracing-subscriber` | 0.1 / 0.3 | Structured logging |
| `futures` | 0.3 | Stream/Sink utilities |
| `dashmap` | 6.x | Concurrent capability registry |
| `base64` | 0.22 | Base64 encoding for screenshot data |
| `objc2` | 0.6 | ObjC FFI (iOS only) |
| `objc2-foundation` | 0.3 | NSString, NSArray, NSRect, etc. |
| `objc2-ui-kit` | 0.3 | UIView, UIWindow, UIDevice, etc. (optional) |

### 10.2 Swift

| Dependency | Source | Used for |
|---|---|---|
| `CRemo` | Binary target in `RemoSDK.xcframework` | Rust FFI binding |
| `RemoSwift` | Local SPM package (or via `remo-spm` remote) | Swift wrapper API |

### 10.3 Build tools

| Tool | Required | Used for |
|---|---|---|
| Rust stable toolchain | Yes | Compilation |
| Xcode + iOS SDK | Yes (for iOS) | iOS target, Swift compilation |
| `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios` | Yes (for iOS) | Cross-compilation targets |

---

## 11. File manifest

```
remo/
├── Cargo.toml                              # Workspace root
├── Makefile                                # setup, build, check, test, cli, ios, ios-sim, ios-device, fmt, lint
├── README.md                               # Overview + quick start
├── SPEC.md                                 # This document
├── build-ios.sh                            # Build iOS XCFramework (sim/device/debug/release modes)
├── rust-toolchain.toml                     # Pin stable + iOS targets
├── .githooks/
│   └── pre-commit                          # cargo fmt + clippy pre-commit hook
├── .github/
│   └── workflows/
│       ├── ci.yml                          # PR checks: fmt, clippy, test, iOS build, Swift integration
│       └── release.yml                     # Tag-triggered: build XCFramework, push to remo-spm
├── tests/
│   └── integration.rs                      # Full round-trip server + client test
├── crates/
│   ├── remo-protocol/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs                      # Re-exports + DEFAULT_PORT
│   │       ├── message.rs                  # Request, Response, Event, ErrorCode
│   │       └── codec.rs                    # RemoCodec (length-prefix + JSON) + tests
│   ├── remo-transport/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── connection.rs               # Connection: send/recv over framed TCP/Unix
│   │       └── listener.rs                 # Listener: async TCP accept loop
│   ├── remo-usbmuxd/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── types.rs                    # UsbmuxHeader, Device, DeviceAttached, etc.
│   │       └── client.rs                   # UsbmuxClient (Listen, Connect), list_devices()
│   ├── remo-bonjour/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs                      # ServiceRegistration, ServiceBrowser, TxtRecord
│   │       └── ...
│   ├── remo-sdk/
│   │   ├── Cargo.toml                      # features: ios (enables remo-objc/uikit + bonjour)
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── registry.rs                 # CapabilityRegistry (DashMap) + tests
│   │       ├── server.rs                   # RemoServer + register_builtins() + built-in capabilities
│   │       └── ffi.rs                      # C ABI: remo_start, remo_register_capability, etc.
│   ├── remo-objc/
│   │   ├── Cargo.toml                      # features: uikit (optional objc2-ui-kit)
│   │   └── src/
│   │       ├── lib.rs                      # Re-exports all modules
│   │       ├── main_thread.rs              # GCD dispatch: run_on_main_sync()
│   │       ├── view_tree.rs                # ViewNode, snapshot_view_tree()
│   │       ├── screenshot.rs               # capture_screenshot() → JPEG/PNG bytes
│   │       ├── device_info.rs              # get_device_info(), get_app_info()
│   │       ├── screen_capture.rs           # RPScreenRecorder → CMSampleBuffer capture
│   │       └── video_encoder.rs            # VideoToolbox H.264 encoder + AVCC→Annex-B
│   ├── remo-desktop/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── rpc_client.rs               # RpcClient (async call w/ timeout + event stream)
│   │       ├── device_manager.rs           # DeviceManager (USB + Bonjour discovery)
│   │       ├── stream_receiver.rs          # StreamReceiver (broadcast → ordered frames)
│   │       ├── mp4_muxer.rs               # fMP4 muxer (init segment + moof/mdat)
│   │       ├── dashboard/
│   │       │   ├── mod.rs                  # axum HTTP/WS server + REST API
│   │       │   └── dashboard.html          # Single-page web UI (embedded)
│   │       └── web_player/
│   │           ├── mod.rs                  # Standalone web player server
│   │           └── player.html             # MSE video player page
│   └── remo-cli/
│       ├── Cargo.toml
│       └── src/
│           └── main.rs                     # CLI: devices, call, list, watch, tree, screenshot, info
├── swift/
│   ├── RemoSwift/
│   │   ├── Package.swift                   # SPM package
│   │   └── Sources/
│   │       └── RemoSwift/
│   │           ├── include/
│   │           │   └── remo.h              # C header for FFI (manually maintained)
│   │           └── Remo.swift              # Swift wrapper: auto-start + Remo.register()
│   └── RemoSDK.xcframework/               # Built by build-ios.sh (gitignored)
└── examples/ios/
    ├── RemoExample.xcworkspace/
    ├── RemoExample.xcodeproj/
    ├── RemoExample/
    │   └── RemoExampleApp.swift            # App entry point
    └── RemoExamplePackage/
        ├── Package.swift                   # SPM: local path (dev) or remote binary (release)
        ├── Sources/RemoExampleFeature/
        │   └── ContentView.swift           # 4 tabs, 10+ custom capabilities
        └── Tests/
            └── RemoExampleFeatureTests/    # Swift integration tests
```

---

## 12. Milestones

### ~~M1: Simulator loopback~~ Done (v0.1.0)
- Full RPC round-trip on simulator
- CLI: devices, call, list, watch

### ~~M2: Real device over USB~~ Done (v0.1.0)
- usbmuxd tunnel end-to-end
- Generic transport over UnixStream

### ~~M3: Auto-discovery + Multi-simulator~~ Done (v0.2.0)
- Bonjour service registration and browsing
- Auto-assigned ports, multiple simultaneous simulators
- Debug-only SDK (`#if DEBUG`)

### ~~M4: Built-in introspection~~ Done (v0.2.0)
- View tree, screenshot, device info, app info — all auto-registered
- GCD main-thread dispatch for safe UIKit access
- CLI: tree, screenshot, info commands

### ~~M5: CI/CD + SPM distribution~~ Done (v0.2.0)
- GitHub Actions CI (check, fmt, clippy, test, iOS build, Swift integration)
- Automated release pipeline → `remo-spm` binary SPM package

### ~~M6: Video streaming + Web dashboard~~ Done (v0.3.0-dev)
- H.264 screen capture via RPScreenRecorder + VideoToolbox
- StreamFrame wire protocol (Type 0x02)
- fMP4 muxer + MSE web player
- Web dashboard with multi-device discovery, device selector, video streaming, screenshots, capabilities panel
- `remo dashboard` and `remo mirror` CLI commands

### M7: Event streaming (next)
- Implement T-004 (event push FFI + observation tracking)
- `remo watch` receives live state changes

### M8: macOS GUI
- Implement T-009 (desktop app)
- Device list, live view tree, state editor, event log

### M9: Production readiness
- Implement T-003 (reconnection), T-015 (handshake)
- View property modification (T-016)
- Audit T-014 (thread safety)
