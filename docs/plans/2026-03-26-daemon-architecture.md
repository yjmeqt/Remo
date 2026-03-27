# Remo Daemon Architecture + Capability Change Events — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract a daemon middleware layer from remo-desktop with persistent connections, an event bus, and async call support; emit capability change events from the iOS SDK.

**Architecture:** New `remo-daemon` crate owns device discovery, persistent `RpcClient` connections (with keepalive/reconnect), and an `EventBus` that buffers events for WebSocket subscribers, REST polling, and webhook callbacks. The CLI gains `start`/`stop`/`status` commands and falls back to direct TCP when the daemon isn't running. The dashboard becomes a thin UI client of the daemon. The iOS SDK emits `capabilities_changed` events on register/unregister.

**Tech Stack:** Rust (tokio, axum, dashmap, serde_json), existing remo-protocol/transport/bonjour/usbmuxd crates.

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `crates/remo-daemon/Cargo.toml` | Crate manifest — depends on remo-protocol, remo-transport, remo-bonjour, remo-usbmuxd, remo-desktop (for RpcClient) |
| `crates/remo-daemon/src/lib.rs` | Module declarations + public re-exports |
| `crates/remo-daemon/src/event_bus.rs` | EventBus: ring buffer, seq assignment, broadcast, polling, webhook dispatch |
| `crates/remo-daemon/src/connection_pool.rs` | ConnectionPool: per-device persistent RpcClient, keepalive, reconnect |
| `crates/remo-daemon/src/api.rs` | Axum HTTP API router and handlers |
| `crates/remo-daemon/src/daemon.rs` | Daemon lifecycle: start, shutdown, daemon.json |
| `crates/remo-daemon/src/types.rs` | Shared types: DaemonEvent, DeviceState, CallMode |
| `tests/daemon_integration.rs` | Integration tests for daemon API |

### Modified files

| File | Changes |
|---|---|
| `Cargo.toml` (workspace root) | Add `remo-daemon` to workspace members |
| `crates/remo-sdk/src/registry.rs` | Add `event_sender` field, emit events on register/unregister |
| `crates/remo-sdk/src/server.rs` | Inject event_sender into registry on connection accept |
| `crates/remo-sdk/src/ffi.rs` | Wire event_sender through FFI global state |
| `crates/remo-sdk/src/lib.rs` | Re-export updated types |
| `crates/remo-cli/Cargo.toml` | Add remo-daemon dependency |
| `crates/remo-cli/src/main.rs` | Add start/stop/status commands + daemon fallback logic |
| `crates/remo-desktop/src/dashboard/mod.rs` | Refactor to use daemon API instead of direct DeviceManager/RpcClient |
| `tests/integration.rs` | Add test for capabilities_changed event |

---

## Task 1: Emit `capabilities_changed` events from iOS SDK

**Files:**
- Modify: `crates/remo-sdk/src/registry.rs`
- Modify: `crates/remo-sdk/src/server.rs`
- Modify: `crates/remo-sdk/src/ffi.rs`
- Test: `tests/integration.rs`

### Step 1.1: Write failing test for capabilities_changed event

- [ ] Add test to `tests/integration.rs`:

```rust
#[tokio::test]
async fn capabilities_changed_event_on_register() {
    use remo_protocol::{Event, Message, Request};
    use remo_sdk::{CapabilityRegistry, RemoServer};
    use remo_transport::Connection;
    use serde_json::json;
    use std::time::Duration;

    let registry = CapabilityRegistry::new();
    registry.register_sync("initial", |_| Ok(json!({"ok": true})));

    let server = RemoServer::new(registry.clone(), 0);
    let (port_tx, port_rx) = tokio::sync::oneshot::channel();
    let shutdown = server.shutdown_handle();

    tokio::spawn(async move {
        server.run(Some(port_tx)).await.unwrap();
    });

    let port = port_rx.await.unwrap();
    let addr = format!("127.0.0.1:{}", port).parse().unwrap();
    let mut conn = Connection::connect(addr).await.unwrap();

    // Register a new capability after connection is established
    registry.register_sync("dynamic_cap", |_| Ok(json!({"dynamic": true})));

    // We should receive a capabilities_changed event
    let msg = tokio::time::timeout(Duration::from_secs(2), conn.recv())
        .await
        .expect("should receive event within timeout")
        .expect("should receive message");

    match msg {
        Message::Event(event) => {
            assert_eq!(event.kind, "capabilities_changed");
            let payload = event.payload;
            assert_eq!(payload["action"], "registered");
            assert_eq!(payload["name"], "dynamic_cap");
            let caps = payload["capabilities"].as_array().unwrap();
            assert!(caps.iter().any(|c| c == "dynamic_cap"));
            assert!(caps.iter().any(|c| c == "initial"));
        }
        other => panic!("expected Event, got {:?}", other),
    }

    shutdown.send(()).ok();
}

#[tokio::test]
async fn capabilities_changed_event_on_unregister() {
    use remo_protocol::{Event, Message};
    use remo_sdk::{CapabilityRegistry, RemoServer};
    use remo_transport::Connection;
    use serde_json::json;
    use std::time::Duration;

    let registry = CapabilityRegistry::new();
    registry.register_sync("to_remove", |_| Ok(json!({"ok": true})));

    let server = RemoServer::new(registry.clone(), 0);
    let (port_tx, port_rx) = tokio::sync::oneshot::channel();
    let shutdown = server.shutdown_handle();

    tokio::spawn(async move {
        server.run(Some(port_tx)).await.unwrap();
    });

    let port = port_rx.await.unwrap();
    let addr = format!("127.0.0.1:{}", port).parse().unwrap();
    let mut conn = Connection::connect(addr).await.unwrap();

    // Unregister the capability
    registry.unregister("to_remove");

    let msg = tokio::time::timeout(Duration::from_secs(2), conn.recv())
        .await
        .expect("should receive event within timeout")
        .expect("should receive message");

    match msg {
        Message::Event(event) => {
            assert_eq!(event.kind, "capabilities_changed");
            let payload = event.payload;
            assert_eq!(payload["action"], "unregistered");
            assert_eq!(payload["name"], "to_remove");
            let caps = payload["capabilities"].as_array().unwrap();
            assert!(!caps.iter().any(|c| c == "to_remove"));
        }
        other => panic!("expected Event, got {:?}", other),
    }

    shutdown.send(()).ok();
}
```

- [ ] Run tests to verify they fail:

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/feat-capability-events
cargo test capabilities_changed -- --nocapture
```

Expected: compile error — `CapabilityRegistry` doesn't support event emission yet.

### Step 1.2: Add event_sender to CapabilityRegistry

- [ ] Modify `crates/remo-sdk/src/registry.rs`:

Add a `broadcast::Sender<Event>` to the registry so register/unregister can emit events.

```rust
// Add to imports at top of file:
use remo_protocol::Event;
use tokio::sync::broadcast;
use serde_json::json;

// Replace the CapabilityRegistry struct:
#[derive(Default, Clone)]
pub struct CapabilityRegistry {
    handlers: Arc<DashMap<String, BoxedHandler>>,
    event_tx: Arc<std::sync::Mutex<Option<broadcast::Sender<Event>>>>,
}

