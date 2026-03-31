# Remo Showcase Website

Interactive showcase demonstrating how AI agents use Remo to autonomously verify iOS apps. Built with React, TypeScript, Vite, and Tailwind CSS.

**Live:** [yjmeqt.github.io/Remo](https://yjmeqt.github.io/Remo/)

## Development

```bash
cd website
pnpm install
pnpm dev      # http://localhost:5173/Remo/
```

## Build & Preview

```bash
cd website
pnpm build    # outputs to dist/
pnpm preview  # preview production build locally
```

## Demo Video

The hero section plays a real screen recording of RemoExample being driven by Remo capabilities. To re-record:

```bash
# From repo root — requires a booted iOS Simulator with RemoExample
./scripts/record-demo.sh

# Then copy artifacts
cp /tmp/remo-demo/demo.mp4 website/public/demo.mp4
# Update website/src/components/DemoHero/timeline.ts with new elapsed_s values
```

See `scripts/record-demo.sh` for details on the recording process.

## Deployment

Deployed automatically to GitHub Pages via `.github/workflows/deploy-website.yml` on push to `main` when `website/` changes. Can also be triggered manually from the Actions tab.

## Design

### Visual Philosophy

Apple product page cinema style — each Remo capability owns a full viewport with scroll-triggered entrance animations. Dark theme with glassmorphism panels, ambient lighting, and film-grain noise texture.

### Section Order

The 6 showcase sections are deliberately ordered by conceptual importance:

1. **Capability Invocation** — first because it's the core Remo concept: register handlers in Swift, call from anywhere. This is the first thing visitors should understand.
2. **View Tree Inspection** — how agents "see" the app (structured JSON of the UI hierarchy).
3. **Screenshot Capture** — instant visual verification after every action.
4. **Live Video Streaming** — real-time H.264 screen mirroring.
5. **Multi-Device Discovery** — USB + Bonjour, scaling across devices.
6. **Dynamic Registration** — advanced concept: capabilities follow the UI lifecycle.

### Design System (`shared.tsx`)

All showcase sections share a unified visual language:

- **ShowcaseSection** — full-viewport (`min-h-screen`) centered wrapper
- **SectionHeader** — 11px uppercase label + 48px gradient title + 17px subtitle
- **GlassPanel** — `backdrop-filter: blur(20px)`, semi-transparent zinc-900, colored top-edge glow
- **NoiseOverlay** — SVG fractalNoise at 3% opacity (film-grain tactile depth)
- **AmbientLight** — dual radial gradients per section (accent color at 7% + complementary at 5%)
- **FloatingParticles** — 3 animated dots per section
- **GradientConnector** — animated vertical gradient line between panels
- Entrance animations trigger at 30% viewport intersection (`whileInView`, `once: true`)

Each section has a distinct accent color: emerald (Capability), purple (View Tree), pink (Screenshot), sky blue (Video), orange (Discovery), teal+violet (Dynamic Registration).

Code syntax colors are consistent across all CLI panels: violet keywords, emerald functions, amber strings, zinc comments.

### Hero Demo

The hero section plays a real screen recording of RemoExample driven by Remo capabilities. The demo has a two-phase narrative:

1. **Code phase** (0–10s, terminal only): Claude explores the codebase, reads `ContentView.swift`, registers capabilities. iPhone screen is blank.
2. **Verify phase** (10s onwards, terminal + video): Claude invokes capabilities in sequence. The iPhone video shows the real app responding in sync.

**Video-terminal synchronization:** Terminal step times are `VIDEO_PHASE_START + elapsed_s` where `elapsed_s` comes from real recording timestamps (`demo-timestamps.json`). Video playback time is `(elapsed - VIDEO_PHASE_START) + VIDEO_OFFSET`, where `VIDEO_OFFSET` (1s) skips the simctl recording startup idle period. See `timeline.ts` for the full alignment model.

**Curated capability sequence:** The demo exercises a visually compelling subset — counter increments (number changes), toast notification, accent color change, confetti animation, tab navigation, item list additions. Internal capabilities (`__ping`, `__device_info`) and non-visual ones (`state.get`) are excluded.

**Why `simctl recordVideo`:** The recording script uses `xcrun simctl io recordVideo` instead of `remo mirror --save` because `remo mirror`'s MP4 muxer uses a hardcoded frame duration, compressing idle periods (a 17s recording becomes ~10s). `simctl` maintains proper wall-clock timing. See issue #18.

### Design Specs

Detailed design specifications are preserved in `docs/superpowers/specs/`:

| Spec | Content |
|------|---------|
| `showcase-website-design` | Original website structure — page layout, 3-column hero, features grid |
| `premium-capability-showcase-design` | Full-viewport showcase redesign — glassmorphism design system, View Tree + Capability sections |
| `real-demo-design` | Hero demo recording pipeline — narrative structure, capability sequence curation, video alignment |
| `remaining-showcase-sections-design` | Screenshot, Video, Discovery, Dynamic Registration — per-section layout and animation specs |

## Architecture

```
src/
├── components/
│   ├── DemoHero/
│   │   ├── DemoHero.tsx       — two-column layout (iPhone + terminal)
│   │   ├── IPhoneFrame.tsx    — iPhone mockup with synced video playback
│   │   ├── AgentTerminal.tsx  — animated terminal showing agent commands
│   │   ├── timeline.ts        — demo steps with timestamps from recording
│   │   └── useTimeline.ts     — animation driver (requestAnimationFrame)
│   ├── FeatureShowcase/
│   │   ├── FeatureShowcase.tsx            — renders all 6 showcase sections
│   │   ├── shared.tsx                     — design system (GlassPanel, AmbientLight, animations)
│   │   ├── CapabilitySection.tsx          — Register → Invoke → Response pipeline
│   │   ├── ViewTreeSection.tsx            — phone wireframe → JSON with hover linking
│   │   ├── PhoneWireframe.tsx             — interactive phone wireframe for View Tree
│   │   ├── ScreenshotSection.tsx          — shutter flash + capture carousel
│   │   ├── VideoStreamSection.tsx         — REC badge + waveform timeline
│   │   ├── DeviceDiscoverySection.tsx     — device card grid with USB/Bonjour tags
│   │   └── DynamicRegistrationSection.tsx — dual-screen capability diff
│   ├── Navbar.tsx
│   ├── VisionSection.tsx
│   └── Footer.tsx
├── App.tsx
└── main.tsx
```
