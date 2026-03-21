# Remo

**Remote iOS Inspection & Control** — a Lookin-like tool that lets a macOS desktop
communicate with multiple iOS real-devices / simulators over usbmuxd, exposing a
capability-based RPC system backed by ObjC runtime introspection.

## Architecture

```
┌──────────────────────┐          ┌─────────────────────────────────┐
│   macOS Host (CLI)   │          │   iOS Device / Simulator        │
│                      │   TCP    │                                 │
│  remo-host ──────────┼──────────┤── remo-agent                    │
│  remo-transport      │ (usbmuxd │   ├── CapabilityRegistry        │
│  └─ usbmuxd client   │  tunnel) │   ├── handler (builtins)        │
│                      │          │   └── remo-objc (ObjC bridge)   │
└──────────────────────┘          └─────────────────────────────────┘
         │                                      │
         └──── remo-core (shared protocol) ─────┘
```

### Crates

| Crate | Purpose |
|---|---|
| `remo-core` | Wire protocol (MessagePack framing), handshake, shared types |
| `remo-transport` | usbmuxd protocol implementation, device discovery & management |
| `remo-host` | macOS CLI — connect to agents, call capabilities, interactive REPL |
| `remo-agent` | iOS-side TCP server, capability registry, request dispatch |
| `remo-objc` | ObjC runtime bridge — view hierarchy inspection, store manipulation |

### Wire Protocol

Length-prefixed MessagePack frames over TCP:

```
┌──────────────┬──────────┬──────────┬────────────────────────┐
│ frame_len:u32│ msg_id:u32│ type:u8  │ msgpack payload        │
└──────────────┴──────────┴──────────┴────────────────────────┘
```

Message types: `Request (0x01)`, `Response (0x02)`, `Event (0x03)`.

Connection begins with a mutual 8-byte handshake (`REMO` + version u32 LE).

## Quick Start

```bash
# Build everything
cargo build

# Run tests (26 unit + integration tests)
cargo test

# Start a standalone agent (mock iOS app)
cargo run --example standalone_agent -- 9876

# In another terminal — run the demo
cargo run -p remo-host -- demo --addr 127.0.0.1:9876

# Or call individual capabilities
cargo run -p remo-host -- call --addr 127.0.0.1:9876 ui.navigate '{"page":"settings"}'
cargo run -p remo-host -- call --addr 127.0.0.1:9876 store.get '{"key":"user_name"}'
cargo run -p remo-host -- call --addr 127.0.0.1:9876 ui.inspect

# Interactive REPL
cargo run -p remo-host -- repl --addr 127.0.0.1:9876
```

## Built-in Capabilities

| Capability | Description |
|---|---|
| `_ping` | Health check |
| `_list_capabilities` | Enumerate all registered capabilities |
| `ui.navigate` | Navigate to a page (`{"page": "settings"}`) |
| `ui.current_page` | Get the current page name |
| `ui.inspect` | Return the full UIKit view hierarchy as JSON |
| `store.get` | Read a value from the app's data store |
| `store.set` | Write a value to the app's data store |
| `store.list` | List all store entries |
| `runtime.classes` | List ObjC runtime classes |
| `runtime.send_message` | Send an ObjC message to an object by address |

## Registering Custom Capabilities (iOS side)

```rust
use remo_agent::{AgentServer, CapabilityRegistry};
use serde_json::json;

let mut registry = CapabilityRegistry::new();

registry.register("my_app.do_thing", "Custom capability", |params| async move {
    let input = params["input"].as_str().unwrap_or("default");
    // ... your logic here ...
    Ok(json!({ "result": input }))
});

let server = AgentServer::bind("0.0.0.0:9876", registry).await?;
server.run().await?;
```

## iOS Integration

The `remo-agent` crate compiles as a static library (`staticlib`) for iOS targets.
Link it into your Xcode project and call the agent startup from `AppDelegate`:

```swift
// Bridge header exposes: remo_agent_start(port: UInt16)
func application(_ app: UIApplication, didFinishLaunchingWithOptions ...) -> Bool {
    DispatchQueue.global().async {
        remo_agent_start(9876)
    }
    return true
}
```

Cross-compile for iOS:
```bash
rustup target add aarch64-apple-ios
cargo build --target aarch64-apple-ios -p remo-agent --release
```

## usbmuxd Transport

On macOS, `remo-transport` connects to the usbmuxd daemon to discover USB-attached
iOS devices and establish TCP tunnels:

```rust
use remo_transport::UsbmuxdClient;

let mut client = UsbmuxdClient::connect_default().await?;
let devices = client.list_devices().await?;

for dev in &devices {
    println!("{} ({})", dev.serial_number, dev.device_id);
}

// Tunnel to device port 9876
client.connect_to_device(devices[0].device_id, 9876).await?;
let tcp_stream = client.into_inner(); // Now a direct tunnel
```

## License

MIT
