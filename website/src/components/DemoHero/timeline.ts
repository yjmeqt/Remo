export type TerminalLineType = "prompt" | "claude" | "command" | "result";

export interface TerminalLine {
  type: TerminalLineType;
  text: string;
}

export type AccentColorName =
  | "blue"
  | "purple"
  | "red"
  | "green"
  | "orange"
  | "pink"
  | "yellow"
  | "mint"
  | "teal";

export type PhoneRoute = "home" | "uikit" | "activity" | "settings";

export type GridTab = "feed" | "items";

export type ScrollPosition = "top" | "middle" | "bottom";

/**
 * Side-effects a `command` step triggers on the mock phone.
 * Applied with a small delay after the terminal line appears so the UI
 * feels like a real RPC round-trip.
 */
export type PhoneAction =
  | { kind: "toast"; message: string }
  | { kind: "setAccentColor"; color: AccentColorName }
  | { kind: "confetti" }
  | { kind: "navigate"; route: PhoneRoute }
  | { kind: "selectGridTab"; tab: GridTab }
  | { kind: "gridScroll"; position: ScrollPosition }
  | { kind: "feedAppend"; title: string; subtitle: string };

export interface DemoStep {
  time: number;
  terminal: TerminalLine;
  /** If set, the mock phone applies this effect ~`phoneActionDelay` after `time`. */
  phoneAction?: PhoneAction;
}

/** Seconds the phone lags behind the matching command line — feels like an RPC. */
export const PHONE_ACTION_DELAY = 0.45;

/** Seconds before the iPhone screen lights up at the start of the demo. */
export const PHONE_BOOT_TIME = 10;

const V = PHONE_BOOT_TIME;

export const DEMO_STEPS: DemoStep[] = [
  // === CODE PHASE (terminal only, iPhone screen still dark) ===
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
      text: "I see UI effects and a Grid tab with feed and items. I'll declare typed capabilities for each one.",
    },
  },
  {
    time: 6.5,
    terminal: {
      type: "command",
      text: "❯ Edit UIKitDemoViewController.swift — added #Remo { #remoScope { #remoCap(Grid*.self) { … } } }",
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

  // === LIVE APP PHASE (terminal + simulated phone) ===
  // Times are absolute seconds. Phone effect lands at time + PHONE_ACTION_DELAY.

  // -- Toast --
  {
    time: V + 0.0,
    terminal: {
      type: "command",
      text: '❯ remo call ui.toast \'{"message":"Features verified ✓"}\'',
    },
    phoneAction: { kind: "toast", message: "Features verified ✓" },
  },
  {
    time: V + 1.0,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: V + 1.7,
    terminal: {
      type: "claude",
      text: "Toast rendered in the running app. Continuing...",
    },
  },

  // -- Confetti --
  {
    time: V + 2.4,
    terminal: { type: "command", text: "❯ remo call ui.confetti '{}'" },
    phoneAction: { kind: "confetti" },
  },
  {
    time: V + 2.9,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: V + 4.6,
    terminal: {
      type: "claude",
      text: "Confetti animation triggered cleanly.",
    },
  },

  // -- Accent color --
  {
    time: V + 5.3,
    terminal: {
      type: "command",
      text: '❯ remo call ui.setAccentColor \'{"color":"purple"}\'',
    },
    phoneAction: { kind: "setAccentColor", color: "purple" },
  },
  {
    time: V + 5.8,
    terminal: { type: "result", text: '✓ { "color": "purple" }' },
  },
  {
    time: V + 6.7,
    terminal: {
      type: "claude",
      text: "Accent color changed to purple. Checking the Grid tab...",
    },
  },

  // -- Navigate to Grid --
  {
    time: V + 7.4,
    terminal: {
      type: "command",
      text: '❯ remo call navigate \'{"route":"uikit"}\'',
    },
    phoneAction: { kind: "navigate", route: "uikit" },
  },
  {
    time: V + 7.9,
    terminal: { type: "result", text: '✓ { "status": "ok" }' },
  },
  {
    time: V + 8.8,
    terminal: {
      type: "claude",
      text: "Grid tab is visible. Exercising scoped capabilities now.",
    },
  },

  // -- Switch to Items, scroll --
  {
    time: V + 9.5,
    terminal: {
      type: "command",
      text: '❯ remo call grid.tab.select \'{"id":"items"}\'',
    },
    phoneAction: { kind: "selectGridTab", tab: "items" },
  },
  {
    time: V + 9.95,
    terminal: { type: "result", text: '✓ { "selectedTab": { "id": "items" } }' },
  },
  {
    time: V + 10.6,
    terminal: {
      type: "command",
      text: '❯ remo call grid.scroll.vertical \'{"position":"bottom"}\'',
    },
    phoneAction: { kind: "gridScroll", position: "bottom" },
  },
  {
    time: V + 11.05,
    terminal: { type: "result", text: '✓ { "position": "bottom", "tab": "items" }' },
  },
  {
    time: V + 11.95,
    terminal: {
      type: "claude",
      text: "Items tab reached the expected scroll position.",
    },
  },

  // -- Back to Feed, append --
  {
    time: V + 12.6,
    terminal: {
      type: "command",
      text: '❯ remo call grid.tab.select \'{"id":"feed"}\'',
    },
    phoneAction: { kind: "selectGridTab", tab: "feed" },
  },
  {
    time: V + 13.05,
    terminal: { type: "result", text: '✓ { "selectedTab": { "id": "feed" } }' },
  },
  {
    time: V + 13.7,
    terminal: {
      type: "command",
      text: '❯ remo call grid.feed.append \'{"title":"Ship It","subtitle":"Live from Remo"}\'',
    },
    phoneAction: {
      kind: "feedAppend",
      title: "Ship It",
      subtitle: "Live from Remo",
    },
  },
  {
    time: V + 14.15,
    terminal: { type: "result", text: '✓ { "status": "ok", "tab": "feed" }' },
  },
  {
    time: V + 15.0,
    terminal: {
      type: "claude",
      text: "Feed updated with the new entry.",
    },
  },

  // -- Summary --
  {
    time: V + 16.2,
    terminal: {
      type: "claude",
      text: "Capability registration and runtime control are working end to end.",
    },
  },
];

// Last step at V+16.2 = 26.2s, plus ~3s viewing buffer + 2s reset fade.
export const DEMO_TOTAL_DURATION = 31;
