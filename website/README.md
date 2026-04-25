# Remo Showcase Website

Interactive showcase demonstrating how AI agents use Remo to drive iOS apps through app-defined capabilities. Built with React, TypeScript, Vite, and Tailwind CSS.

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

## Demo Phone

The hero phone is a React mock of `RemoExample` (not a video). Each timeline step that triggers a capability carries a `phoneAction` (toast, confetti, navigate, grid tab/scroll, feed append, accent color), and `useTimeline` derives `PhoneState` from the elapsed clock so the on-screen reaction stays locked to the matching terminal line. To tweak timing, edit step `time` values in `timeline.ts` and `PHONE_ACTION_DELAY` for the per-action lag.

## Deployment

Deployed automatically to GitHub Pages via `.github/workflows/deploy-website.yml` on push to `main` when `website/` changes. Can also be triggered manually from the Actions tab.

## Design

### Visual Philosophy

Apple product page cinema style — each Remo capability owns a full viewport with scroll-triggered entrance animations. Dark theme with glassmorphism panels, ambient lighting, and film-grain noise texture.

### Section Order

The 5 showcase sections are deliberately ordered by conceptual importance:

1. **Capability Invocation** — first because it is the core Remo concept: register handlers in Swift, call them from anywhere, and return structured results.
2. **Dynamic Registration** — second because lifecycle-aware capabilities are a distinctive part of Remo's value, not an implementation footnote.
3. **View Tree Inspection** — supporting context for how agents can inspect app structure once capabilities move the app into the right state.
4. **Multi-Device Discovery** — USB + Bonjour, scaling capability-driven workflows across devices.
5. **Tool Boundary** — explicit positioning: xcodebuildmcp handles simulator automation and capture; Remo handles in-app semantic control.

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

Each section has a distinct accent color: emerald (Capability), teal-violet (Dynamic Registration), purple (View Tree), orange (Discovery), sky blue (Tool Boundary).

Code syntax colors are consistent across all CLI panels: violet keywords, emerald functions, amber strings, zinc comments.

### Hero Demo

The hero section simulates RemoExample being driven by Remo capabilities. The phone is a React mock of the real iOS UI (Home + Grid tabs, toast, confetti, accent color), so terminal commands and on-screen reactions stay deterministically aligned without a recorded video.

The narrative has two phases:

1. **Code phase** (0 → `PHONE_BOOT_TIME`, terminal only): Claude explores the codebase, reads `ContentView.swift`, and registers capabilities. The iPhone screen shows a lock-screen image.
2. **Live app phase** (after `PHONE_BOOT_TIME`, terminal + simulated phone): Claude invokes capabilities in sequence. Each `command` step carries an optional `phoneAction` consumed by `useTimeline` to derive the current `PhoneState`.

**Action timing:** Each `phoneAction` lands at `step.time + PHONE_ACTION_DELAY` (≈0.45s) so the screen reacts a beat after the terminal line, mimicking an RPC round-trip. Tune both in `timeline.ts`.

**Curated capability sequence:** toast, confetti, accent color, navigate to Grid, switch grid tab, scroll, append feed card. Internal/non-visual capabilities are excluded.

### Design Specs

Detailed design specifications are preserved in `docs/superpowers/specs/`:

| Spec | Content |
|------|---------|
| `showcase-website-design` | Original website structure — page layout, 3-column hero, features grid |
| `premium-capability-showcase-design` | Full-viewport showcase redesign — glassmorphism design system, View Tree + Capability sections |
| `real-demo-design` | Hero demo recording pipeline — narrative structure, capability sequence curation, video alignment |
| `remaining-showcase-sections-design` | Discovery and Dynamic Registration section specs from the original full showcase |

## Architecture

```
src/
├── components/
│   ├── DemoHero/
│   │   ├── DemoHero.tsx       — two-column layout (iPhone + terminal)
│   │   ├── IPhoneFrame.tsx    — iPhone bezel + screen container
│   │   ├── PhoneScreen/       — React mock of the RemoExample UI
│   │   │   ├── PhoneScreen.tsx, StatusBar.tsx, TabBar.tsx
│   │   │   ├── HomeScreen.tsx, GridScreen.tsx
│   │   │   ├── Toast.tsx, Confetti.tsx
│   │   │   ├── colors.ts, gridSeed.ts
│   │   ├── AgentTerminal.tsx  — animated terminal showing agent commands
│   │   ├── timeline.ts        — demo steps with phone actions
│   │   └── useTimeline.ts     — clock + phone state derivation
│   ├── FeatureShowcase/
│   │   ├── FeatureShowcase.tsx            — renders the active marketing sections
│   │   ├── shared.tsx                     — design system (GlassPanel, AmbientLight, animations)
│   │   ├── CapabilitySection.tsx          — Register → Invoke → Response pipeline
│   │   ├── DynamicRegistrationSection.tsx — lifecycle-aware capability diff
│   │   ├── ViewTreeSection.tsx            — phone wireframe → JSON with hover linking
│   │   ├── PhoneWireframe.tsx             — interactive phone wireframe for View Tree
│   │   ├── DeviceDiscoverySection.tsx     — device card grid with USB/Bonjour tags
│   │   └── ToolBoundarySection.tsx        — Remo vs xcodebuildmcp product boundary
│   ├── Navbar.tsx
│   ├── VisionSection.tsx
│   └── Footer.tsx
├── App.tsx
└── main.tsx
```
