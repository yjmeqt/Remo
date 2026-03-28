# Remo Showcase Website

Interactive showcase demonstrating how AI agents use Remo to autonomously verify iOS apps. Built with React, TypeScript, Vite, and Tailwind CSS.

**Live:** [yjmeqt.github.io/Remo](https://yjmeqt.github.io/Remo/)

## Development

```bash
cd website
npm install
npm run dev      # http://localhost:5173/Remo/
```

## Build & Preview

```bash
npm run build    # outputs to dist/
npm run preview  # preview production build locally
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
