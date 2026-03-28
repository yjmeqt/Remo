export type TerminalLineType = "prompt" | "claude" | "command" | "result";

export interface TerminalLine {
  type: TerminalLineType;
  text: string;
}

export interface DemoStep {
  time: number;
  terminal: TerminalLine;
  videoTime?: number;
}

// =============================================================================
// Demo Timeline
//
// Two phases:
//   1. Code phase (0–8s): terminal-only, agent explores code and registers
//      capabilities. videoTime stays at 0 (app idle).
//   2. Verify phase (9s+): agent invokes capabilities, video syncs to real
//      recording timestamps.
//
// After running scripts/record-demo.sh, update the verify phase videoTime
// values with the elapsed_s from demo-timestamps.json.
// =============================================================================

export const DEMO_STEPS: DemoStep[] = [
  // === CODE PHASE (terminal only, no video movement) ===
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

  // === VERIFY PHASE (terminal + video) ===
  // videoTime values below are placeholders. Update with real elapsed_s
  // from demo-timestamps.json after running scripts/record-demo.sh.

  // -- Discovery --
  {
    time: 10,
    terminal: { type: "command", text: "❯ remo devices" },
  },
  {
    time: 11,
    terminal: { type: "result", text: "✓ iPhone 17 Pro (Bonjour)" },
  },
  {
    time: 12,
    terminal: {
      type: "claude",
      text: "Device found. Testing the counter...",
    },
  },

  // -- Counter (increment x3) --
  {
    time: 13,
    terminal: {
      type: "command",
      text: "❯ remo call counter.increment '{\"amount\":1}'",
    },
    videoTime: 2.5,
  },
  {
    time: 14,
    terminal: { type: "result", text: '✓ { "amount": 1 }' },
  },
  {
    time: 14.5,
    terminal: {
      type: "command",
      text: "❯ remo call counter.increment '{\"amount\":1}'",
    },
    videoTime: 3.5,
  },
  {
    time: 15.5,
    terminal: { type: "result", text: '✓ { "amount": 2 }' },
  },
  {
    time: 16,
    terminal: {
      type: "command",
      text: "❯ remo call counter.increment '{\"amount\":1}'",
    },
    videoTime: 4.5,
  },
  {
    time: 17,
    terminal: { type: "result", text: '✓ { "amount": 3 }' },
  },
  {
    time: 18,
    terminal: {
      type: "claude",
      text: "Counter works. Testing UI effects...",
    },
  },

  // -- Toast --
  {
    time: 19,
    terminal: {
      type: "command",
      text: '❯ remo call ui.toast \'{"message":"Features verified ✓"}\'',
    },
    videoTime: 5.5,
  },
  {
    time: 20,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },

  // -- Accent Color --
  {
    time: 21.5,
    terminal: {
      type: "command",
      text: '❯ remo call ui.setAccentColor \'{"color":"purple"}\'',
    },
    videoTime: 7.5,
  },
  {
    time: 22.5,
    terminal: { type: "result", text: '✓ { "color": "purple" }' },
  },

  // -- Confetti --
  {
    time: 23.5,
    terminal: { type: "command", text: "❯ remo call ui.confetti '{}'" },
    videoTime: 8.5,
  },
  {
    time: 24.5,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: 26,
    terminal: {
      type: "claude",
      text: "UI effects working. Checking the items page...",
    },
  },

  // -- Navigation --
  {
    time: 27,
    terminal: {
      type: "command",
      text: '❯ remo call navigate \'{"route":"items"}\'',
    },
    videoTime: 11,
  },
  {
    time: 28,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },

  // -- Items --
  {
    time: 29,
    terminal: {
      type: "command",
      text: '❯ remo call items.add \'{"name":"Test Item 1"}\'',
    },
    videoTime: 12.5,
  },
  {
    time: 30,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: 30.5,
    terminal: {
      type: "command",
      text: '❯ remo call items.add \'{"name":"Test Item 2"}\'',
    },
    videoTime: 13.5,
  },
  {
    time: 31.5,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: 32.5,
    terminal: {
      type: "claude",
      text: "Items added. Capturing a screenshot to confirm...",
    },
  },

  // -- Screenshot --
  {
    time: 34,
    terminal: { type: "command", text: "❯ remo screenshot" },
    videoTime: 14.5,
  },
  {
    time: 35.5,
    terminal: {
      type: "result",
      text: "✓ captured 1170×2532 → screenshot_001.png",
    },
  },

  // -- Summary --
  {
    time: 37,
    terminal: {
      type: "claude",
      text: "All features verified successfully. Counter, UI effects, navigation, and items all working correctly.",
    },
  },
];

export const DEMO_TOTAL_DURATION = 40; // seconds before loop restarts