// Add method to set event sender:
impl CapabilityRegistry {
    // ... existing methods ...

    /// Set the broadcast sender for capability change events.
    /// Called by the server when a connection is established.
    pub fn set_event_sender(&self, tx: broadcast::Sender<Event>) {
        *self.event_tx.lock().unwrap() = Some(tx);
    }

    fn emit_capabilities_changed(&self, action: &str, name: &str) {
        let guard = self.event_tx.lock().unwrap();
        if let Some(tx) = guard.as_ref() {
            let capabilities: Vec<String> = self.handlers.iter().map(|r| r.key().clone()).collect();
            let event = Event {
                kind: "capabilities_changed".to_string(),
                payload: json!({
                    "action": action,
                    "name": name,
                    "capabilities": capabilities,
                }),
            };
            let _ = tx.send(event);
        }
    }
}
```

- [ ] Add emit calls to `register_sync` (after inserting handler):

```rust
// At end of register_sync, after self.handlers.insert(name, ...):
self.emit_capabilities_changed("registered", &name);
```

- [ ] Add emit calls to `register` (after inserting handler):

```rust
// At end of register, after self.handlers.insert(name, ...):
self.emit_capabilities_changed("registered", &name);
```

- [ ] Add emit calls to `register_sync_raw` (after inserting handler):

```rust
// At end of register_sync_raw, after self.handlers.insert(name, ...):
self.emit_capabilities_changed("registered", &name);
```

- [ ] Add emit call to `unregister` (after removing handler, only if it was present):

```rust
pub fn unregister(&self, name: &str) -> bool {
    let removed = self.handlers.remove(name).is_some();
    if removed {
        self.emit_capabilities_changed("unregistered", name);
    }
    removed
}
```

### Step 1.3: Wire event_sender in the server

- [ ] Modify `crates/remo-sdk/src/server.rs` to create a broadcast channel and forward events to all connected clients.

In the `run` method, after creating the registry, create a broadcast channel and set it on the registry:

```rust
// In RemoServer::run(), before the accept loop:
let (event_tx, _) = broadcast::channel::<remo_protocol::Event>(64);
self.registry.set_event_sender(event_tx.clone());
```

In the per-connection handler, subscribe to the event channel and forward events to the client's write half:

```rust
// Inside the per-connection spawn, after splitting into read/write:
let mut event_rx = event_tx.subscribe();
let event_sender = sender.clone(); // StreamSender or Arc<Mutex<WriteHalf>>

tokio::spawn(async move {
    while let Ok(event) = event_rx.recv().await {
        let msg = Message::Event(event);
        if event_sender.send_message(msg).await.is_err() {
            break;
        }
    }
});
```

### Step 1.4: Run tests and verify they pass

- [ ] Run the capabilities_changed tests:

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/feat-capability-events
cargo test capabilities_changed -- --nocapture
```

Expected: both `capabilities_changed_event_on_register` and `capabilities_changed_event_on_unregister` PASS.

- [ ] Run all existing tests to ensure no regressions:

```bash
cargo test
```

Expected: all tests pass (4 existing + 2 new = 6 total).

### Step 1.5: Commit

- [ ] Commit:

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/feat-capability-events
git add crates/remo-sdk/src/registry.rs crates/remo-sdk/src/server.rs tests/integration.rs
git commit -m "feat: emit capabilities_changed events on register/unregister (#13)"
```

---

## Task 2: Create remo-daemon crate scaffold

**Files:**
- Create: `crates/remo-daemon/Cargo.toml`
- Create: `crates/remo-daemon/src/lib.rs`
- Create: `crates/remo-daemon/src/types.rs`
- Modify: `Cargo.toml` (workspace root)

### Step 2.1: Create crate directory and Cargo.toml

- [ ] Create `crates/remo-daemon/Cargo.toml`:

```toml
[package]
name = "remo-daemon"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
description = "Remo daemon — persistent device connections, event bus, and HTTP API"

[dependencies]
remo-protocol = { path = "../remo-protocol" }
remo-transport = { path = "../remo-transport" }
remo-desktop = { path = "../remo-desktop" }
remo-bonjour = { path = "../remo-bonjour" }
remo-usbmuxd = { path = "../remo-usbmuxd" }

tokio = { workspace = true, features = ["full"] }
axum = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
tracing = { workspace = true }
thiserror = { workspace = true }
uuid = { workspace = true }
dashmap = { workspace = true }
reqwest = { version = "0.12", default-features = false, features = ["json", "rustls-tls"] }
chrono = { version = "0.4", features = ["serde"] }
```

### Step 2.2: Create lib.rs and types.rs

- [ ] Create `crates/remo-daemon/src/lib.rs`:

```rust
pub mod types;
pub mod event_bus;
pub mod connection_pool;
pub mod api;
pub mod daemon;
```

- [ ] Create `crates/remo-daemon/src/types.rs`:

```rust
use chrono::{DateTime, Utc};
use remo_desktop::DeviceId;
use serde::{Deserialize, Serialize};

/// Unified daemon event with sequence number for cursor-based polling.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonEvent {
    pub seq: u64,
    pub timestamp: DateTime<Utc>,
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device: Option<String>,
    pub payload: serde_json::Value,
}

/// Device connection state as tracked by the daemon.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DeviceState {
    Discovered,
    Connecting,
    Connected,
    Disconnected,
}

/// Call mode for /call endpoint.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CallMode {
    Await,
    Fire,
}

impl Default for CallMode {
    fn default() -> Self {
        Self::Await
    }
}

/// Daemon metadata written to ~/.remo/daemon.json.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonInfo {
    pub pid: u32,
    pub port: u16,
    pub started_at: DateTime<Utc>,
}

/// Webhook registration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Webhook {
    pub id: String,
    pub url: String,
    #[serde(default)]
    pub filter: Vec<String>,
}

/// Format a DeviceId as a string for event payloads.
pub fn device_id_to_string(id: &DeviceId) -> String {
    match id {
        DeviceId::Usb(n) => format!("usb:{}", n),
        DeviceId::Bonjour(name) => format!("bonjour:{}", name),
    }
}

/// Parse a device ID string back into a DeviceId.
pub fn parse_device_id(s: &str) -> Option<DeviceId> {
    if let Some(n) = s.strip_prefix("usb:") {
        n.parse().ok().map(DeviceId::Usb)
    } else if let Some(name) = s.strip_prefix("bonjour:") {
        Some(DeviceId::Bonjour(name.to_string()))
    } else {
        None
    }
}
```

### Step 2.3: Add to workspace

- [ ] Add `"crates/remo-daemon"` to the `members` array in workspace root `Cargo.toml`.

### Step 2.4: Verify it compiles

- [ ] Create placeholder modules so lib.rs compiles:

Create `crates/remo-daemon/src/event_bus.rs`:
```rust
// Implemented in Task 3
```

Create `crates/remo-daemon/src/connection_pool.rs`:
```rust
// Implemented in Task 4
```

Create `crates/remo-daemon/src/api.rs`:
```rust
// Implemented in Task 5
```

Create `crates/remo-daemon/src/daemon.rs`:
```rust
// Implemented in Task 6
```

- [ ] Build:

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/feat-capability-events
cargo check -p remo-daemon
```

