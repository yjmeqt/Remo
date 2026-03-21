# Enhanced RemoExample App — Design Spec

**Goal:** Transform the example app from a minimal counter demo into a compelling showcase that instantly demonstrates Remo's power: live connection awareness, real-time event logging, remote-triggered visual effects, and animated list manipulation — all controllable from a terminal.

## Demo story

A developer opens the example app on a simulator, then runs CLI commands from their terminal:

```bash
remo call ui.toast '{"message": "Hello from macOS!"}'     # banner slides down
remo call ui.confetti '{}'                                  # confetti explosion
remo call ui.setAccentColor '{"color": "purple"}'           # entire app recolors
remo call items.add '{"name": "New Item"}'                  # list animates in
remo call counter.increment '{"amount": 10}'                # counter pulses
```

The app's **Activity Log** tab shows each command arriving in real time.

## Architecture

Single-file change: `ContentView.swift`. No new packages or Rust changes.

### State additions to `AppStore`

| Property | Type | Purpose |
|---|---|---|
| `accentColorName` | `String` | Current accent color name (drives `.tint()`) |
| `toastMessage` | `String?` | When non-nil, shows animated toast banner |
| `showConfetti` | `Bool` | Triggers confetti overlay |
| `activityLog` | `[LogEntry]` | Reverse-chronological RPC call log |

### `LogEntry` model

```swift
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let capability: String
    let params: String
    let result: String
}
```

### New capabilities

| Capability | Params | Effect |
|---|---|---|
| `ui.toast` | `{"message": "..."}` | Shows slide-down toast for 3 seconds |
| `ui.confetti` | `{}` | Triggers confetti particle overlay for 2 seconds |
| `ui.setAccentColor` | `{"color": "purple/blue/red/green/orange/pink"}` | Changes app-wide accent tint |
| `items.add` | `{"name": "..."}` | Appends item with animation |
| `items.remove` | `{"name": "..."}` | Removes first matching item with animation |
| `items.clear` | `{}` | Clears all items with animation |

All existing capabilities (`navigate`, `state.get`, `state.set`, `counter.increment`) are preserved.

### Logging wrapper

Every capability call goes through a logging wrapper that appends to `activityLog` before returning the result.

### Tab structure

| Tab | Icon | Content |
|---|---|---|
| Home | `house` | Greeting, counter with pulse animation, connection status badge |
| Items | `list.bullet` | Animated list with add/remove/clear |
| Activity | `waveform` | Live scrolling log of RPC calls |
| Settings | `gear` | Username, debug info (port, capabilities) |

### Overlays (on root ContentView)

- **Toast:** Slide-down banner with message, auto-dismisses after 3s
- **Confetti:** Particle emitter overlay, auto-dismisses after 2s

### Visual polish

- Connection status pill on Home: green dot + "Remo on port XXXX"
- Counter uses `contentTransition(.numericText())` for smooth number changes
- List uses `.animation(.default, value:)` for add/remove
- Accent color drives `.tint()` on the root `TabView`
