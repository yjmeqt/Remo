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
│   └── DemoHero/
│       ├── DemoHero.tsx       — two-column layout (iPhone + terminal)
│       ├── IPhoneFrame.tsx    — iPhone mockup with synced video playback
│       ├── AgentTerminal.tsx  — animated terminal showing agent commands
│       ├── timeline.ts        — demo steps with timestamps from recording
│       └── useTimeline.ts     — animation driver (requestAnimationFrame)
├── App.tsx
└── main.tsx
```