Expected: compiles with warnings about empty modules.

### Step 2.5: Commit

- [ ] Commit:

```bash
git add Cargo.toml crates/remo-daemon/
git commit -m "feat: scaffold remo-daemon crate with types"
```

---

## Task 3: Implement EventBus

**Files:**
- Modify: `crates/remo-daemon/src/event_bus.rs`
- Test: inline `#[cfg(test)]` module

### Step 3.1: Write failing tests for EventBus

- [ ] Write tests in `crates/remo-daemon/src/event_bus.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn emit_assigns_sequential_ids() {
        let bus = EventBus::new(100);
        bus.emit("test", None, json!({}));
        bus.emit("test", None, json!({}));
        let events = bus.poll(0, 10);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].seq, 1);
        assert_eq!(events[1].seq, 2);
    }

    #[test]
    fn poll_returns_events_after_cursor() {
        let bus = EventBus::new(100);
        bus.emit("a", None, json!({"n": 1}));
        bus.emit("b", None, json!({"n": 2}));
        bus.emit("c", None, json!({"n": 3}));

        let events = bus.poll(1, 10);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].kind, "b");
        assert_eq!(events[1].kind, "c");
    }

    #[test]
    fn ring_buffer_evicts_oldest() {
        let bus = EventBus::new(3);
        bus.emit("a", None, json!({}));
        bus.emit("b", None, json!({}));
        bus.emit("c", None, json!({}));
        bus.emit("d", None, json!({})); // evicts "a"

        let events = bus.poll(0, 10);
        assert_eq!(events.len(), 3);
        assert_eq!(events[0].kind, "b");
    }

    #[test]
    fn poll_with_expired_cursor_returns_all_available() {
        let bus = EventBus::new(2);
        bus.emit("a", None, json!({})); // seq 1
        bus.emit("b", None, json!({})); // seq 2
        bus.emit("c", None, json!({})); // seq 3, evicts "a"

        // cursor 0 is before the earliest available (seq 2)
        let events = bus.poll(0, 10);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].seq, 2);
    }

    #[tokio::test]
    async fn subscribe_receives_new_events() {
        let bus = EventBus::new(100);
        let mut rx = bus.subscribe();

        bus.emit("hello", None, json!({"msg": "world"}));

        let event = rx.recv().await.unwrap();
        assert_eq!(event.kind, "hello");
    }

    #[test]
    fn earliest_cursor_returns_none_when_empty() {
        let bus = EventBus::new(100);
        assert_eq!(bus.earliest_cursor(), None);
    }

    #[test]
    fn earliest_cursor_returns_first_seq() {
        let bus = EventBus::new(100);
        bus.emit("a", None, json!({}));
        bus.emit("b", None, json!({}));
        assert_eq!(bus.earliest_cursor(), Some(1));
    }
}
```

- [ ] Run tests to verify they fail:

```bash
cargo test -p remo-daemon -- --nocapture
```

Expected: compile error — `EventBus` not defined yet.

### Step 3.2: Implement EventBus

- [ ] Write `crates/remo-daemon/src/event_bus.rs`:

```rust
use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

use chrono::Utc;
use serde_json::Value;
use tokio::sync::broadcast;

use crate::types::DaemonEvent;

/// Thread-safe event bus with ring buffer, broadcast, and cursor-based polling.
pub struct EventBus {
    seq: AtomicU64,
    buffer: Mutex<VecDeque<DaemonEvent>>,
    capacity: usize,
    tx: broadcast::Sender<DaemonEvent>,
}

impl EventBus {
    pub fn new(capacity: usize) -> Self {
        let (tx, _) = broadcast::channel(256);
        Self {
            seq: AtomicU64::new(0),
            buffer: Mutex::new(VecDeque::with_capacity(capacity)),
            capacity,
            tx,
        }
    }

    /// Emit a new event. Assigns a monotonic sequence number and timestamp.
    pub fn emit(&self, kind: &str, device: Option<String>, payload: Value) {
        let seq = self.seq.fetch_add(1, Ordering::Relaxed) + 1;
        let event = DaemonEvent {
            seq,
            timestamp: Utc::now(),
            kind: kind.to_string(),
            device,
            payload,
        };

        {
            let mut buf = self.buffer.lock().unwrap();
            if buf.len() >= self.capacity {
                buf.pop_front();
            }
            buf.push_back(event.clone());
        }

        // Ignore send errors (no subscribers)
        let _ = self.tx.send(event);
    }

    /// Poll for events with seq > cursor. Returns up to `limit` events.
    pub fn poll(&self, cursor: u64, limit: usize) -> Vec<DaemonEvent> {
        let buf = self.buffer.lock().unwrap();
        buf.iter()
            .filter(|e| e.seq > cursor)
            .take(limit)
            .cloned()
            .collect()
    }

    /// Subscribe to real-time event stream.
    pub fn subscribe(&self) -> broadcast::Receiver<DaemonEvent> {
        self.tx.subscribe()
    }

    /// Returns the earliest available cursor (lowest seq in buffer), or None if empty.
    pub fn earliest_cursor(&self) -> Option<u64> {
        let buf = self.buffer.lock().unwrap();
        buf.front().map(|e| e.seq)
    }

    /// Returns the latest seq number (0 if no events emitted).
    pub fn latest_seq(&self) -> u64 {
        self.seq.load(Ordering::Relaxed)
    }
}
```

### Step 3.3: Run tests and verify they pass

- [ ] Run EventBus tests:

```bash
cargo test -p remo-daemon event_bus -- --nocapture
```

Expected: all 7 tests pass.

### Step 3.4: Commit

- [ ] Commit:

```bash
git add crates/remo-daemon/src/event_bus.rs
git commit -m "feat(daemon): implement EventBus with ring buffer and broadcast"
```

---

## Task 4: Implement ConnectionPool

**Files:**
- Modify: `crates/remo-daemon/src/connection_pool.rs`
- Test: inline `#[cfg(test)]` module

### Step 4.1: Write failing test for ConnectionPool

- [ ] Write tests in `crates/remo-daemon/src/connection_pool.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use remo_desktop::DeviceId;

    #[test]
    fn device_state_transitions() {
        let pool = ConnectionPool::new();
        let id = DeviceId::Bonjour("test".into());

        // Initially no state
        assert_eq!(pool.get_state(&id), None);

        // After marking discovered
        pool.set_state(id.clone(), DeviceState::Discovered);
        assert_eq!(pool.get_state(&id), Some(DeviceState::Discovered));

        // Transition to connected
        pool.set_state(id.clone(), DeviceState::Connected);
        assert_eq!(pool.get_state(&id), Some(DeviceState::Connected));

        // Remove
        pool.remove(&id);
        assert_eq!(pool.get_state(&id), None);
    }

    #[test]
    fn list_entries() {
        let pool = ConnectionPool::new();
        pool.set_state(DeviceId::Bonjour("a".into()), DeviceState::Connected);
        pool.set_state(DeviceId::Bonjour("b".into()), DeviceState::Discovered);

        let entries = pool.list();
        assert_eq!(entries.len(), 2);
    }
}
```

