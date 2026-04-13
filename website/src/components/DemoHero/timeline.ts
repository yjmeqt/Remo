export type TerminalLineType = "prompt" | "claude" | "command" | "result";

export interface TerminalLine {
  type: TerminalLineType;
  text: string;
}

export interface DemoStep {
  time: number;
  terminal: TerminalLine;
}

// =============================================================================
// Demo Timeline
//
// Two phases:
//   1. Code phase (0 – VIDEO_PHASE_START): terminal-only, agent explores code
//      and registers capabilities. iPhone is blank (videoTime = -1).
//   2. Live app phase (VIDEO_PHASE_START onwards): video plays continuously
//      while terminal commands appear synced to the recording.
//
// The video advances as: videoTime = (elapsed - VIDEO_PHASE_START) + VIDEO_OFFSET
// VIDEO_OFFSET skips the recording startup idle period so the video starts right
// when capabilities fire. Terminal step times = VIDEO_PHASE_START + elapsed_s
// where elapsed_s comes from demo-timestamps.json.
// =============================================================================

/** Terminal time (seconds) when the video appears and starts playing */
export const VIDEO_PHASE_START = 10;

/** Seconds into the video where capabilities start (recording startup delay) */
export const VIDEO_OFFSET = 1;

/**
 * Shorthand for live-app phase step times.
 * V + recording_elapsed_s = terminal time when that step appears,
 * and the video will be at VIDEO_OFFSET + recording_elapsed_s.
 */
const V = VIDEO_PHASE_START;

export const DEMO_STEPS: DemoStep[] = [
  // === CODE PHASE (terminal only, iPhone blank) ===
  {
    time: 0,
    terminal: {
      type: "prompt",
      text: '$ claude "drive the RemoExample app through Remo capabilities"',
    },
  },
  {
    time: 2,
    terminal: {
      type: "claude",
      text: "Let me explore the project structure...",
    },
  },
  {
    time: 3.5,
    terminal: {
      type: "command",
      text: "❯ Read examples/ios/.../ContentView.swift",
    },
  },
  {
    time: 5,
    terminal: {
      type: "claude",
      text: "I see UI effects and a Grid tab with feed and items. I'll register capabilities for each one.",
    },
  },
  {
    time: 6.5,
    terminal: {
      type: "command",
      text: '❯ Edit UIKitDemoViewController.swift — added Remo.register("grid.*", ...)',
    },
  },
  {
    time: 7.5,
    terminal: {
      type: "result",
      text: "✓ Capabilities registered",
    },
  },
  {
    time: 8.5,
    terminal: {
      type: "claude",
      text: "Capabilities registered. Now I'll drive the app.",
    },
  },

  // === LIVE APP PHASE (terminal + continuous video) ===
  // iPhone appears at VIDEO_PHASE_START. Video starts at VIDEO_OFFSET
  // (skipping the idle recording startup period).
  //
  // Recording timestamps (2026-03-28):
  //   ui.toast:               0.02
  //   observation 01:         2.63
  //   ui.setAccentColor:      3.18
  //   observation 02:         4.78
  //   ui.confetti:            5.33
  //   observation 03:         8.42
  //   navigate (uikit):       8.97
  //   observation 04:         10.61
  //   grid.tab.select items:  11.16
  //   grid.scroll.vertical:   12.22
  //   observation 05:         13.28
  //   grid.tab.select feed:   13.83
  //   grid.feed.append:       14.89
  //   observation 06:         15.95

  // -- Toast (recording: 0.02, observation at 2.63) --
  {
    time: V + 0.02,
    terminal: {
      type: "command",
      text: '❯ remo call ui.toast \'{"message":"Features verified ✓"}\'',
    },
  },
  {
    time: V + 4.3,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: V + 6.39,
    terminal: {
      type: "claude",
      text: "Toast rendered in the running app. Continuing...",
    },
  },

  // -- Accent Color (recording: 6.93, observation at 8.53) --
  {
    time: V + 6.93,
    terminal: {
      type: "command",
      text: '❯ remo call ui.setAccentColor \'{"color":"purple"}\'',
    },
  },
  {
    time: V + 7.4,
    terminal: { type: "result", text: '✓ { "color": "purple" }' },
  },
  {
    time: V + 8.53,
    terminal: {
      type: "claude",
      text: "Accent color changed to purple.",
    },
  },

  // -- Confetti (recording: 5.33, observation at 8.42) --
  {
    time: V + 5.33,
    terminal: { type: "command", text: "❯ remo call ui.confetti '{}'" },
  },
  {
    time: V + 5.75,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: V + 8.42,
    terminal: {
      type: "claude",
      text: "Confetti animation triggered cleanly.",
    },
  },
  {
    time: V + 8.7,
    terminal: {
      type: "claude",
      text: "UI effects working. Checking the Grid tab...",
    },
  },

  // -- Navigate to Grid (recording: 8.97, observation at 10.61) --
  {
    time: V + 8.97,
    terminal: {
      type: "command",
      text: '❯ remo call navigate \'{"route":"uikit"}\'',
    },
  },
  {
    time: V + 9.45,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: V + 10.61,
    terminal: {
      type: "claude",
      text: "Grid tab is visible. Exercising scoped capabilities now.",
    },
  },

  // -- Grid capabilities (recording: 11.16 – 15.95) --
  {
    time: V + 11.16,
    terminal: {
      type: "command",
      text: '❯ remo call grid.tab.select \'{"id":"items"}\'',
    },
  },
  {
    time: V + 11.6,
    terminal: { type: "result", text: '✓ { "selectedTab": { "id": "items" } }' },
  },
  {
    time: V + 12.22,
    terminal: {
      type: "command",
      text: '❯ remo call grid.scroll.vertical \'{"position":"bottom"}\'',
    },
  },
  {
    time: V + 12.65,
    terminal: { type: "result", text: '✓ { "position": "bottom", "tab": "items" }' },
  },
  {
    time: V + 13.28,
    terminal: {
      type: "claude",
      text: "Items tab reached the expected scroll position.",
    },
  },
  {
    time: V + 13.83,
    terminal: {
      type: "command",
      text: '❯ remo call grid.tab.select \'{"id":"feed"}\'',
    },
  },
  {
    time: V + 14.25,
    terminal: { type: "result", text: '✓ { "selectedTab": { "id": "feed" } }' },
  },
  {
    time: V + 14.89,
    terminal: {
      type: "command",
      text: '❯ remo call grid.feed.append \'{"title":"Ship It","subtitle":"Live from Remo"}\'',
    },
  },
  {
    time: V + 15.3,
    terminal: { type: "result", text: '✓ { "status": "ok", "tab": "feed" }' },
  },
  {
    time: V + 15.95,
    terminal: {
      type: "claude",
      text: "Feed updated with the new entry.",
    },
  },

  // -- Summary --
  {
    time: V + 17,
    terminal: {
      type: "claude",
      text: "Capability registration and runtime control are working end to end.",
    },
  },
];

// Last step at V+17 = 27s, plus 3s viewing buffer + 2s reset fade
export const DEMO_TOTAL_DURATION = 32;
