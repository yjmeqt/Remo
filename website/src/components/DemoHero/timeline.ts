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
//   2. Verify phase (VIDEO_PHASE_START onwards): video plays continuously
//      while terminal commands appear synced to the recording.
//
// The video advances as: videoTime = (elapsed - VIDEO_PHASE_START) + VIDEO_OFFSET
// VIDEO_OFFSET skips the mirror-init idle period so the video starts right
// when capabilities fire. Terminal step times = VIDEO_PHASE_START + elapsed_s
// where elapsed_s comes from demo-timestamps.json.
// =============================================================================

/** Terminal time (seconds) when the video appears and starts playing */
export const VIDEO_PHASE_START = 10;

/** Seconds into the video where capabilities start (simctl recording delay) */
export const VIDEO_OFFSET = 1;

/**
 * Shorthand for verify-phase step times.
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
      text: '$ claude "verify the RemoExample app works correctly"',
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
      text: "I see counter, items, and UI effect features. I'll register capabilities to verify each one.",
    },
  },
  {
    time: 6.5,
    terminal: {
      type: "command",
      text: '❯ Edit ContentView.swift — added Remo.register("counter.increment", ...)',
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
      text: "Capabilities registered. Now let me verify the app.",
    },
  },

  // === VERIFY PHASE (terminal + continuous video) ===
  // iPhone appears at VIDEO_PHASE_START. Video starts at VIDEO_OFFSET
  // (skipping the idle mirror-init period).
  //
  // Recording timestamps (2026-03-28):
  //   counter.increment: 0.02, 1.07, 2.12
  //   screenshot 01:     3.23
  //   ui.toast:          3.78
  //   screenshot 02:     6.39
  //   ui.setAccentColor: 6.93
  //   screenshot 03:     8.53
  //   ui.confetti:       9.08
  //   screenshot 04:     12.17
  //   navigate:          12.72
  //   screenshot 05:     14.36
  //   items.add #1:      14.92
  //   items.add #2:      15.98
  //   screenshot 06:     17.04

  // -- Counter (recording: 0.02, 1.07, 2.12) --
  {
    time: V + 0.02,
    terminal: {
      type: "command",
      text: "❯ remo call counter.increment '{\"amount\":1}'",
    },
  },
  {
    time: V + 0.5,
    terminal: { type: "result", text: '✓ { "amount": 1 }' },
  },
  {
    time: V + 1.07,
    terminal: {
      type: "command",
      text: "❯ remo call counter.increment '{\"amount\":1}'",
    },
  },
  {
    time: V + 1.5,
    terminal: { type: "result", text: '✓ { "amount": 2 }' },
  },
  {
    time: V + 2.12,
    terminal: {
      type: "command",
      text: "❯ remo call counter.increment '{\"amount\":1}'",
    },
  },
  {
    time: V + 2.6,
    terminal: { type: "result", text: '✓ { "amount": 3 }' },
  },
  {
    time: V + 3.23,
    terminal: { type: "command", text: "❯ remo screenshot" },
  },
  {
    time: V + 3.5,
    terminal: {
      type: "result",
      text: "✓ captured 1170×2532 → counter.png",
    },
  },
  {
    time: V + 3.6,
    terminal: {
      type: "claude",
      text: "Counter works. Testing UI effects...",
    },
  },

  // -- Toast (recording: 3.78, screenshot at 6.39) --
  {
    time: V + 3.78,
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
    terminal: { type: "command", text: "❯ remo screenshot" },
  },
  {
    time: V + 6.6,
    terminal: {
      type: "result",
      text: "✓ captured → toast.png",
    },
  },

  // -- Accent Color (recording: 6.93, screenshot at 8.53) --
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
    terminal: { type: "command", text: "❯ remo screenshot" },
  },
  {
    time: V + 8.7,
    terminal: {
      type: "result",
      text: "✓ captured → accent.png",
    },
  },

  // -- Confetti (recording: 9.08, screenshot at 12.17) --
  {
    time: V + 9.08,
    terminal: { type: "command", text: "❯ remo call ui.confetti '{}'" },
  },
  {
    time: V + 9.5,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: V + 12.17,
    terminal: { type: "command", text: "❯ remo screenshot" },
  },
  {
    time: V + 12.4,
    terminal: {
      type: "result",
      text: "✓ captured → confetti.png",
    },
  },
  {
    time: V + 12.5,
    terminal: {
      type: "claude",
      text: "UI effects working. Checking the items page...",
    },
  },

  // -- Navigation (recording: 12.72, screenshot at 14.36) --
  {
    time: V + 12.72,
    terminal: {
      type: "command",
      text: '❯ remo call navigate \'{"route":"items"}\'',
    },
  },
  {
    time: V + 13.2,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: V + 14.36,
    terminal: { type: "command", text: "❯ remo screenshot" },
  },
  {
    time: V + 14.6,
    terminal: {
      type: "result",
      text: "✓ captured → items-page.png",
    },
  },

  // -- Items (recording: 14.92, 15.98, screenshot at 17.04) --
  {
    time: V + 14.92,
    terminal: {
      type: "command",
      text: '❯ remo call items.add \'{"name":"Test Item 1"}\'',
    },
  },
  {
    time: V + 15.4,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: V + 15.98,
    terminal: {
      type: "command",
      text: '❯ remo call items.add \'{"name":"Test Item 2"}\'',
    },
  },
  {
    time: V + 16.4,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: V + 17.04,
    terminal: { type: "command", text: "❯ remo screenshot" },
  },
  {
    time: V + 17.3,
    terminal: {
      type: "result",
      text: "✓ captured → items-added.png",
    },
  },

  // -- Summary --
  {
    time: V + 18,
    terminal: {
      type: "claude",
      text: "All features verified successfully. Counter, UI effects, navigation, and items all working correctly.",
    },
  },
];

// Last step at V+18 = 28s, plus 3s viewing buffer + 2s reset fade
export const DEMO_TOTAL_DURATION = 33;