- [ ] Run to verify failure:

```bash
cargo test -p remo-daemon connection_pool -- --nocapture
```

Expected: compile error — `ConnectionPool` not defined.

### Step 4.2: Implement ConnectionPool

- [ ] Write `crates/remo-daemon/src/connection_pool.rs`:

```rust
use std::sync::Arc;
use std::time::Duration;

use dashmap::DashMap;
use remo_desktop::{DeviceId, DeviceInfo, RpcClient, RpcResponse};
use remo_protocol::Event;
use serde_json::Value;
use tokio::sync::mpsc;
use tokio::time;
use tracing::{info, warn};

use crate::event_bus::EventBus;
use crate::types::{device_id_to_string, DeviceState};

const PING_INTERVAL: Duration = Duration::from_secs(5);
const PING_TIMEOUT: Duration = Duration::from_secs(2);
const MAX_PING_FAILURES: u32 = 3;

struct PoolEntry {
    state: DeviceState,
    client: Option<RpcClient>,
    device_info: Option<DeviceInfo>,
}

/// Manages persistent RpcClient connections with keepalive and reconnect.
pub struct ConnectionPool {
    entries: DashMap<DeviceId, PoolEntry>,
}

impl ConnectionPool {
    pub fn new() -> Self {
        Self {
            entries: DashMap::new(),
        }
    }

    pub fn set_state(&self, id: DeviceId, state: DeviceState) {
        self.entries
            .entry(id)
            .and_modify(|e| e.state = state)
            .or_insert(PoolEntry {
                state,
                client: None,
                device_info: None,
            });
    }

    pub fn get_state(&self, id: &DeviceId) -> Option<DeviceState> {
        self.entries.get(id).map(|e| e.state)
    }

    pub fn remove(&self, id: &DeviceId) {
        self.entries.remove(id);
    }

    pub fn set_client(&self, id: &DeviceId, client: RpcClient) {
        if let Some(mut entry) = self.entries.get_mut(id) {
            entry.client = Some(client);
            entry.state = DeviceState::Connected;
        }
    }

    pub fn set_device_info(&self, id: &DeviceId, info: DeviceInfo) {
        if let Some(mut entry) = self.entries.get_mut(id) {
            entry.device_info = Some(info);
        }
    }

    /// Get a reference to the RpcClient for a device, if connected.
    /// Caller must not hold the ref across await points (DashMap ref guard).
    pub fn get_client(&self, id: &DeviceId) -> Option<dashmap::mapref::one::Ref<'_, DeviceId, PoolEntry>> {
        let entry = self.entries.get(id)?;
        if entry.client.is_some() {
            Some(entry)
        } else {
            None
        }
    }

    /// Call a capability on a connected device.
    pub async fn call(
        &self,
        id: &DeviceId,
        capability: &str,
        params: Value,
        timeout: Duration,
    ) -> Result<RpcResponse, String> {
        // Clone the client out to avoid holding DashMap ref across await
        let client = {
            let entry = self.entries.get(id).ok_or("device not found")?;
            entry.client.as_ref().ok_or("device not connected")?.clone()
        };
        client
            .call(capability, params, timeout)
            .await
            .map_err(|e| e.to_string())
    }

    pub fn list(&self) -> Vec<(DeviceId, DeviceState)> {
        self.entries
            .iter()
            .map(|r| (r.key().clone(), r.state))
            .collect()
    }

    /// Spawn a keepalive task for a connected device.
    /// Returns a JoinHandle that runs until the device disconnects.
    pub fn spawn_keepalive(
        &self,
        id: DeviceId,
        event_bus: Arc<EventBus>,
    ) -> tokio::task::JoinHandle<()> {
        let entries = self.entries.clone();
        let device_str = device_id_to_string(&id);

        tokio::spawn(async move {
            let mut failures: u32 = 0;

            loop {
                time::sleep(PING_INTERVAL).await;

                let client = {
                    let Some(entry) = entries.get(&id) else {
                        break; // device removed
                    };
                    match &entry.client {
                        Some(c) => c.clone(),
                        None => break, // no client
                    }
                };

                let ping_result = time::timeout(
                    PING_TIMEOUT,
                    client.call("__ping", Value::Null, PING_TIMEOUT),
                )
                .await;

                match ping_result {
                    Ok(Ok(_)) => {
                        failures = 0;
                    }
                    _ => {
                        failures += 1;
                        warn!(
                            device = %device_str,
                            failures,
                            "ping failed ({}/{})",
                            failures,
                            MAX_PING_FAILURES
                        );
                        if failures >= MAX_PING_FAILURES {
                            info!(device = %device_str, "marking disconnected after {} ping failures", failures);
                            if let Some(mut entry) = entries.get_mut(&id) {
                                entry.state = DeviceState::Disconnected;
                                entry.client = None;
                            }
                            event_bus.emit(
                                "connection_lost",
                                Some(device_str.clone()),
                                serde_json::json!({"reason": "ping_timeout"}),
                            );
                            break;
                        }
                    }
                }
            }
        })
    }
}
```

### Step 4.3: Run tests and verify they pass

- [ ] Run ConnectionPool tests:

```bash
cargo test -p remo-daemon connection_pool -- --nocapture
```

Expected: 2 tests pass.

### Step 4.4: Commit

- [ ] Commit:

```bash
git add crates/remo-daemon/src/connection_pool.rs
git commit -m "feat(daemon): implement ConnectionPool with keepalive"
```

---

## Task 5: Implement Daemon HTTP API

**Files:**
- Modify: `crates/remo-daemon/src/api.rs`

### Step 5.1: Implement the axum router and handlers

- [ ] Write `crates/remo-daemon/src/api.rs`:

