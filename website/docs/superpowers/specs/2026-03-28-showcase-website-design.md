# Remo Showcase Website — Design Spec

## Overview

A single-page showcase website for Remo that leads with an interactive demo animation, demonstrating how AI agents drive iOS development through Remo. Built with React + Vite + Tailwind CSS + shadcn/ui + Framer Motion.

## Target Audience

Both developers/AI agent builders who might integrate Remo and a broader tech audience interested in agentic iOS development.

## Visual Style

shadcn/ui dark theme — zinc grays (`#09090b` background, `#18181b` surfaces, `#27272a` borders), white text, subtle contrast. Professional and modern.

## Page Structure

```
┌─────────────────────────────────────────────┐
│  Navbar (Remo logo, Docs, GitHub, Get Started) │
├─────────────────────────────────────────────┤
│  Hero tagline                                │
│  "Eyes and hands for AI agents on iOS"       │
├────────────┬──────────┬─────────────────────┤
│  iPhone 17 │ Capabil- │  Claude Code         │
│  frame +   │ ity API  │  Terminal            │
│  video     │ Tree     │  (simulated agent    │
│            │          │   session)           │
│  ──────    │          │                      │
│  Screenshot│          │                      │
│  gallery   │          │                      │
├────────────┴──────────┴─────────────────────┤
│  Vision: "How Remo Harnesses iOS Dev"        │
│  3 value props in a row                      │
├─────────────────────────────────────────────┤
│  Features: 6 capability cards (2×3 grid)     │
├─────────────────────────────────────────────┤
│  Footer: logo, GitHub, MIT, credits          │
└─────────────────────────────────────────────┘
```

## Demo Hero — Three-Column Layout

### Left Column (widest, ~30%)
- **iPhone 17 frame** with generous margins (dark container with padding around the phone)
- Embedded `<video>` element inside the phone screen, muted, no controls
- Video is placeholder for now — will be replaced with a real recording from RemoExample later
- Video is not free-playing; it is scrubbed to specific timestamps per timeline step
- **Screenshot gallery** below the phone — a grid of thumbnails that accumulates as the demo progresses

### Center Column (~25%)
- **Capability API tree** — a tree view of the app's registered capabilities
- Organized by feature group: device, counter, items, settings
- Nodes highlight (pulse green) when the agent invokes them
- Acts as the visual bridge connecting agent actions to app behavior

### Right Column (~45%)
- **Claude Code terminal** — simulated terminal window with macOS traffic light buttons
- Shows a complete agent session: user prompt → Claude reasoning → Remo CLI commands → results
- Terminal lines appear with typewriter effect, synchronized to the timeline

### Animation System

Driven by a single timeline array in `timeline.ts`:

```ts
type TerminalLine = {
  type: 'prompt' | 'claude' | 'command' | 'result'
  text: string
}

type DemoStep = {
  time: number           // seconds from start of demo
  terminal: TerminalLine // what appears in the terminal
  treeHighlight?: string // which capability tree node to highlight
  videoTime?: number     // scrub iPhone video to this timestamp
  screenshot?: boolean   // triggers screenshot fly animation
}
```

**Per-step animation flow:**
1. Terminal text appears with typewriter effect (Framer Motion character animation)
2. If `treeHighlight` is set, the corresponding tree node pulses with a green glow
3. If `videoTime` is set, the iPhone video seeks to that timestamp
4. If `screenshot` is true, a thumbnail of the phone screen animates from the iPhone position down to the screenshot gallery using Framer Motion `layoutId`

**Looping:** After the last step, a short pause (~2s), then reset — terminal clears, gallery empties, video rewinds, replay begins.

## Vision Section — "How Remo Harnesses iOS Development"

Centered heading + subtitle, then 3 value propositions in a row:

1. **Closed-loop autonomy** — Agent writes code, builds, invokes capabilities, inspects UI, verifies results — no human in the loop
2. **Debug-only by design** — `#if DEBUG` compilation ensures zero production runtime overhead; Remo compiles to no-ops in Release builds
3. **Universal discovery** — USB for physical devices, Bonjour for simulators — agents find devices automatically

Each item: icon + title + one-line description.

## Features Section

A 2×3 grid of shadcn `Card` components:

| Feature | Description |
|---------|------------|
| Screenshot capture | Instant visual verification after any action |
| Live video streaming | H.264 hardware-encoded screen mirroring |
| View tree inspection | Full UIView hierarchy as structured JSON |
| Capability invocation | Register named handlers, agents call them dynamically |
| Multi-device discovery | USB + Bonjour, physical devices + simulators |
| Dynamic registration | Page-level `register` / `unregister` lifecycle |

Each card: icon + title + one-line description. Dark zinc styling.

## Footer

Single row: Remo logo (left), GitHub link, "MIT License", "Built by Yi Jiang" (right).

## Project Structure

```
website/
├── src/
│   ├── components/
│   │   ├── Navbar.tsx
│   │   ├── DemoHero/
│   │   │   ├── DemoHero.tsx           — 3-column layout container
│   │   │   ├── IPhoneFrame.tsx        — phone frame + embedded video
│   │   │   ├── CapabilityTree.tsx     — animated tree with highlight state
│   │   │   ├── AgentTerminal.tsx      — typewriter terminal simulation
│   │   │   ├── ScreenshotGallery.tsx  — thumbnail grid + fly animation
│   │   │   └── timeline.ts           — JSON demo script
│   │   ├── VisionSection.tsx          — value proposition section
│   │   ├── FeaturesSection.tsx        — capability cards grid
│   │   └── Footer.tsx
│   ├── App.tsx
│   └── main.tsx
├── public/
│   └── demo.mp4                       — placeholder, replaced later
├── index.html
├── vite.config.ts
├── tailwind.config.ts
├── package.json
└── tsconfig.json
```

## Tech Stack

- **Vite** — build tool and dev server
- **React 19** + **TypeScript**
- **Tailwind CSS v4** — utility-first styling
- **shadcn/ui** — component library (Card, Button)
- **Framer Motion** — animations (typewriter, tree highlights, screenshot fly, layout transitions)

## Video Strategy

The iPhone video is a placeholder during development (gradient or static image). The real video will be recorded from RemoExample later and dropped into `public/demo.mp4`. The video is scrubbed frame-by-frame via the timeline, not free-playing.

## Deployment

Not specified yet. The site builds to static files via `vite build` and can be deployed to GitHub Pages, Vercel, or any static host.
