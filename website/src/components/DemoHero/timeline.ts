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

export const DEMO_STEPS: DemoStep[] = [
  {
    time: 0,
    terminal: { type: "prompt", text: '$ claude "test the counter feature"' },
  },
  {
    time: 2,
    terminal: {
      type: "claude",
      text: "I'll test the counter. Let me discover the device first.",
    },
  },
  {
    time: 4,
    terminal: { type: "command", text: "❯ remo devices" },
  },
  {
    time: 5.5,
    terminal: { type: "result", text: "✓ iPhone 17 Pro (Bonjour)" },
  },
  {
    time: 7,
    terminal: {
      type: "claude",
      text: "Found the device. Listing capabilities...",
    },
  },
  {
    time: 9,
    terminal: { type: "command", text: "❯ remo capabilities" },
  },
  {
    time: 10.5,
    terminal: {
      type: "result",
      text: "counter: increment, decrement, get_count",
    },
  },
  {
    time: 11.5,
    terminal: {
      type: "result",
      text: "items: add_item, delete_item, list_items",
    },
  },
  {
    time: 13,
    terminal: { type: "claude", text: "Invoking increment..." },
  },
  {
    time: 14.5,
    terminal: { type: "command", text: '❯ remo invoke "increment"' },
    videoTime: 3,
  },
  {
    time: 16,
    terminal: { type: "result", text: '✓ { "count": 1 }' },
  },
  {
    time: 17.5,
    terminal: {
      type: "claude",
      text: "Let me increment a few more times to verify...",
    },
  },
  {
    time: 19,
    terminal: { type: "command", text: '❯ remo invoke "increment"' },
    videoTime: 5,
  },
  {
    time: 20,
    terminal: { type: "result", text: '✓ { "count": 2 }' },
  },
  {
    time: 21,
    terminal: { type: "command", text: '❯ remo invoke "increment"' },
    videoTime: 7,
  },
  {
    time: 22,
    terminal: { type: "result", text: '✓ { "count": 3 }' },
  },
  {
    time: 23.5,
    terminal: {
      type: "claude",
      text: "Let me take a screenshot to verify the UI.",
    },
  },
  {
    time: 25,
    terminal: { type: "command", text: "❯ remo screenshot" },
    videoTime: 8,
  },
  {
    time: 27,
    terminal: {
      type: "result",
      text: "✓ captured 1170×2532 → screenshot_001.png",
    },
  },
  {
    time: 28.5,
    terminal: {
      type: "claude",
      text: "Counter shows 3. Let me check the view tree for the label.",
    },
  },
  {
    time: 30,
    terminal: { type: "command", text: "❯ remo view-tree" },
  },
  {
    time: 31.5,
    terminal: {
      type: "result",
      text: '✓ UILabel { text: "3", frame: (187, 400, 40, 48) }',
    },
  },
  {
    time: 33,
    terminal: {
      type: "claude",
      text: "Counter is working correctly. Now let me test reset...",
    },
  },
  {
    time: 35,
    terminal: { type: "command", text: '❯ remo invoke "reset"' },
    videoTime: 11,
  },
  {
    time: 36.5,
    terminal: { type: "result", text: '✓ { "count": 0 }' },
  },
  {
    time: 38,
    terminal: { type: "command", text: "❯ remo screenshot" },
    videoTime: 12,
  },
  {
    time: 39.5,
    terminal: {
      type: "result",
      text: "✓ captured 1170×2532 → screenshot_002.png",
    },
  },
  {
    time: 41,
    terminal: {
      type: "claude",
      text: "All tests pass. Counter increments correctly and reset works.",
    },
  },
];

export const DEMO_TOTAL_DURATION = 44; // seconds before loop restarts