```rust
use std::sync::Arc;
use std::time::Duration;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::{get, post, delete};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::connection_pool::ConnectionPool;
use crate::event_bus::EventBus;
use crate::types::{CallMode, DaemonEvent, Webhook, device_id_to_string, parse_device_id};

/// Shared state for all API handlers.
pub struct ApiState {
    pub pool: Arc<ConnectionPool>,
    pub event_bus: Arc<EventBus>,
    pub webhooks: Arc<std::sync::Mutex<Vec<Webhook>>>,
}

pub fn router(state: Arc<ApiState>) -> Router {
    Router::new()
        .route("/status", get(get_status))
        .route("/devices", get(list_devices))
        .route("/devices/{id}/connect", post(connect_device))
        .route("/devices/{id}/disconnect", post(disconnect_device))
        .route("/call", post(call_capability))
        .route("/capabilities", get(list_capabilities))
        .route("/screenshot", post(take_screenshot))
        .route("/events", get(poll_events))
        .route("/webhooks", post(register_webhook))
        .route("/webhooks/{id}", delete(delete_webhook))
        .route("/ws/events", get(ws_events))
        .with_state(state)
}

// --- Request/Response types ---

#[derive(Deserialize)]
struct CallRequest {
    device: Option<String>,
    capability: String,
    #[serde(default)]
    params: Value,
    #[serde(default)]
    mode: CallMode,
    timeout_ms: Option<u64>,
}

#[derive(Deserialize)]
struct PollQuery {
    since: Option<u64>,
    limit: Option<usize>,
}

#[derive(Deserialize)]
struct WebhookRequest {
    url: String,
    #[serde(default)]
    filter: Vec<String>,
}

#[derive(Serialize)]
struct StatusResponse {
    status: &'static str,
    devices: usize,
    connected: usize,
}

#[derive(Serialize)]
struct PollResponse {
    events: Vec<DaemonEvent>,
    next_cursor: u64,
}

// --- Handlers ---

async fn get_status(State(state): State<Arc<ApiState>>) -> Json<StatusResponse> {
    let entries = state.pool.list();
    let connected = entries
        .iter()
        .filter(|(_, s)| *s == crate::types::DeviceState::Connected)
        .count();
    Json(StatusResponse {
        status: "running",
        devices: entries.len(),
        connected,
    })
}

async fn list_devices(State(state): State<Arc<ApiState>>) -> Json<Value> {
    let entries = state.pool.list();
    let devices: Vec<Value> = entries
        .into_iter()
        .map(|(id, s)| {
            json!({
                "id": device_id_to_string(&id),
                "state": s,
            })
        })
        .collect();
    Json(json!(devices))
}

async fn connect_device(
    State(state): State<Arc<ApiState>>,
    Path(id_str): Path<String>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let _id = parse_device_id(&id_str).ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "invalid device id format"})),
        )
    })?;
    // Connection is handled automatically by the daemon's discovery loop.
    // This endpoint is for manual trigger when auto-connect is disabled.
    Ok(Json(json!({"status": "connect requested", "device": id_str})))
}

async fn disconnect_device(
    State(state): State<Arc<ApiState>>,
    Path(id_str): Path<String>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let id = parse_device_id(&id_str).ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "invalid device id format"})),
        )
    })?;
    state.pool.remove(&id);
    state.event_bus.emit(
        "connection_lost",
        Some(id_str.clone()),
        json!({"reason": "manual_disconnect"}),
    );
    Ok(Json(json!({"status": "disconnected", "device": id_str})))
}

async fn call_capability(
    State(state): State<Arc<ApiState>>,
    Json(req): Json<CallRequest>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let device_id = resolve_device(&state.pool, req.device.as_deref())?;
    let timeout = Duration::from_millis(req.timeout_ms.unwrap_or(30_000));
    let device_str = device_id_to_string(&device_id);

    match req.mode {
        CallMode::Await => {
            let resp = state
                .pool
                .call(&device_id, &req.capability, req.params, timeout)
                .await
                .map_err(|e| {
                    (
                        StatusCode::BAD_GATEWAY,
                        Json(json!({"error": e})),
                    )
                })?;
            match resp {
                remo_desktop::RpcResponse::Json(r) => {
                    Ok(Json(serde_json::to_value(r.result).unwrap_or(json!(null))))
                }
                remo_desktop::RpcResponse::Binary(b) => {
                    Ok(Json(json!({
                        "metadata": b.metadata,
                        "data_len": b.data.len(),
                    })))
                }
            }
        }
        CallMode::Fire => {
            let call_id = Uuid::new_v4().to_string();
            let pool = state.pool.clone();
            let event_bus = state.event_bus.clone();
            let capability = req.capability.clone();
            let params = req.params.clone();
            let cid = call_id.clone();

            tokio::spawn(async move {
                match pool.call(&device_id, &capability, params, timeout).await {
                    Ok(resp) => {
                        let data = match resp {
                            remo_desktop::RpcResponse::Json(r) => {
                                serde_json::to_value(r.result).unwrap_or(json!(null))
                            }
                            remo_desktop::RpcResponse::Binary(b) => {
                                json!({"metadata": b.metadata, "data_len": b.data.len()})
                            }
                        };
                        event_bus.emit(
                            "call_completed",
                            Some(device_str),
                            json!({"call_id": cid, "status": "ok", "data": data}),
                        );
                    }
                    Err(e) => {
                        event_bus.emit(
                            "call_failed",
                            Some(device_str),
                            json!({"call_id": cid, "error": e}),
                        );
                    }
                }
            });

            Ok(Json(json!({"call_id": call_id, "status": "accepted"})))
        }
    }
}

async fn list_capabilities(
    State(state): State<Arc<ApiState>>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let device_id = resolve_device(&state.pool, None)?;
    let timeout = Duration::from_secs(5);
    let resp = state
        .pool
        .call(&device_id, "__list_capabilities", Value::Null, timeout)
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, Json(json!({"error": e}))))?;

    match resp {
        remo_desktop::RpcResponse::Json(r) => {
            Ok(Json(serde_json::to_value(r.result).unwrap_or(json!(null))))
        }
        _ => Ok(Json(json!([]))),
    }
}

async fn take_screenshot(
    State(state): State<Arc<ApiState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let device_id = resolve_device(&state.pool, None)?;
    let timeout = Duration::from_secs(10);
    let resp = state
        .pool
        .call(&device_id, "__screenshot", Value::Null, timeout)
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, Json(json!({"error": e}))))?;

    match resp {
        remo_desktop::RpcResponse::Binary(b) => {
            let content_type = b
                .metadata
                .get("format")
                .and_then(|f| f.as_str())
                .map(|f| match f {
                    "png" => "image/png",
                    _ => "image/jpeg",
                })
                .unwrap_or("image/jpeg");
            Ok((
                StatusCode::OK,
                [(axum::http::header::CONTENT_TYPE, content_type)],
                b.data,
            ))
        }
        _ => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({"error": "unexpected response type"})),
        )),
    }
}

async fn poll_events(
    State(state): State<Arc<ApiState>>,
    Query(q): Query<PollQuery>,
) -> Json<PollResponse> {
    let cursor = q.since.unwrap_or(0);
    let limit = q.limit.unwrap_or(50).min(1000);
    let events = state.event_bus.poll(cursor, limit);
    let next_cursor = events.last().map(|e| e.seq).unwrap_or(cursor);
    Json(PollResponse {
        events,
        next_cursor,
    })
}

async fn register_webhook(
    State(state): State<Arc<ApiState>>,
    Json(req): Json<WebhookRequest>,
) -> Json<Value> {
    let webhook = Webhook {
        id: Uuid::new_v4().to_string(),
        url: req.url,
        filter: req.filter,
    };
    let id = webhook.id.clone();
    state.webhooks.lock().unwrap().push(webhook);
    Json(json!({"webhook_id": id}))
}

async fn delete_webhook(
    State(state): State<Arc<ApiState>>,
    Path(id): Path<String>,
) -> StatusCode {
    let mut hooks = state.webhooks.lock().unwrap();
    let len_before = hooks.len();
    hooks.retain(|w| w.id != id);
    if hooks.len() < len_before {
        StatusCode::NO_CONTENT
    } else {
        StatusCode::NOT_FOUND
    }
}

async fn ws_events(
    State(state): State<Arc<ApiState>>,
    ws: axum::extract::WebSocketUpgrade,
) -> impl IntoResponse {
    let event_bus = state.event_bus.clone();
    ws.on_upgrade(move |mut socket| async move {
        let mut rx = event_bus.subscribe();
        while let Ok(event) = rx.recv().await {
            let json = serde_json::to_string(&event).unwrap_or_default();
            if socket
                .send(axum::extract::ws::Message::Text(json.into()))
                .await
                .is_err()
            {
                break;
            }
        }
    })
}

// --- Helpers ---

/// Resolve which device to target. If explicit, parse it. If None, auto-select
/// the single connected device or error.
fn resolve_device(
    pool: &ConnectionPool,
    device: Option<&str>,
) -> Result<remo_desktop::DeviceId, (StatusCode, Json<Value>)> {
    if let Some(s) = device {
        parse_device_id(s).ok_or_else(|| {
            (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "invalid device id format"})),
            )
        })
    } else {
        let connected: Vec<_> = pool
            .list()
            .into_iter()
            .filter(|(_, s)| *s == crate::types::DeviceState::Connected)
            .collect();
        match connected.len() {
            0 => Err((
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"error": "no device connected"})),
            )),
            1 => Ok(connected.into_iter().next().unwrap().0),
            _ => Err((
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "multiple devices connected, specify 'device' field"})),
            )),
        }
    }
}
```

