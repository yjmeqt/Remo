# Real E2E-Based Demo

## Goal

Replace the current scripted demo animation with a real recording of the RemoExample app being driven by Remo capabilities, using actual timestamps from the recording as the demo timeline.

## Context

The current demo (`timeline.ts`) is a 44-second hand-crafted animation with made-up timings and placeholder video. The e2e test script (`scripts/e2e-test.sh`) already exercises all RemoExample capabilities with assertions. This design creates a purpose-built recording script that captures both video and timestamps, then uses those artifacts to drive an authentic demo.

## Narrative

The demo tells the story of Claude Code verifying the RemoExample app after making changes. The arc:

1. **Context phase (~5-8s, terminal only):** Claude briefly shows it explored the codebase (reads `ContentView.swift`, notes the features), then says it will register capabilities and verify each feature. The iPhone shows the app idle.

2. **Verify phase (~35-40s, terminal + live video):** Claude invokes capabilities in sequence. The iPhone video shows the real app responding in real-time.

The key narrative detail: these capabilities are ones Claude itself registered in the code after exploring the project — the terminal output shows the agent adding `Remo.register(...)` calls as needed, then invoking them to verify.

## Curated Capability Order

The demo exercises a visually-compelling subset of the full e2e test:

| # | Capability | Agent says | Visual payoff |
|---|-----------|-----------|---------------|
| 1 | `remo devices` | "Let me discover the device..." | — |
| 2 | `remo capabilities` | "Listing registered capabilities..." | — |
| 3 | `counter.increment` x3 | "Testing the counter..." | Number goes 0 -> 1 -> 2 -> 3 |
| 4 | `ui.toast` | "Triggering a toast notification..." | Toast overlay appears |
| 5 | `ui.setAccentColor` | "Changing the accent color..." | App recolors |
| 6 | `ui.confetti` | "Testing confetti effect..." | Particles fly |
| 7 | `navigate("items")` | "Navigating to the items page..." | Tab switches |
| 8 | `items.add` x2 | "Adding items to verify list..." | List grows |
| 9 | `remo screenshot` | "Capturing a screenshot to confirm..." | — |
| 10 | Summary | "All features verified successfully." | — |

Total loop duration: ~45 seconds.

Capabilities deliberately excluded:
- `__ping`, `__device_info`, `__app_info` — internal/boring
- `state.get`, `state.set` — not visual
- `items.remove`, `items.clear` — similar to add, redundant
- `counter.decrement`, `counter.get_count` — counter.increment alone is enough

## Recording Script

### `scripts/record-demo.sh`

A bash script that:

1. Connects to a running RemoExample on a booted simulator (reuses the e2e discovery logic).
2. Starts `remo mirror --save demo.mp4 --fps 30` in background.
3. Runs each curated capability in order, with deliberate pauses (0.5-2s) so UI animations are visible on camera.
4. After each capability call, logs a JSON entry: `{ "capability": "<name>", "params": {...}, "result": {...}, "elapsed_s": <float> }`.
5. Stops the mirror recording.
6. Outputs:
   - `demo.mp4` — the captured video
   - `demo-timestamps.json` — array of timestamped capability invocations

Usage:
```bash
SKIP_BUILD=1 ./scripts/record-demo.sh
# Outputs: /tmp/remo-demo/demo.mp4, /tmp/remo-demo/demo-timestamps.json
```

The script assumes the app is already built and running (use `SKIP_BUILD=1` from the e2e script pattern). It does NOT run assertions — it's purely for capture.

### Pacing

Each capability gets a deliberate sleep after invocation to let the UI animation complete:

- `counter.increment`: 0.5s between each
- `ui.toast`: 1.5s (toast display time)
- `ui.setAccentColor`: 0.8s (color transition)
- `ui.confetti`: 2.0s (particle animation)
- `navigate`: 1.0s (tab switch animation)
- `items.add`: 0.5s between each
- `remo screenshot`: 0.5s

## Website Changes

### `timeline.ts` — Rewrite

Replace the current hand-crafted steps with a timeline generated from real timestamps.

Structure stays the same (`DemoStep[]`), but:
- `time` values come from `demo-timestamps.json` elapsed_s
- `videoTime` values match the elapsed_s (since video starts at recording start)
- `terminal.text` values are hand-crafted agent narrative lines inserted between the real capability invocations
- `treeHighlight` is removed from the type (no capability tree)

The code phase (first ~5-8s) uses `videoTime: 0` (app idle) with terminal-only narrative:
```
0.0s  $ claude "verify the RemoExample app works correctly"
2.0s  Claude: "Let me explore the project structure..."
3.5s  > Read examples/ios/.../ContentView.swift
5.0s  Claude: "I see counter, items, and UI effect features. I'll register capabilities to verify each one."
6.5s  > Edit ContentView.swift — added Remo.register("counter.increment", ...)
7.5s  Claude: "Capabilities registered. Now let me verify the app."
```

Then the verify phase uses real timestamps from the recording for both terminal commands and videoTime.

Note: the `treeHighlight` field is removed from `DemoStep` — there is no capability tree column.

### `CapabilityTree.tsx` — Delete

The capability tree column is removed entirely. The terminal narrative itself shows the agent registering and invoking capabilities, making the tree redundant.

### `IPhoneFrame.tsx` — Enable real video

- Remove `hidden` class from the `<video>` element
- Remove the placeholder content div (gradient + static counter)
- The video `src="/demo.mp4"` already points to the right path

### `ScreenshotGallery.tsx` — Delete

Dead code since the previous session removed its usage from `DemoHero.tsx`.

### `useTimeline.ts` — Clean up

- Remove `screenshots` from the return type and internal logic (no longer used).
- Remove `activeHighlight` / `treeHighlight` logic (no capability tree).

### `DemoHero.tsx` — Update layout

- Remove the CapabilityTree import and center column.
- Change from three-column to two-column layout: iPhone (left) + Terminal (right).
- Keep the fixed `h-[613px]` row height that matches the iPhone.

## Workflow

1. Build and launch RemoExample on simulator (existing e2e setup).
2. Run `scripts/record-demo.sh` to capture video + timestamps.
3. Copy `demo.mp4` to `website/public/demo.mp4`.
4. Use `demo-timestamps.json` to update `timeline.ts` with real timings.
5. Update layout to two-column, enable video, clean up dead code.
6. Verify the demo loop looks correct in the browser.

## Out of Scope

- Automated pipeline from recording to timeline (manual copy + timeline update is fine for now)
- Recording the "code exploration" phase on video (terminal-only narrative)
- Adding new UI components to the website
- Responsive/mobile layout (desktop two-column only for now)
