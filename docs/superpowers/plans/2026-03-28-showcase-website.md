# Showcase Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-page showcase website for Remo with a synced three-column demo animation (iPhone + Capability Tree + Claude Code Terminal), a vision section, feature cards, and footer.

**Architecture:** Single-page React app in `website/` directory. A JSON timeline drives the demo: each step types terminal text, highlights a capability tree node, scrubs the iPhone video, and optionally triggers a screenshot fly animation. Framer Motion orchestrates all animations. The page auto-plays on load and loops.

**Tech Stack:** Vite, React 19, TypeScript, Tailwind CSS v4, shadcn/ui, Framer Motion

**Spec:** `docs/superpowers/specs/2026-03-28-showcase-website-design.md`

---

## File Map

### New Files

| File | Responsibility |
|---|---|
| `website/package.json` | Project dependencies and scripts |
| `website/vite.config.ts` | Vite configuration with React plugin |
| `website/tsconfig.json` | TypeScript config |
| `website/tsconfig.app.json` | App-specific TS config |
| `website/tsconfig.node.json` | Node-specific TS config |
| `website/index.html` | HTML entry point |
| `website/tailwind.config.ts` | Tailwind dark theme config |
| `website/src/main.tsx` | React entry point |
| `website/src/index.css` | Tailwind imports + global styles |
| `website/src/App.tsx` | Page layout — assembles all sections |
| `website/src/lib/utils.ts` | shadcn `cn()` utility |
| `website/src/components/ui/card.tsx` | shadcn Card component |
| `website/src/components/ui/button.tsx` | shadcn Button component |
| `website/src/components/Navbar.tsx` | Top navigation bar |
| `website/src/components/DemoHero/timeline.ts` | Demo script data — steps with timestamps, terminal lines, tree highlights, video times |
| `website/src/components/DemoHero/useTimeline.ts` | Custom hook — drives the timeline loop, exposes current step index and elapsed time |
| `website/src/components/DemoHero/DemoHero.tsx` | Three-column container, owns timeline state |
| `website/src/components/DemoHero/IPhoneFrame.tsx` | iPhone 17 frame with video element |
| `website/src/components/DemoHero/CapabilityTree.tsx` | Animated tree view with highlight state |
| `website/src/components/DemoHero/AgentTerminal.tsx` | Typewriter terminal simulation |
| `website/src/components/DemoHero/ScreenshotGallery.tsx` | Thumbnail grid with fly-in animation |
| `website/src/components/VisionSection.tsx` | "How Remo Harnesses iOS Dev" — 3 value props |
| `website/src/components/FeaturesSection.tsx` | 6 capability cards in 2×3 grid |
| `website/src/components/Footer.tsx` | Footer with links and credits |

---

## Task 1: Project Scaffolding

**Files:**
- Create: `website/package.json`, `website/vite.config.ts`, `website/tsconfig.json`, `website/tsconfig.app.json`, `website/tsconfig.node.json`, `website/index.html`, `website/tailwind.config.ts`, `website/src/main.tsx`, `website/src/index.css`, `website/src/App.tsx`, `website/src/lib/utils.ts`

- [ ] **Step 1: Scaffold Vite project**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/showcase-website
npm create vite@latest website -- --template react-ts
```

- [ ] **Step 2: Install dependencies**

```bash
cd website
npm install
npm install -D tailwindcss @tailwindcss/vite
npm install framer-motion class-variance-authority clsx tailwind-merge lucide-react
```

- [ ] **Step 3: Configure Vite with Tailwind**

Replace `website/vite.config.ts`:

```ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": "/src",
    },
  },
});
```

- [ ] **Step 4: Set up Tailwind CSS**

Replace `website/src/index.css`:

```css
@import "tailwindcss";
```

- [ ] **Step 5: Create cn() utility**

Create `website/src/lib/utils.ts`:

```ts
import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

- [ ] **Step 6: Create minimal App.tsx**

Replace `website/src/App.tsx`:

```tsx
function App() {
  return (
    <div className="min-h-screen bg-[#09090b] text-zinc-50">
      <p className="p-8 text-zinc-400">Remo website scaffolding works.</p>
    </div>
  );
}

export default App;
```

- [ ] **Step 7: Clean up main.tsx**

Replace `website/src/main.tsx`:

```tsx
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import App from "./App";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
```