### Step 5.2: Verify it compiles

- [ ] Build:

```bash
cargo check -p remo-daemon
```

Expected: compiles. Fix any import issues.

### Step 5.3: Commit

- [ ] Commit:

```bash
git add crates/remo-daemon/src/api.rs
git commit -m "feat(daemon): implement HTTP API with device, call, event, and webhook endpoints"
```

---

## Task 6: Implement Daemon lifecycle

**Files:**
- Modify: `crates/remo-daemon/src/daemon.rs`

### Step 6.1: Implement Daemon struct

- [ ] Write `crates/remo-daemon/src/daemon.rs`:

```rust
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;

use remo_desktop::{DeviceId, DeviceManagerEvent};
use remo_protocol::Event;
use serde_json::json;
use tokio::sync::mpsc;
use tracing::{info, warn};

use crate::api::{self, ApiState};
use crate::connection_pool::ConnectionPool;
use crate::event_bus::EventBus;
use crate::types::{DaemonInfo, DeviceState, Webhook, device_id_to_string};

/// The Remo daemon: device discovery, persistent connections, event bus, HTTP API.
pub struct Daemon {
    port: u16,
    pool: Arc<ConnectionPool>,
    event_bus: Arc<EventBus>,
}

impl Daemon {
    pub fn new(port: u16) -> Self {
        Self {
            port,
            pool: Arc::new(ConnectionPool::new()),
            event_bus: Arc::new(EventBus::new(1000)),
        }
    }

    /// Run the daemon. Blocks until shutdown signal is received.
    pub async fn run(self) -> Result<(), Box<dyn std::error::Error>> {
        // Write daemon.json
        let info = DaemonInfo {
            pid: std::process::id(),
            port: self.port,
            started_at: chrono::Utc::now(),
        };
        write_daemon_info(&info)?;

        // Start device discovery
        let (device_manager, mut dm_rx) = remo_desktop::DeviceManager::new();
        device_manager.start_bonjour_discovery()?;
        if let Err(e) = device_manager.start_usb_discovery().await {
            warn!("USB discovery unavailable: {}", e);
        }

        // Spawn device event handler
        let pool = self.pool.clone();
        let event_bus = self.event_bus.clone();
        let dm = Arc::new(device_manager);
        let dm_for_connect = dm.clone();

        tokio::spawn({
            let pool = pool.clone();
            let event_bus = event_bus.clone();
            async move {
                while let Some(event) = dm_rx.recv().await {
                    match event {
                        DeviceManagerEvent::DeviceAdded(info) => {
                            let id_str = device_id_to_string(&info.id);
                            let id = info.id.clone();
                            pool.set_state(info.id.clone(), DeviceState::Discovered);
                            pool.set_device_info(&info.id, info);
                            event_bus.emit(
                                "device_discovered",
                                Some(id_str.clone()),
                                json!({}),
                            );

                            // Auto-connect
                            let pool = pool.clone();
                            let event_bus = event_bus.clone();
                            let dm = dm_for_connect.clone();
                            tokio::spawn(async move {
                                pool.set_state(id.clone(), DeviceState::Connecting);
                                let (event_tx, mut event_rx) = mpsc::channel::<Event>(64);

                                match dm.connect(&id, event_tx).await {
                                    Ok(client) => {
                                        let id_str = device_id_to_string(&id);
                                        pool.set_client(&id, client);
                                        event_bus.emit(
                                            "connection_established",
                                            Some(id_str.clone()),
                                            json!({}),
                                        );

                                        // Forward RPC events to EventBus
                                        let event_bus = event_bus.clone();
                                        tokio::spawn(async move {
                                            while let Some(evt) = event_rx.recv().await {
                                                event_bus.emit(
                                                    &evt.kind,
                                                    Some(id_str.clone()),
                                                    evt.payload,
                                                );
                                            }
                                        });

                                        // Start keepalive
                                        pool.spawn_keepalive(id, event_bus);
                                    }
                                    Err(e) => {
                                        warn!(
                                            device = %device_id_to_string(&id),
                                            "auto-connect failed: {}",
                                            e
                                        );
                                        pool.set_state(id, DeviceState::Disconnected);
                                    }
                                }
                            });
                        }
                        DeviceManagerEvent::DeviceRemoved(id) => {
                            let id_str = device_id_to_string(&id);
                            pool.remove(&id);
                            event_bus.emit("device_lost", Some(id_str), json!({}));
                        }
                    }
                }
            }
        });

        // Start HTTP API
        let api_state = Arc::new(ApiState {
            pool: self.pool.clone(),
            event_bus: self.event_bus.clone(),
            webhooks: Arc::new(std::sync::Mutex::new(Vec::new())),
        });

        let app = api::router(api_state);
        let addr: SocketAddr = ([127, 0, 0, 1], self.port).into();
        let listener = tokio::net::TcpListener::bind(addr).await?;
        let actual_addr = listener.local_addr()?;
        info!("daemon listening on {}", actual_addr);

        // Spawn webhook dispatcher
        let webhooks = Arc::new(std::sync::Mutex::new(Vec::<Webhook>::new()));
        let webhook_bus = self.event_bus.clone();
        let webhooks_ref = webhooks.clone();
        tokio::spawn(async move {
            let mut rx = webhook_bus.subscribe();
            let client = reqwest::Client::new();
            while let Ok(event) = rx.recv().await {
                let hooks = webhooks_ref.lock().unwrap().clone();
                for hook in hooks {
                    if hook.filter.is_empty()
                        || hook.filter.iter().any(|f| f == &event.kind)
                    {
                        let client = client.clone();
                        let url = hook.url.clone();
                        let body = serde_json::to_value(&event).unwrap_or_default();
                        tokio::spawn(async move {
                            let _ = client.post(&url).json(&body).send().await;
                        });
                    }
                }
            }
        });

        // Serve until shutdown
        axum::serve(listener, app)
            .with_graceful_shutdown(async {
                tokio::signal::ctrl_c().await.ok();
                info!("shutting down daemon");
            })
            .await?;

        // Cleanup
        remove_daemon_info();
        Ok(())
    }
}

/// Path to daemon.json.
fn daemon_json_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".remo").join("daemon.json")
}

fn write_daemon_info(info: &DaemonInfo) -> std::io::Result<()> {
    let path = daemon_json_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(info).unwrap();
    std::fs::write(path, json)
}

fn remove_daemon_info() {
    let _ = std::fs::remove_file(daemon_json_path());
}

/// Read daemon info from disk. Returns None if file doesn't exist or is invalid.
pub fn read_daemon_info() -> Option<DaemonInfo> {
    let path = daemon_json_path();
    let contents = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&contents).ok()
}

/// Check if the daemon process is alive by sending a signal 0 to the PID.
pub fn is_daemon_alive(info: &DaemonInfo) -> bool {
    unsafe { libc::kill(info.pid as i32, 0) == 0 }
}
```

