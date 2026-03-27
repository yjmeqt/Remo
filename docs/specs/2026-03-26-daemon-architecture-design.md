# Remo Daemon Architecture + Capability Change Events

**Date:** 2026-03-26
**Issue:** #13 (capabilities_changed events) + daemon architecture
**Branch:** `feat/capability-change-events`

## Problem

1. **CLI connections are stateless** — each command opens/closes a TCP connection, unable to detect disconnects or receive push events
2. **Dashboard and CLI have different connection models** — dashboard maintains a persistent connection, CLI does not
3. **No async workflow support for agents** — when iOS executes a long-running task, the agent must block waiting for a response
4. **No capability change notifications** — after dynamic register/unregister, clients see a stale capability list

## Solution

### Architecture: daemon middleware layer

Extract the core of `remo-desktop` (device management + persistent connections + event bus) into a standalone `remo-daemon` crate. All clients (CLI, dashboard, AI agents) communicate through the daemon's HTTP API.

```
remo-protocol
remo-transport
remo-bonjour
remo-usbmuxd
    └── remo-daemon (new crate)
            ├── remo-desktop (slim: pure dashboard UI, becomes a daemon client)
            └── remo-cli (prefers daemon API, falls back to direct TCP)
```

## Remo Daemon

### Lifecycle

```
remo start [--port 19630] [-d]    # start daemon (foreground by default, -d for background)
remo stop                          # graceful shutdown
remo status                        # check health + list connected devices
```

- Writes PID + port to `~/.remo/daemon.json`
- Automatically starts Bonjour + USB device discovery on startup

**daemon.json example:**
```json
{
  "pid": 12345,
  "port": 19630,
  "started_at": "2026-03-26T10:00:00Z"
}
```

### ConnectionPool

Maintains a persistent `RpcClient` for each discovered device:

- **Auto-connect:** automatically establishes a connection when a device is discovered
- **Keepalive:** sends `__ping` every 5s; 3 consecutive timeouts (2s each) marks device as disconnected
- **Disconnect detection:** ping timeout or TCP close → marks device `disconnected`, emits `connection_lost` event
- **Auto-reconnect:** if device is still in the discovery list → exponential backoff retry, emits `connection_restored` on success

**Device state machine:**
```
discovered → connecting → connected → disconnected
                ↑                          │
                └──────── (auto-retry) ────┘
```

### HTTP API

#### Device management

```
GET  /devices                    → list discovered devices + connection state
POST /devices/{id}/connect       → manually trigger connection
POST /devices/{id}/disconnect    → disconnect a specific device
```

#### Capability invocation

```
POST /call
{
  "device": "bonjour:RemoExample",   // optional, auto-selects when only one device connected
  "capability": "counter.increment",
  "params": {"amount": 1},
  "mode": "await"                     // "await" | "fire"
}
```

- **`await`:** synchronously waits for iOS response (default timeout 30s, override with `timeout_ms` parameter)
- **`fire`:** immediately returns a `call_id`; iOS response is delivered as a `call_completed` event

**Fire mode response:**
```json
{ "call_id": "uuid-xxx", "status": "accepted" }
```

**Completion event:**
```json
{
  "kind": "call_completed",
  "payload": { "call_id": "uuid-xxx", "status": "ok", "data": { ... } }
}
```

Fire mode implementation: daemon spawns a background task using the existing `RpcClient.call()` to wait for the iOS response, then emits an event when it arrives. No iOS SDK changes required.

#### Event consumption (three modes)

**1. WebSocket subscription**
```
GET /ws/events → real-time push of all events
```

**2. REST polling**
```
GET /events?since=<cursor>&limit=50
→ { "events": [...], "next_cursor": 43 }
```

**3. Webhook callback**
```
POST   /webhooks { "url": "...", "filter": ["call_completed"] }
DELETE /webhooks/{id}
```

#### Other endpoints

```
GET  /status             → daemon health and runtime info
GET  /capabilities       → capability list for current device
POST /screenshot         → capture screenshot
GET  /ws/stream          → video stream WebSocket
```

### EventBus

**Unified event format:**
```json
{
  "seq": 42,
  "timestamp": "2026-03-26T10:05:00Z",
  "kind": "...",
  "device": "bonjour:RemoExample",
  "payload": { ... }
}
```

**Event types:**

| kind | source | description |
|---|---|---|
| `device_discovered` | daemon | new device appeared |
| `device_lost` | daemon | device disappeared |
| `connection_established` | daemon | connection established |
| `connection_lost` | daemon | connection dropped |
| `connection_restored` | daemon | auto-reconnect succeeded |
| `call_completed` | iOS → daemon | async result from fire-mode call |
| `call_failed` | daemon | fire-mode call timed out or failed |
| `capabilities_changed` | iOS → daemon | capability registered/unregistered |
| `app_event` | iOS → daemon | app-defined custom event passthrough |

**Internal architecture:**
```
iOS RpcClient events ──┐
daemon internal events ─┤
                        ▼
                    EventBus
                    ├── seq assignment (AtomicU64)
                    ├── ring buffer (VecDeque, cap=1000)
                    ├── broadcast::Sender → WebSocket subscribers
                    ├── polling: binary search buffer by cursor
                    └── webhook: spawn HTTP POST task per match
```

## iOS SDK Changes (Issue #13)

Emit an `Event` message from `CapabilityRegistry::register` / `unregister` over the current connection:

```json
{
  "type": "event",
  "kind": "capabilities_changed",
  "payload": {
    "action": "registered",
    "name": "counter.increment",
    "capabilities": ["navigate", "state.get", "counter.increment"]
  }
}
```

**Implementation:** the registry holds an `event_sender: Option<broadcast::Sender<Event>>`. The server injects the sender when accepting a connection. On register/unregister, the registry emits the event, and the server writes it to the connection's write half.

## CLI Changes

### New commands

- `remo start [--port 19630] [-d]`
- `remo stop`
- `remo status`

### Fallback logic

All existing commands (`call`, `list`, `screenshot`, etc.):

1. Read `~/.remo/daemon.json`
2. Check if PID is alive
3. Alive → route through daemon HTTP API
4. Not alive → direct TCP connection (existing behavior)

## Dashboard Changes

- No longer directly owns `DeviceManager` or `RpcClient`
- All data fetched via daemon HTTP API / WebSocket
- `remo dashboard` command: auto-starts daemon if not already running

## Error Handling

| Scenario | Daemon behavior |
|---|---|
| iOS app crash | ping timeout → `connection_lost`, enters reconnect loop |
| Simulator restart | Bonjour Lost → `device_lost`; re-discovered → auto-connect |
| USB cable unplugged | usbmuxd Detached → `device_lost` + `connection_lost` |
| Daemon crash | CLI detects stale PID → falls back to direct TCP |
| Port conflict | `remo start` exits with error |
| Buffer overflow | oldest events evicted; polling with expired cursor returns `cursor_expired` + earliest available cursor |
| `/call` without device when multiple connected | returns 400, requires explicit device selection |