- [ ] **Step 8: Verify dev server starts**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/showcase-website/website
npm run dev
```

Expected: Vite dev server starts, browser shows "Remo website scaffolding works." on a dark background.

- [ ] **Step 9: Commit**

```bash
git add website/
git commit -m "feat(website): scaffold Vite + React + Tailwind project"
```

---

## Task 2: shadcn/ui Components

**Files:**
- Create: `website/src/components/ui/card.tsx`, `website/src/components/ui/button.tsx`

- [ ] **Step 1: Create Card component**

Create `website/src/components/ui/card.tsx`:

```tsx
import * as React from "react";
import { cn } from "@/lib/utils";

const Card = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn(
      "rounded-xl border border-zinc-800 bg-zinc-900 text-zinc-50 shadow",
      className
    )}
    {...props}
  />
));
Card.displayName = "Card";

const CardHeader = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn("flex flex-col space-y-1.5 p-6", className)}
    {...props}
  />
));
CardHeader.displayName = "CardHeader";

const CardTitle = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn("font-semibold leading-none tracking-tight", className)}
    {...props}
  />
));
CardTitle.displayName = "CardTitle";

const CardDescription = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn("text-sm text-zinc-400", className)}
    {...props}
  />
));
CardDescription.displayName = "CardDescription";

const CardContent = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn("p-6 pt-0", className)} {...props} />
));
CardContent.displayName = "CardContent";

export { Card, CardHeader, CardTitle, CardDescription, CardContent };
```

- [ ] **Step 2: Create Button component**

Create `website/src/components/ui/button.tsx`:

```tsx
import * as React from "react";
import { cn } from "@/lib/utils";

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "default" | "outline" | "ghost";
  size?: "default" | "sm" | "lg";
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant = "default", size = "default", ...props }, ref) => {
    return (
      <button
        ref={ref}
        className={cn(
          "inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-zinc-300 disabled:pointer-events-none disabled:opacity-50",
          variant === "default" &&
            "bg-zinc-50 text-zinc-900 shadow hover:bg-zinc-200",
          variant === "outline" &&
            "border border-zinc-800 bg-transparent text-zinc-300 hover:bg-zinc-800 hover:text-zinc-50",
          variant === "ghost" &&
            "text-zinc-400 hover:bg-zinc-800 hover:text-zinc-50",
          size === "default" && "h-9 px-4 py-2",
          size === "sm" && "h-8 rounded-md px-3 text-xs",
          size === "lg" && "h-10 rounded-md px-8",
          className
        )}
        {...props}
      />
    );
  }
);
Button.displayName = "Button";