### Step 6.2: Add libc dependency

- [ ] Add `libc = "0.2"` to `crates/remo-daemon/Cargo.toml` under `[dependencies]`.

### Step 6.3: Verify it compiles

- [ ] Build:

```bash
cargo check -p remo-daemon
```

Expected: compiles.

### Step 6.4: Commit

- [ ] Commit:

```bash
git add crates/remo-daemon/
git commit -m "feat(daemon): implement Daemon lifecycle with auto-connect and webhook dispatch"
```

---

## Task 7: Add CLI commands for daemon

**Files:**
- Modify: `crates/remo-cli/Cargo.toml`
- Modify: `crates/remo-cli/src/main.rs`

### Step 7.1: Add remo-daemon dependency to CLI

- [ ] Add to `crates/remo-cli/Cargo.toml` under `[dependencies]`:

```toml
remo-daemon = { path = "../remo-daemon" }
reqwest = { version = "0.12", default-features = false, features = ["json", "rustls-tls"] }
```

### Step 7.2: Add start/stop/status CLI commands

- [ ] Add to the `Command` enum in `crates/remo-cli/src/main.rs`:

```rust
/// Start the Remo daemon
Start {
    /// Port to listen on
    #[arg(long, default_value = "19630")]
    port: u16,

    /// Run in background (daemonize)
    #[arg(short = 'd', long)]
    daemon: bool,
},

/// Stop the running Remo daemon
Stop,

/// Show daemon status
Status,
```

- [ ] Add handler functions:

```rust
async fn cmd_start(port: u16, daemonize: bool) -> Result<()> {
    if daemonize {
        // Fork to background using std::process::Command
        let exe = std::env::current_exe()?;
        let child = std::process::Command::new(exe)
            .args(["start", "--port", &port.to_string()])
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()?;
        println!("daemon started (pid: {})", child.id());
        return Ok(());
    }

    let daemon = remo_daemon::Daemon::new(port);
    daemon.run().await.map_err(|e| anyhow::anyhow!("{}", e))
}

async fn cmd_stop() -> Result<()> {
    let info = remo_daemon::read_daemon_info()
        .ok_or_else(|| anyhow::anyhow!("no daemon running (daemon.json not found)"))?;

    if !remo_daemon::is_daemon_alive(&info) {
        remo_daemon::remove_daemon_info_public();
        anyhow::bail!("daemon process {} is not running (stale daemon.json removed)", info.pid);
    }

    // Send SIGTERM
    unsafe { libc::kill(info.pid as i32, libc::SIGTERM) };
    println!("sent shutdown signal to daemon (pid: {})", info.pid);
    Ok(())
}

async fn cmd_status() -> Result<()> {
    match remo_daemon::read_daemon_info() {
        Some(info) if remo_daemon::is_daemon_alive(&info) => {
            println!("daemon running (pid: {}, port: {})", info.pid, info.port);

            // Fetch status from API
            let client = reqwest::Client::new();
            let url = format!("http://127.0.0.1:{}/status", info.port);
            match client.get(&url).send().await {
                Ok(resp) => {
                    let body: serde_json::Value = resp.json().await?;
                    println!(
                        "  devices: {}, connected: {}",
                        body["devices"], body["connected"]
                    );
                }
                Err(e) => println!("  (could not reach API: {})", e),
            }
        }
        Some(info) => {
            println!("daemon not running (stale pid: {})", info.pid);
        }
        None => {
            println!("daemon not running");
        }
    }
    Ok(())
}
```

- [ ] Wire commands in the `match` block in `main()`.

### Step 7.3: Add daemon fallback logic to existing commands

- [ ] Add a helper function that checks for a running daemon and returns an HTTP client + base URL:

```rust
/// Try to get a daemon HTTP client. Returns None if daemon is not running.
fn try_daemon_client() -> Option<(reqwest::Client, String)> {
    let info = remo_daemon::read_daemon_info()?;
    if !remo_daemon::is_daemon_alive(&info) {
        return None;
    }
    Some((
        reqwest::Client::new(),
        format!("http://127.0.0.1:{}", info.port),
    ))
}
```

- [ ] Modify `cmd_call` (the `Call` command handler) to check for daemon first:

```rust
// At the start of the call handler:
if let Some((client, base_url)) = try_daemon_client() {
    let body = serde_json::json!({
        "capability": capability,
        "params": params,
        "mode": "await",
        "timeout_ms": timeout.as_millis() as u64,
    });
    let resp = client
        .post(format!("{}/call", base_url))
        .json(&body)
        .send()
        .await?;
    let result: serde_json::Value = resp.json().await?;
    println!("{}", serde_json::to_string_pretty(&result)?);
    return Ok(());
}
// ... existing direct-connect logic as fallback ...
```

- [ ] Apply the same pattern to `List`, `Screenshot`, `Info` commands.

### Step 7.4: Verify it compiles

- [ ] Build the CLI:

```bash
cargo build -p remo-cli
```

Expected: compiles.

### Step 7.5: Commit

- [ ] Commit:

```bash
git add crates/remo-cli/ crates/remo-daemon/
git commit -m "feat(cli): add start/stop/status commands with daemon fallback"
```

---

## Task 8: Refactor dashboard to use daemon API

**Files:**
- Modify: `crates/remo-desktop/src/dashboard/mod.rs`

### Step 8.1: Add daemon-aware mode to dashboard

The dashboard currently owns its own `DeviceManager` and `RpcClient`. Refactor it so that when a daemon is running, it proxies through the daemon's API instead.

- [ ] Modify `DashboardState` to support two modes — direct (current) and daemon-proxy:

```rust
enum ConnectionMode {
    /// Direct mode: dashboard owns DeviceManager + RpcClient (current behavior)
    Direct {
        device_manager: DeviceManager,
        dm_event_rx: Mutex<mpsc::Receiver<DeviceManagerEvent>>,
        connection: Mutex<Option<ActiveConnection>>,
    },
    /// Proxy mode: all requests forwarded to daemon HTTP API
    Proxy {
        daemon_url: String,
        http_client: reqwest::Client,
    },
}
```