export { Button };
```

- [ ] **Step 3: Verify components render**

Update `website/src/App.tsx` temporarily:

```tsx
import { Card, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";

function App() {
  return (
    <div className="min-h-screen bg-[#09090b] text-zinc-50 p-8">
      <Card className="max-w-sm">
        <CardHeader>
          <CardTitle>Test Card</CardTitle>
          <CardDescription>shadcn/ui components work.</CardDescription>
        </CardHeader>
      </Card>
      <Button className="mt-4">Default</Button>
      <Button variant="outline" className="mt-4 ml-2">Outline</Button>
    </div>
  );
}

export default App;
```

Expected: Dark card and buttons render correctly.

- [ ] **Step 4: Commit**

```bash
git add website/src/components/ui/
git commit -m "feat(website): add shadcn Card and Button components"
```

---

## Task 3: Navbar

**Files:**
- Create: `website/src/components/Navbar.tsx`

- [ ] **Step 1: Create Navbar component**

Create `website/src/components/Navbar.tsx`:

```tsx
import { Button } from "@/components/ui/button";

export function Navbar() {
  return (
    <nav className="flex items-center justify-between px-6 py-3 border-b border-zinc-800">
      <span className="text-lg font-bold tracking-tight text-zinc-50">
        Remo
      </span>
      <div className="flex items-center gap-4">
        <a
          href="https://github.com/yjmeqt/Remo"
          target="_blank"
          rel="noopener noreferrer"
          className="text-sm text-zinc-400 hover:text-zinc-50 transition-colors"
        >
          GitHub
        </a>
        <Button size="sm">Get Started</Button>
      </div>
    </nav>
  );
}
```

- [ ] **Step 2: Wire into App.tsx**

Replace `website/src/App.tsx`:

```tsx
import { Navbar } from "@/components/Navbar";

function App() {
  return (
    <div className="min-h-screen bg-[#09090b] text-zinc-50">
      <Navbar />
      <p className="p-8 text-zinc-400">Sections will go here.</p>
    </div>
  );
}

export default App;
```

Expected: Navbar renders at top with "Remo" logo, GitHub link, Get Started button.

- [ ] **Step 3: Commit**

```bash
git add website/src/components/Navbar.tsx website/src/App.tsx
git commit -m "feat(website): add Navbar component"
```

---

## Task 4: Timeline Data

**Files:**
- Create: `website/src/components/DemoHero/timeline.ts`

- [ ] **Step 1: Define types and demo script**

Create `website/src/components/DemoHero/timeline.ts`:

```ts
export type TerminalLineType = "prompt" | "claude" | "command" | "result";

export interface TerminalLine {
  type: TerminalLineType;
  text: string;
}

export interface DemoStep {
  time: number;
  terminal: TerminalLine;
  treeHighlight?: string;
  videoTime?: number;
  screenshot?: boolean;
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
    treeHighlight: "device",
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
    treeHighlight: "counter.increment",
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
    treeHighlight: "counter.increment",
    videoTime: 5,
  },
  {
    time: 20,
    terminal: { type: "result", text: '✓ { "count": 2 }' },
  },
  {
    time: 21,
    terminal: { type: "command", text: '❯ remo invoke "increment"' },
    treeHighlight: "counter.increment",
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
    treeHighlight: "device.screenshot",
    videoTime: 8,
    screenshot: true,
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
    treeHighlight: "device.view_tree",
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
    treeHighlight: "settings.reset",
    videoTime: 11,
  },
  {
    time: 36.5,
    terminal: { type: "result", text: '✓ { "count": 0 }' },
  },
  {
    time: 38,
    terminal: { type: "command", text: "❯ remo screenshot" },
    treeHighlight: "device.screenshot",
    videoTime: 12,
    screenshot: true,
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
```

- [ ] **Step 2: Commit**

```bash
git add website/src/components/DemoHero/timeline.ts
git commit -m "feat(website): add demo timeline data"
```

---

## Task 5: useTimeline Hook

**Files:**
- Create: `website/src/components/DemoHero/useTimeline.ts`

- [ ] **Step 1: Create the hook**

Create `website/src/components/DemoHero/useTimeline.ts`:

```ts
import { useState, useEffect, useRef, useCallback } from "react";
import { DEMO_STEPS, DEMO_TOTAL_DURATION } from "./timeline";
import type { DemoStep } from "./timeline";

export interface TimelineState {
  visibleSteps: DemoStep[];
  activeHighlight: string | null;
  screenshots: number[];
  currentVideoTime: number;
  isResetting: boolean;
}

export function useTimeline(): TimelineState {
  const [elapsed, setElapsed] = useState(0);
  const [isResetting, setIsResetting] = useState(false);
  const startTimeRef = useRef(Date.now());
  const frameRef = useRef<number>(0);

  const tick = useCallback(() => {
    const now = Date.now();
    const rawElapsed = (now - startTimeRef.current) / 1000;

    if (rawElapsed >= DEMO_TOTAL_DURATION) {
      setIsResetting(true);
      setTimeout(() => {
        startTimeRef.current = Date.now();
        setElapsed(0);
        setIsResetting(false);
      }, 2000);
      return;
    }

    setElapsed(rawElapsed);
    frameRef.current = requestAnimationFrame(tick);
  }, []);

  useEffect(() => {
    frameRef.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frameRef.current);
  }, [tick]);

  const visibleSteps = DEMO_STEPS.filter((step) => step.time <= elapsed);

  const lastHighlightStep = [...visibleSteps]
    .reverse()
    .find((s) => s.treeHighlight);
  const activeHighlight = lastHighlightStep?.treeHighlight ?? null;
  const highlightAge = lastHighlightStep
    ? elapsed - lastHighlightStep.time
    : Infinity;
  const displayHighlight = highlightAge < 2.5 ? activeHighlight : null;

  const screenshots = visibleSteps
    .filter((s) => s.screenshot)
    .map((_, i) => i);

  const lastVideoStep = [...visibleSteps]
    .reverse()
    .find((s) => s.videoTime !== undefined);
  const currentVideoTime = lastVideoStep?.videoTime ?? 0;

  return {
    visibleSteps,
    activeHighlight: displayHighlight,
    screenshots,
    currentVideoTime,
    isResetting,
  };
}
```

- [ ] **Step 2: Commit**

```bash
git add website/src/components/DemoHero/useTimeline.ts
git commit -m "feat(website): add useTimeline hook"
```

---

## Task 6: IPhoneFrame Component

**Files:**
- Create: `website/src/components/DemoHero/IPhoneFrame.tsx`

- [ ] **Step 1: Create component**

Create `website/src/components/DemoHero/IPhoneFrame.tsx`:

```tsx
import { useRef, useEffect } from "react";

interface IPhoneFrameProps {
  videoTime: number;
}

export function IPhoneFrame({ videoTime }: IPhoneFrameProps) {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    if (videoRef.current && videoRef.current.readyState >= 2) {
      videoRef.current.currentTime = videoTime;
    }
  }, [videoTime]);

  return (
    <div className="flex flex-col items-center rounded-2xl bg-[#0f0f11] border border-zinc-800/50 p-8">
      <div className="relative w-[200px] bg-zinc-800 border-[3px] border-zinc-700 rounded-[32px] p-3 shadow-[0_4px_40px_rgba(0,0,0,0.5),0_0_0_1px_rgba(255,255,255,0.03)]">
        {/* Dynamic Island */}
        <div className="w-[60px] h-[12px] bg-black rounded-lg mx-auto mb-2" />

        {/* Screen */}
        <div className="bg-black rounded-[20px] aspect-[9/19.5] overflow-hidden flex items-center justify-center">
          {/* Placeholder — replaced with real video later */}
          <video
            ref={videoRef}
            className="w-full h-full object-cover hidden"
            src="/demo.mp4"
            muted
            playsInline
          />
          {/* Placeholder content shown until real video is available */}
          <div className="flex flex-col items-center justify-center w-full h-full bg-gradient-to-b from-zinc-900 to-black">
            <div className="text-4xl font-bold text-emerald-400">3</div>
            <div className="text-[10px] text-zinc-500 mt-1">RemoExample</div>
            <div className="flex gap-2 mt-3">
              <span className="bg-zinc-800 text-zinc-300 px-3 py-1 rounded text-[10px]">
                −
              </span>
              <span className="bg-zinc-800 text-zinc-300 px-3 py-1 rounded text-[10px]">
                +
              </span>
            </div>
          </div>
        </div>

        {/* Home indicator */}
        <div className="w-[60px] h-[4px] bg-zinc-700 rounded-full mx-auto mt-2" />
      </div>
      <div className="text-[10px] text-zinc-600 mt-3">▶ Synced app video</div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add website/src/components/DemoHero/IPhoneFrame.tsx
git commit -m "feat(website): add IPhoneFrame component"
```

---

## Task 7: CapabilityTree Component

**Files:**
- Create: `website/src/components/DemoHero/CapabilityTree.tsx`

- [ ] **Step 1: Create component**

Create `website/src/components/DemoHero/CapabilityTree.tsx`:

```tsx
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";

interface CapabilityTreeProps {
  activeHighlight: string | null;
}

interface TreeNode {
  id: string;
  label: string;
  children?: TreeNode[];
}

const TREE: TreeNode[] = [
  {
    id: "device",
    label: "device",
    children: [
      { id: "device.screenshot", label: "screenshot" },
      { id: "device.video_start", label: "video_start" },
      { id: "device.video_stop", label: "video_stop" },
      { id: "device.view_tree", label: "view_tree" },
    ],
  },
  {
    id: "counter",
    label: "counter",
    children: [
      { id: "counter.increment", label: "increment" },
      { id: "counter.decrement", label: "decrement" },
      { id: "counter.get_count", label: "get_count" },
    ],
  },
  {
    id: "items",
    label: "items",
    children: [
      { id: "items.add_item", label: "add_item" },
      { id: "items.delete_item", label: "delete_item" },
      { id: "items.list_items", label: "list_items" },
    ],
  },
  {
    id: "settings",
    label: "settings",
    children: [
      { id: "settings.toggle_flag", label: "toggle_flag" },
      { id: "settings.reset", label: "reset" },
    ],
  },
];

function TreeLeaf({
  node,
  isLast,
  activeHighlight,
}: {
  node: TreeNode;
  isLast: boolean;
  activeHighlight: string | null;
}) {
  const isActive = activeHighlight === node.id;
  const prefix = isLast ? "└─" : "├─";

  return (
    <div className="flex items-center">
      <span className="text-zinc-600">{prefix} </span>
      <motion.span
        className={cn(
          "px-1 rounded",
          isActive
            ? "text-emerald-400 bg-emerald-400/10"
            : "text-zinc-300"
        )}
        animate={
          isActive
            ? {
                boxShadow: [
                  "0 0 0px rgba(52,211,153,0)",
                  "0 0 12px rgba(52,211,153,0.3)",
                  "0 0 0px rgba(52,211,153,0)",
                ],
              }
            : { boxShadow: "0 0 0px rgba(52,211,153,0)" }
        }
        transition={{ duration: 1.2, repeat: isActive ? Infinity : 0 }}
      >
        {node.label}
      </motion.span>
      {isActive && (
        <motion.span
          className="text-amber-400 text-[10px] ml-2"
          initial={{ opacity: 0, x: -4 }}
          animate={{ opacity: 1, x: 0 }}
        >
          ← active
        </motion.span>
      )}
    </div>
  );
}

function TreeGroup({
  node,
  isLast,
  activeHighlight,
}: {
  node: TreeNode;
  isLast: boolean;
  activeHighlight: string | null;
}) {
  const prefix = isLast ? "└─" : "├─";
  const isGroupActive =
    activeHighlight !== null && activeHighlight.startsWith(node.id);

  return (
    <div>
      <div className="flex items-center">
        <span className="text-zinc-600">{prefix} </span>
        <span
          className={cn(
            "font-medium",
            isGroupActive ? "text-zinc-50" : "text-zinc-300"
          )}
        >
          {node.label}
        </span>
      </div>
      {node.children && (
        <div className="pl-4">
          {node.children.map((child, i) => (
            <TreeLeaf
              key={child.id}
              node={child}
              isLast={i === node.children!.length - 1}
              activeHighlight={activeHighlight}
            />
          ))}
        </div>
      )}
    </div>
  );
}

export function CapabilityTree({ activeHighlight }: CapabilityTreeProps) {
  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-4 min-h-full">
      <div className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500 mb-3">
        Capability Tree
      </div>
      <div className="font-mono text-[11px] leading-relaxed">
        <div className="text-violet-400 mb-1">📱 RemoExample</div>
        <div className="pl-3">
          {TREE.map((group, i) => (
            <TreeGroup
              key={group.id}
              node={group}
              isLast={i === TREE.length - 1}
              activeHighlight={activeHighlight}
            />
          ))}
        </div>
      </div>
      <div className="mt-4 pt-3 border-t border-zinc-800 text-[9px] text-zinc-600 text-center">
        Nodes highlight as agent invokes
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add website/src/components/DemoHero/CapabilityTree.tsx
git commit -m "feat(website): add CapabilityTree component"
```

---

## Task 8: AgentTerminal Component

**Files:**
- Create: `website/src/components/DemoHero/AgentTerminal.tsx`

- [ ] **Step 1: Create component**

Create `website/src/components/DemoHero/AgentTerminal.tsx`:

```tsx
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import type { DemoStep } from "./timeline";

interface AgentTerminalProps {
  visibleSteps: DemoStep[];
  isResetting: boolean;
}

function TerminalLine({ step }: { step: DemoStep }) {
  const { type, text } = step.terminal;

  const colorClass = {
    prompt: "text-zinc-300",
    claude: "text-zinc-500",
    command: "text-zinc-300",
    result: "text-emerald-400",
  }[type];

  const isCommand = type === "command";
  const isClaude = type === "claude";

  return (
    <motion.div
      initial={{ opacity: 0, y: 4 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3 }}
      className={cn(
        isCommand &&
          "bg-[#09090b] border border-zinc-800 rounded-md px-2 py-1.5 my-1",
        !isCommand && "my-0.5"
      )}
    >
      {isClaude && (
        <span className="text-violet-400 mr-1.5">Claude</span>
      )}
      <span className={colorClass}>{text}</span>
    </motion.div>
  );
}

export function AgentTerminal({
  visibleSteps,
  isResetting,
}: AgentTerminalProps) {
  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-xl overflow-hidden min-h-full flex flex-col">
      {/* Title bar */}
      <div className="flex items-center gap-1.5 px-3 py-2 bg-zinc-900/80 border-b border-zinc-800">
        <span className="w-2.5 h-2.5 rounded-full bg-red-500" />
        <span className="w-2.5 h-2.5 rounded-full bg-yellow-500" />
        <span className="w-2.5 h-2.5 rounded-full bg-green-500" />
        <span className="text-[11px] text-zinc-500 ml-2">Claude Code</span>
      </div>

      {/* Terminal content */}
      <div className="flex-1 p-4 font-mono text-[11px] leading-relaxed overflow-y-auto">
        <motion.div
          animate={{ opacity: isResetting ? 0 : 1 }}
          transition={{ duration: 0.5 }}
        >
          {visibleSteps.map((step, i) => (
            <TerminalLine key={`${step.time}-${i}`} step={step} />
          ))}
        </motion.div>
        {!isResetting && (
          <div className="text-zinc-600 mt-1">
            █ <span className="animate-pulse">_</span>
          </div>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add website/src/components/DemoHero/AgentTerminal.tsx
git commit -m "feat(website): add AgentTerminal component"
```

---

## Task 9: ScreenshotGallery Component

**Files:**
- Create: `website/src/components/DemoHero/ScreenshotGallery.tsx`

- [ ] **Step 1: Create component**

Create `website/src/components/DemoHero/ScreenshotGallery.tsx`:

```tsx
import { motion, AnimatePresence } from "framer-motion";

interface ScreenshotGalleryProps {
  screenshots: number[];
  isResetting: boolean;
}

const SCREENSHOT_LABELS = ["screenshot_001", "screenshot_002", "screenshot_003"];

export function ScreenshotGallery({
  screenshots,
  isResetting,
}: ScreenshotGalleryProps) {
  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-3">
      <div className="text-[9px] font-semibold uppercase tracking-wider text-zinc-500 mb-2">
        Captured
      </div>
      <div className="grid grid-cols-3 gap-2">
        <AnimatePresence mode="popLayout">
          {!isResetting &&
            screenshots.map((idx) => (
              <motion.div
                key={idx}
                layoutId={`screenshot-${idx}`}
                initial={{ opacity: 0, scale: 0.5, y: -60 }}
                animate={{ opacity: 1, scale: 1, y: 0 }}
                exit={{ opacity: 0, scale: 0.8 }}
                transition={{ type: "spring", stiffness: 300, damping: 25 }}
                className="h-14 bg-[#09090b] border border-emerald-500/30 rounded flex items-center justify-center shadow-[0_0_8px_rgba(52,211,153,0.1)]"
              >
                <span className="text-emerald-400 text-[9px]">
                  {SCREENSHOT_LABELS[idx] ?? `screenshot_${idx + 1}`}
                </span>
              </motion.div>
            ))}
        </AnimatePresence>
        {/* Empty slots */}
        {Array.from({ length: Math.max(0, 3 - screenshots.length) }).map(
          (_, i) => (
            <div
              key={`empty-${i}`}
              className="h-14 bg-[#09090b] border border-dashed border-zinc-800 rounded flex items-center justify-center"
            >
              <span className="text-zinc-700 text-sm">+</span>
            </div>
          )
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add website/src/components/DemoHero/ScreenshotGallery.tsx
git commit -m "feat(website): add ScreenshotGallery component"
```

---

## Task 10: DemoHero Assembly

**Files:**
- Create: `website/src/components/DemoHero/DemoHero.tsx`

- [ ] **Step 1: Create component**

Create `website/src/components/DemoHero/DemoHero.tsx`:

```tsx
import { useTimeline } from "./useTimeline";
import { IPhoneFrame } from "./IPhoneFrame";
import { CapabilityTree } from "./CapabilityTree";
import { AgentTerminal } from "./AgentTerminal";
import { ScreenshotGallery } from "./ScreenshotGallery";

export function DemoHero() {
  const {
    visibleSteps,
    activeHighlight,
    screenshots,
    currentVideoTime,
    isResetting,
  } = useTimeline();

  return (
    <section>
      {/* Tagline */}
      <div className="text-center py-8 px-6">
        <h1 className="text-3xl md:text-4xl font-bold tracking-tight text-zinc-50">
          Eyes and hands for AI agents on iOS
        </h1>
        <p className="text-zinc-500 mt-2 text-sm">
          Watch Claude Code drive an iOS app through Remo — autonomously.
        </p>
      </div>

      {/* Three-column demo */}
      <div className="flex gap-4 px-5 pb-8 max-w-7xl mx-auto items-stretch">
        {/* Left: iPhone + Screenshots */}
        <div className="flex-none w-[300px] flex flex-col gap-3">
          <IPhoneFrame videoTime={currentVideoTime} />
          <div className="text-center text-violet-400 text-[10px]">
            ↓ screenshots land here ↓
          </div>
          <ScreenshotGallery
            screenshots={screenshots}
            isResetting={isResetting}
          />
        </div>

        {/* Center: Capability Tree */}
        <div className="flex-none w-[220px]">
          <CapabilityTree activeHighlight={activeHighlight} />
        </div>

        {/* Right: Agent Terminal */}
        <div className="flex-1 min-w-0">
          <AgentTerminal
            visibleSteps={visibleSteps}
            isResetting={isResetting}
          />
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Wire into App.tsx**

Replace `website/src/App.tsx`:

```tsx
import { Navbar } from "@/components/Navbar";
import { DemoHero } from "@/components/DemoHero/DemoHero";

function App() {
  return (
    <div className="min-h-screen bg-[#09090b] text-zinc-50">
      <Navbar />
      <DemoHero />
    </div>
  );
}

export default App;
```

- [ ] **Step 3: Verify demo runs**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/showcase-website/website
npm run dev
```

Expected: Three-column demo plays automatically. Terminal lines appear one by one, tree nodes highlight, screenshot thumbnails fly into the gallery. After ~44s it resets and loops.

- [ ] **Step 4: Commit**

```bash
git add website/src/components/DemoHero/DemoHero.tsx website/src/App.tsx
git commit -m "feat(website): assemble DemoHero three-column layout"
```

---

## Task 11: VisionSection

**Files:**
- Create: `website/src/components/VisionSection.tsx`

- [ ] **Step 1: Create component**

Create `website/src/components/VisionSection.tsx`:

```tsx
import { RefreshCw, Shield, Wifi } from "lucide-react";

const VALUE_PROPS = [
  {
    icon: RefreshCw,
    title: "Closed-Loop Autonomy",
    description:
      "Agent writes code, builds, invokes capabilities, inspects UI, verifies results — no human in the loop.",
  },
  {
    icon: Shield,
    title: "Debug-Only by Design",
    description:
      "#if DEBUG compilation ensures zero production runtime overhead. Remo compiles to no-ops in Release builds.",
  },
  {
    icon: Wifi,
    title: "Universal Discovery",
    description:
      "USB for physical devices, Bonjour for simulators — agents find devices automatically.",
  },
];

export function VisionSection() {
  return (
    <section className="py-20 px-6 border-t border-zinc-800">
      <div className="max-w-4xl mx-auto text-center">
        <h2 className="text-2xl md:text-3xl font-bold tracking-tight text-zinc-50">
          How Remo Harnesses iOS Development
        </h2>
        <p className="text-zinc-500 mt-3 max-w-2xl mx-auto">
          Remo gives AI agents a direct interface to iOS applications — turning
          the simulator into a programmable environment where agents can see,
          act, and verify autonomously.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-8 mt-12 max-w-5xl mx-auto">
        {VALUE_PROPS.map((prop) => (
          <div key={prop.title} className="text-center">
            <div className="inline-flex items-center justify-center w-12 h-12 rounded-lg bg-zinc-800 border border-zinc-700 mb-4">
              <prop.icon className="w-5 h-5 text-zinc-300" />
            </div>
            <h3 className="text-lg font-semibold text-zinc-50">
              {prop.title}
            </h3>
            <p className="text-sm text-zinc-400 mt-2 leading-relaxed">
              {prop.description}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Wire into App.tsx**

Update `website/src/App.tsx`:

```tsx
import { Navbar } from "@/components/Navbar";
import { DemoHero } from "@/components/DemoHero/DemoHero";
import { VisionSection } from "@/components/VisionSection";

function App() {
  return (
    <div className="min-h-screen bg-[#09090b] text-zinc-50">
      <Navbar />
      <DemoHero />
      <VisionSection />
    </div>
  );
}

export default App;
```

- [ ] **Step 3: Commit**

```bash
git add website/src/components/VisionSection.tsx website/src/App.tsx
git commit -m "feat(website): add VisionSection component"
```

---

## Task 12: FeaturesSection

**Files:**
- Create: `website/src/components/FeaturesSection.tsx`

- [ ] **Step 1: Create component**

Create `website/src/components/FeaturesSection.tsx`:

```tsx
import {
  Camera,
  Video,
  TreeDeciduous,
  Zap,
  MonitorSmartphone,
  ToggleRight,
} from "lucide-react";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";

const FEATURES = [
  {
    icon: Camera,
    title: "Screenshot Capture",
    description: "Instant visual verification after any action.",
  },
  {
    icon: Video,
    title: "Live Video Streaming",
    description: "H.264 hardware-encoded screen mirroring.",
  },
  {
    icon: TreeDeciduous,
    title: "View Tree Inspection",
    description: "Full UIView hierarchy as structured JSON.",
  },
  {
    icon: Zap,
    title: "Capability Invocation",
    description: "Register named handlers, agents call them dynamically.",
  },
  {
    icon: MonitorSmartphone,
    title: "Multi-Device Discovery",
    description: "USB + Bonjour, physical devices + simulators.",
  },
  {
    icon: ToggleRight,
    title: "Dynamic Registration",
    description: "Page-level register / unregister lifecycle.",
  },
];

export function FeaturesSection() {
  return (
    <section className="py-20 px-6 border-t border-zinc-800">
      <div className="max-w-5xl mx-auto">
        <h2 className="text-2xl md:text-3xl font-bold tracking-tight text-zinc-50 text-center">
          Core Capabilities
        </h2>
        <p className="text-zinc-500 mt-3 text-center">
          Everything an AI agent needs to interact with iOS applications.
        </p>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mt-12">
          {FEATURES.map((feature) => (
            <Card
              key={feature.title}
              className="bg-zinc-900 border-zinc-800 hover:border-zinc-700 transition-colors"
            >
              <CardHeader>
                <div className="inline-flex items-center justify-center w-10 h-10 rounded-lg bg-zinc-800 border border-zinc-700 mb-3">
                  <feature.icon className="w-4 h-4 text-zinc-300" />
                </div>
                <CardTitle className="text-base">{feature.title}</CardTitle>
                <CardDescription>{feature.description}</CardDescription>
              </CardHeader>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Wire into App.tsx**

Update `website/src/App.tsx`:

```tsx
import { Navbar } from "@/components/Navbar";
import { DemoHero } from "@/components/DemoHero/DemoHero";
import { VisionSection } from "@/components/VisionSection";
import { FeaturesSection } from "@/components/FeaturesSection";

function App() {
  return (
    <div className="min-h-screen bg-[#09090b] text-zinc-50">
      <Navbar />
      <DemoHero />
      <VisionSection />
      <FeaturesSection />
    </div>
  );
}

export default App;
```

- [ ] **Step 3: Commit**

```bash
git add website/src/components/FeaturesSection.tsx website/src/App.tsx
git commit -m "feat(website): add FeaturesSection component"
```

---

## Task 13: Footer

**Files:**
- Create: `website/src/components/Footer.tsx`

- [ ] **Step 1: Create component**

Create `website/src/components/Footer.tsx`:

```tsx
export function Footer() {
  return (
    <footer className="border-t border-zinc-800 px-6 py-6">
      <div className="max-w-5xl mx-auto flex items-center justify-between text-sm text-zinc-500">
        <span className="font-semibold text-zinc-400">Remo</span>
        <div className="flex items-center gap-4">
          <a
            href="https://github.com/yjmeqt/Remo"
            target="_blank"
            rel="noopener noreferrer"
            className="hover:text-zinc-300 transition-colors"
          >
            GitHub
          </a>
          <span>MIT License</span>
          <span>Built by Yi Jiang</span>
        </div>
      </div>
    </footer>
  );
}
```

- [ ] **Step 2: Wire into App.tsx (final)**

Update `website/src/App.tsx`:

```tsx
import { Navbar } from "@/components/Navbar";
import { DemoHero } from "@/components/DemoHero/DemoHero";
import { VisionSection } from "@/components/VisionSection";
import { FeaturesSection } from "@/components/FeaturesSection";
import { Footer } from "@/components/Footer";

function App() {
  return (
    <div className="min-h-screen bg-[#09090b] text-zinc-50 flex flex-col">
      <Navbar />
      <main className="flex-1">
        <DemoHero />
        <VisionSection />
        <FeaturesSection />
      </main>
      <Footer />
    </div>
  );
}

export default App;
```

- [ ] **Step 3: Verify full page**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/showcase-website/website
npm run dev
```

Expected: Full page renders — Navbar → Demo Hero (auto-playing, looping) → Vision Section → Features Cards → Footer. Dark theme throughout.

- [ ] **Step 4: Commit**

```bash
git add website/src/components/Footer.tsx website/src/App.tsx
git commit -m "feat(website): add Footer and complete page assembly"
```

---

## Task 14: Build Verification

- [ ] **Step 1: Run production build**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/showcase-website/website
npm run build
```

Expected: Build succeeds with no TypeScript or bundling errors.

- [ ] **Step 2: Preview production build**

```bash
npm run preview
```

Expected: Production build serves correctly at the preview URL, all animations work.

- [ ] **Step 3: Commit any build fixes if needed**