- [ ] Modify `cmd_dashboard` in `crates/remo-cli/src/main.rs` to check if daemon is running:

```rust
async fn cmd_dashboard(port: u16, no_open: bool) -> Result<()> {
    if let Some((_, daemon_url)) = try_daemon_client() {
        // Proxy mode: dashboard UI + proxy to daemon
        info!("daemon detected, running dashboard in proxy mode");
        // Start dashboard with proxy state pointing to daemon_url
        // ...
    } else {
        // Direct mode: start daemon inline + dashboard
        // (existing behavior)
    }
    // ...
}
```

This is a larger refactor. The key principle is: the dashboard HTML/JS stays the same, but the backend handlers either call the local DeviceManager/RpcClient or forward to the daemon's HTTP API.

### Step 8.2: Verify existing dashboard still works

- [ ] Build and run:

```bash
cargo build -p remo-cli
```

Expected: compiles. Dashboard in direct mode unchanged.

### Step 8.3: Commit

- [ ] Commit:

```bash
git add crates/remo-desktop/ crates/remo-cli/
git commit -m "refactor(dashboard): support daemon proxy mode alongside direct mode"
```

---

## Task 9: Daemon integration tests

**Files:**
- Create: `tests/daemon_integration.rs`

### Step 9.1: Write integration test for daemon API

- [ ] Create `tests/daemon_integration.rs`:

```rust
use std::time::Duration;

use remo_daemon::event_bus::EventBus;
use remo_daemon::connection_pool::ConnectionPool;
use remo_daemon::api::{self, ApiState};
use remo_daemon::types::DeviceState;
use remo_desktop::DeviceId;
use serde_json::json;
use std::sync::Arc;

/// Helper to create a test API state.
fn test_state() -> Arc<ApiState> {
    Arc::new(ApiState {
        pool: Arc::new(ConnectionPool::new()),
        event_bus: Arc::new(EventBus::new(100)),
        webhooks: Arc::new(std::sync::Mutex::new(Vec::new())),
    })
}

#[tokio::test]
async fn status_endpoint_returns_running() {
    let state = test_state();
    let app = api::router(state);

    let resp = axum::http::Request::builder()
        .uri("/status")
        .body(axum::body::Body::empty())
        .unwrap();

    let resp = tower::ServiceExt::oneshot(app, resp).await.unwrap();
    assert_eq!(resp.status(), 200);

    let body = axum::body::to_bytes(resp.into_body(), usize::MAX).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["status"], "running");
}

#[tokio::test]
async fn poll_events_returns_emitted_events() {
    let state = test_state();
    state.event_bus.emit("test_event", None, json!({"key": "value"}));
    state.event_bus.emit("test_event_2", None, json!({"key": "value2"}));

    let app = api::router(state);

    let resp = axum::http::Request::builder()
        .uri("/events?since=0&limit=10")
        .body(axum::body::Body::empty())
        .unwrap();

    let resp = tower::ServiceExt::oneshot(app, resp).await.unwrap();
    assert_eq!(resp.status(), 200);

    let body = axum::body::to_bytes(resp.into_body(), usize::MAX).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let events = json["events"].as_array().unwrap();
    assert_eq!(events.len(), 2);
    assert_eq!(events[0]["kind"], "test_event");
    assert_eq!(events[1]["kind"], "test_event_2");
    assert_eq!(json["next_cursor"], 2);
}

#[tokio::test]
async fn call_without_connected_device_returns_503() {
    let state = test_state();
    let app = api::router(state);

    let resp = axum::http::Request::builder()
        .method("POST")
        .uri("/call")
        .header("content-type", "application/json")
        .body(axum::body::Body::from(
            json!({"capability": "test", "params": {}}).to_string(),
        ))
        .unwrap();

    let resp = tower::ServiceExt::oneshot(app, resp).await.unwrap();
    assert_eq!(resp.status(), 503);
}

#[tokio::test]
async fn devices_endpoint_lists_pool_entries() {
    let state = test_state();
    state
        .pool
        .set_state(DeviceId::Bonjour("TestDevice".into()), DeviceState::Connected);

    let app = api::router(state);

    let resp = axum::http::Request::builder()
        .uri("/devices")
        .body(axum::body::Body::empty())
        .unwrap();

    let resp = tower::ServiceExt::oneshot(app, resp).await.unwrap();
    assert_eq!(resp.status(), 200);

    let body = axum::body::to_bytes(resp.into_body(), usize::MAX).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let devices = json.as_array().unwrap();
    assert_eq!(devices.len(), 1);
    assert_eq!(devices[0]["id"], "bonjour:TestDevice");
}
```

### Step 9.2: Run integration tests

- [ ] Run:

```bash
cargo test --test daemon_integration -- --nocapture
```

Expected: all 4 tests pass.

### Step 9.3: Commit

- [ ] Commit:

```bash
git add tests/daemon_integration.rs
git commit -m "test: add daemon API integration tests"
```

---

## Task 10: Update lib.rs exports and final wiring

**Files:**
- Modify: `crates/remo-daemon/src/lib.rs`

### Step 10.1: Clean up public API

- [ ] Update `crates/remo-daemon/src/lib.rs` with proper public exports:

```rust
pub mod types;
pub mod event_bus;
pub mod connection_pool;
pub mod api;
pub mod daemon;

pub use daemon::{Daemon, read_daemon_info, is_daemon_alive};
pub use types::DaemonInfo;
```

### Step 10.2: Add a public function to remove daemon info (for CLI stop command)

- [ ] Add to `crates/remo-daemon/src/daemon.rs`:

```rust
/// Remove daemon.json. Public for CLI stop command cleanup.
pub fn remove_daemon_info_public() {
    remove_daemon_info();
}
```

### Step 10.3: Run all tests

- [ ] Run the full test suite:

```bash
cargo test
```

Expected: all tests pass (existing + new).

### Step 10.4: Commit

- [ ] Commit:

```bash
git add crates/remo-daemon/ crates/remo-cli/ crates/remo-sdk/ tests/
git commit -m "feat: complete daemon architecture with event bus, connection pool, and HTTP API"
```

---

## Summary

| Task | Description | Key files |
|---|---|---|
| 1 | Emit `capabilities_changed` events from SDK | `registry.rs`, `server.rs`, `integration.rs` |
| 2 | Scaffold `remo-daemon` crate | `Cargo.toml`, `lib.rs`, `types.rs` |
| 3 | Implement EventBus | `event_bus.rs` |
| 4 | Implement ConnectionPool | `connection_pool.rs` |
| 5 | Implement HTTP API | `api.rs` |
| 6 | Implement Daemon lifecycle | `daemon.rs` |
| 7 | CLI start/stop/status + fallback | `main.rs` |
| 8 | Dashboard daemon proxy mode | `dashboard/mod.rs` |
| 9 | Integration tests | `daemon_integration.rs` |
| 10 | Final wiring + exports | `lib.rs` |
