# Remaining Showcase Sections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 4 new full-viewport showcase sections and reorder all 6 sections in FeatureShowcase.

**Architecture:** Each section is a self-contained React component using shared primitives from `shared.tsx` (ShowcaseSection, SectionHeader, GlassPanel, NoiseOverlay, AmbientLight, FloatingParticles, animation helpers). Phone wireframes are built inline per section (simpler than the interactive PhoneWireframe.tsx). CSS keyframe animations are implemented via Framer Motion's `animate` prop.

**Tech Stack:** React 19, TypeScript, Framer Motion 12, Tailwind CSS 4

---

## File Structure

```
website/src/components/FeatureShowcase/
├── FeatureShowcase.tsx            — MODIFY: reorder + import 4 new sections
├── shared.tsx                     — existing, no changes
├── CapabilitySection.tsx          — existing, no changes
├── ViewTreeSection.tsx            — existing, no changes
├── PhoneWireframe.tsx             — existing, no changes
├── ScreenshotSection.tsx          — CREATE
├── VideoStreamSection.tsx         — CREATE
├── DeviceDiscoverySection.tsx     — CREATE
└── DynamicRegistrationSection.tsx — CREATE
```

---

### Task 1: Screenshot Capture Section

**Files:**
- Create: `website/src/components/FeatureShowcase/ScreenshotSection.tsx`

**Context:** This section uses a vertical layout: phone with shutter flash → thumbnail carousel → CLI panel. Accent color is pink (`#f472b6`). Refer to the design spec at `website/docs/superpowers/specs/2026-03-28-remaining-showcase-sections-design.md` Section 3.

**Shared imports needed:** `ShowcaseSection`, `SectionHeader`, `NoiseOverlay`, `AmbientLight`, `FloatingParticles`, `fadeInUp`. From `shared.tsx`.

- [ ] **Step 1: Create ScreenshotSection.tsx**

```tsx
import { motion } from "framer-motion";
import {
  ShowcaseSection,
  SectionHeader,
  NoiseOverlay,
  AmbientLight,
  FloatingParticles,
  fadeInUp,
} from "./shared";

// ---------------------------------------------------------------------------
// Phone with shutter flash
// ---------------------------------------------------------------------------

function ShutterPhone() {
  return (
    <div
      className="relative flex-shrink-0"
      style={{ width: 160, height: 320, borderRadius: 28 }}
    >
      {/* Phone body */}
      <div
        className="absolute inset-0 overflow-hidden"
        style={{
          borderRadius: 28,
          border: "1.5px solid rgba(113,113,122,0.4)",
          background: "rgba(9,9,11,0.8)",
        }}
      >
        {/* Notch */}
        <div
          className="absolute top-[6px] left-1/2 -translate-x-1/2 z-10"
          style={{
            width: 44,
            height: 15,
            background: "#09090b",
            borderRadius: "0 0 10px 10px",
          }}
        />

        {/* Screen */}
        <div
          className="absolute overflow-hidden flex flex-col"
          style={{
            left: "4%",
            right: "4%",
            top: "2.5%",
            bottom: "2.5%",
            borderRadius: 22,
            background: "linear-gradient(180deg, #18181b, #1c1c20)",
            padding: "36px 10px 10px",
          }}
        >
          {/* Shutter flash overlay */}
          <motion.div
            className="absolute inset-0 pointer-events-none"
            style={{ borderRadius: 22, background: "rgba(244,114,182,0.12)" }}
            animate={{
              opacity: [0, 0, 0, 0, 1, 0, 0],
            }}
            transition={{
              duration: 3,
              times: [0, 0.8, 0.84, 0.85, 0.87, 0.92, 1],
              repeat: Infinity,
              ease: "easeInOut",
            }}
          />

          {/* Captured badge */}
          <motion.div
            className="absolute top-[38px] right-[12px] z-20"
            style={{
              fontSize: 8,
              textTransform: "uppercase",
              letterSpacing: 1.5,
              fontWeight: 600,
              color: "#f472b6",
              background: "rgba(244,114,182,0.15)",
              border: "1px solid rgba(244,114,182,0.25)",
              padding: "2px 6px",
              borderRadius: 4,
            }}
            animate={{
              opacity: [0, 0, 0, 0, 1, 1, 0, 0],
              scale: [0.9, 0.9, 0.9, 0.9, 1, 1, 0.9, 0.9],
            }}
            transition={{
              duration: 3,
              times: [0, 0.8, 0.84, 0.85, 0.87, 0.95, 0.97, 1],
              repeat: Infinity,
              ease: "easeInOut",
            }}
          >
            Captured
          </motion.div>

          {/* Nav bar */}
          <div className="h-[14px] rounded bg-zinc-700/30 mb-2" />

          {/* Counter */}
          <div className="text-[28px] font-bold text-center text-white my-6">
            4
          </div>

          {/* Button */}
          <div
            className="w-[70%] mx-auto h-7 rounded-lg flex items-center justify-center text-[10px] font-medium"
            style={{
              background: "rgba(139,92,246,0.3)",
              border: "1px solid rgba(139,92,246,0.4)",
              color: "#c084fc",
            }}
          >
            Increment
          </div>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Thumbnail strip
// ---------------------------------------------------------------------------

const THUMBS = [
  { num: 1, value: "1", active: false },
  { num: 2, value: "2", active: false },
  { num: 3, value: "3", active: false },
  { num: 4, value: "4", active: true },
];

function ThumbnailStrip() {
  return (
    <div className="flex gap-2.5 items-center justify-center">
      {THUMBS.map((t, i) => (
        <motion.div
          key={t.num}
          className="relative cursor-default"
          style={{
            width: 64,
            height: 110,
            borderRadius: 10,
            border: t.active
              ? "1px solid rgba(244,114,182,0.5)"
              : "1px solid rgba(63,63,70,0.4)",
            background: "rgba(24,24,27,0.6)",
            boxShadow: t.active
              ? "0 0 20px rgba(244,114,182,0.15)"
              : "none",
            overflow: "hidden",
          }}
          {...fadeInUp(0.4 + i * 0.1)}
        >
          {/* Inner screen */}
          <div
            className="absolute flex flex-col"
            style={{
              inset: 3,
              borderRadius: 7,
              overflow: "hidden",
              background: "linear-gradient(180deg, #1c1c20, #18181b)",
              padding: "14px 4px 4px",
            }}
          >
            <div className="h-2 rounded bg-zinc-700/30 mb-1" />
            <div
              className="text-center my-1.5"
              style={{
                fontSize: 8,
                fontWeight: 600,
                color: t.active ? "#f472b6" : "#71717a",
              }}
            >
              {t.value}
            </div>
            <div
              className="w-[60%] mx-auto rounded"
              style={{
                height: 10,
                background: "rgba(139,92,246,0.2)",
              }}
            />
          </div>

          {/* Frame number */}
          <div
            className="absolute bottom-1 right-1.5 font-semibold"
            style={{
              fontSize: 7,
              color: t.active ? "#f472b6" : "#52525b",
            }}
          >
            #{t.num}
          </div>
        </motion.div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// CLI panel
// ---------------------------------------------------------------------------

function CliPanel() {
  return (
    <motion.div
      className="w-full max-w-[400px] mx-auto"
      style={{
        background: "rgba(24,24,27,0.7)",
        border: "1px solid rgba(63,63,70,0.3)",
        borderRadius: 10,
        padding: "14px 16px",
        fontFamily: "'SF Mono','Fira Code',monospace",
        fontSize: 11,
        lineHeight: 1.8,
      }}
      {...fadeInUp(0.9)}
    >
      <div className="text-zinc-700">$ Agent's verification loop</div>
      <div>
        <span className="text-zinc-400">remo call</span>{" "}
        <span className="text-emerald-400">counter.increment</span>{" "}
        <span className="text-amber-400">{"'{\"amount\": 1}'"}</span>
      </div>
      <div>
        <span className="text-zinc-400">remo</span>{" "}
        <span className="text-emerald-400">screenshot</span>{" "}
        <span className="text-amber-400">--format jpeg</span>
      </div>
      <div>
        <span className="text-emerald-400">✓</span>{" "}
        <span className="text-pink-400">Δ detected</span>{" "}
        <span className="text-zinc-700">— counter 3→4, UI verified</span>
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// ScreenshotSection
// ---------------------------------------------------------------------------

export function ScreenshotSection() {
  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(244,114,182,0.07)"
        secondary="rgba(251,146,60,0.05)"
        primaryPos="50% 30%"
        secondaryPos="35% 65%"
      />
      <FloatingParticles
        particles={[
          { top: "18%", left: "20%", color: "#f472b6", duration: 6, delay: 0 },
          { top: "60%", left: "78%", color: "#f472b6", duration: 8, delay: 2 },
          { top: "82%", left: "30%", color: "#fbbf24", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="Screenshot Capture"
        labelColor="#f472b6"
        title="Instant visual verification"
        subtitle="Capture the screen after every action. Agents verify UI state autonomously — no manual checking, no guesswork."
      />

      <div className="relative z-10 flex flex-col items-center gap-6 w-full">
        {/* Phone */}
        <motion.div {...fadeInUp(0.2)}>
          <ShutterPhone />
        </motion.div>

        {/* Thumbnails */}
        <ThumbnailStrip />

        {/* CLI */}
        <CliPanel />
      </div>
    </ShowcaseSection>
  );
}
```

- [ ] **Step 2: Verify the build**

Run from `website/` directory:
```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/showcase-website/website && npx tsc --noEmit && npm run build
```

Expected: no TypeScript errors, build succeeds.

- [ ] **Step 3: Commit**

```bash
git add website/src/components/FeatureShowcase/ScreenshotSection.tsx
git commit -m "feat(showcase): add Screenshot Capture section with shutter flash and carousel"
```

---

### Task 2: Live Video Streaming Section

**Files:**
- Create: `website/src/components/FeatureShowcase/VideoStreamSection.tsx`

**Context:** Vertical layout: phone with REC badge → timeline bar with waveform visualization. Accent color is sky blue (`#38bdf8`). Refer to spec Section 4.

- [ ] **Step 1: Create VideoStreamSection.tsx**

```tsx
import { motion } from "framer-motion";
import {
  ShowcaseSection,
  SectionHeader,
  NoiseOverlay,
  AmbientLight,
  FloatingParticles,
  fadeInUp,
} from "./shared";

// ---------------------------------------------------------------------------
// Phone with REC badge
// ---------------------------------------------------------------------------

function RecPhone() {
  return (
    <div
      className="relative flex-shrink-0"
      style={{ width: 150, height: 300, borderRadius: 26 }}
    >
      <div
        className="absolute inset-0 overflow-hidden"
        style={{
          borderRadius: 26,
          border: "1.5px solid rgba(113,113,122,0.4)",
          background: "rgba(9,9,11,0.8)",
        }}
      >
        {/* Notch */}
        <div
          className="absolute top-[6px] left-1/2 -translate-x-1/2 z-10"
          style={{
            width: 42,
            height: 14,
            background: "#09090b",
            borderRadius: "0 0 10px 10px",
          }}
        />

        {/* Screen */}
        <div
          className="absolute overflow-hidden flex flex-col"
          style={{
            left: "4%",
            right: "4%",
            top: "2.5%",
            bottom: "2.5%",
            borderRadius: 22,
            background: "linear-gradient(180deg, #18181b, #1c1c20)",
            padding: "36px 10px 10px",
          }}
        >
          {/* REC badge */}
          <div
            className="absolute top-[38px] left-[10px] z-20 flex items-center gap-1"
            style={{
              fontSize: 8,
              textTransform: "uppercase",
              letterSpacing: 1.5,
              fontWeight: 700,
              color: "#ef4444",
              background: "rgba(239,68,68,0.15)",
              border: "1px solid rgba(239,68,68,0.3)",
              padding: "2px 7px",
              borderRadius: 4,
            }}
          >
            <motion.span
              className="rounded-full"
              style={{ width: 4, height: 4, background: "#ef4444" }}
              animate={{ opacity: [0.4, 1, 0.4] }}
              transition={{
                duration: 1.5,
                repeat: Infinity,
                ease: "easeInOut",
              }}
            />
            Rec
          </div>

          {/* Nav bar */}
          <div className="h-[14px] rounded bg-zinc-700/30 mb-2" />

          {/* Counter */}
          <div className="text-[28px] font-bold text-center text-white my-6">
            4
          </div>

          {/* Button */}
          <div
            className="w-[70%] mx-auto h-7 rounded-lg flex items-center justify-center text-[10px] font-medium"
            style={{
              background: "rgba(139,92,246,0.3)",
              border: "1px solid rgba(139,92,246,0.4)",
              color: "#c084fc",
            }}
          >
            Increment
          </div>

          {/* Animated list rows */}
          <div className="mt-3 flex flex-col gap-1">
            {[0, 0.3, 0.6].map((delay, i) => (
              <motion.div
                key={i}
                className="rounded bg-zinc-700/15"
                style={{
                  height: 12,
                  width: i === 1 ? "85%" : i === 2 ? "70%" : "100%",
                }}
                animate={{ y: [0, -4, 0], opacity: [0.5, 0.8, 0.5] }}
                transition={{
                  duration: 4,
                  delay,
                  repeat: Infinity,
                  ease: "easeInOut",
                }}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Waveform bar heights (fixed, pseudo-random)
// ---------------------------------------------------------------------------

const BAR_HEIGHTS = [
  12, 24, 18, 32, 20, 38, 28, 16, 30, 22, 36, 14, 26, 40, 20, 34, 18, 28,
  10, 22, 30, 16, 36, 24, 32, 12, 38, 20, 26, 14,
];

// ---------------------------------------------------------------------------
// Timeline bar
// ---------------------------------------------------------------------------

function TimelineBar() {
  return (
    <div
      className="w-full max-w-[500px]"
      style={{
        background: "rgba(24,24,27,0.7)",
        border: "1px solid rgba(63,63,70,0.3)",
        borderRadius: 10,
        padding: "16px 20px",
      }}
    >
      {/* Header */}
      <div className="flex justify-between items-center mb-2.5">
        <span
          style={{
            fontSize: 10,
            color: "#38bdf8",
            fontWeight: 600,
            textTransform: "uppercase",
            letterSpacing: 1.5,
          }}
        >
          Recording
        </span>
        <span
          style={{
            fontSize: 10,
            color: "#52525b",
            fontFamily: "'SF Mono','Fira Code',monospace",
          }}
        >
          00:04.2 / 00:06.5
        </span>
      </div>

      {/* Waveform */}
      <div className="flex items-end gap-[1.5px]" style={{ height: 40 }}>
        {BAR_HEIGHTS.map((h, i) => (
          <motion.div
            key={i}
            style={{
              width: 3,
              height: h,
              borderRadius: 1.5,
              background: "rgba(56,189,248,0.4)",
            }}
            animate={{ opacity: [0.3, 0.8, 0.3] }}
            transition={{
              duration: 2,
              delay: (i / BAR_HEIGHTS.length) * 2,
              repeat: Infinity,
              ease: "easeInOut",
            }}
          />
        ))}
      </div>

      {/* Playhead track */}
      <div
        className="relative mt-2"
        style={{
          height: 2,
          background: "rgba(63,63,70,0.3)",
          borderRadius: 1,
        }}
      >
        <div
          className="absolute top-0 left-0 h-full"
          style={{
            width: "65%",
            borderRadius: 1,
            background: "linear-gradient(90deg, #38bdf8, #818cf8)",
          }}
        />
        <div
          className="absolute"
          style={{
            top: -3,
            left: "65%",
            width: 8,
            height: 8,
            borderRadius: "50%",
            background: "#38bdf8",
            border: "2px solid #09090b",
            boxShadow: "0 0 8px rgba(56,189,248,0.4)",
          }}
        />
      </div>

      {/* Frame markers */}
      <div
        className="flex justify-between mt-1.5"
        style={{
          fontSize: 7,
          color: "#3f3f46",
          fontFamily: "'SF Mono','Fira Code',monospace",
        }}
      >
        <span>0:00</span>
        <span>0:02</span>
        <span>0:04</span>
        <span>0:06</span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// VideoStreamSection
// ---------------------------------------------------------------------------

export function VideoStreamSection() {
  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(56,189,248,0.07)"
        secondary="rgba(129,140,248,0.05)"
        primaryPos="50% 30%"
        secondaryPos="60% 65%"
      />
      <FloatingParticles
        particles={[
          { top: "15%", left: "18%", color: "#38bdf8", duration: 6, delay: 0 },
          { top: "55%", left: "82%", color: "#818cf8", duration: 8, delay: 2 },
          { top: "80%", left: "25%", color: "#38bdf8", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="Live Video Streaming"
        labelColor="#38bdf8"
        title="Stream the screen in real time"
        subtitle="H.264 hardware-encoded mirroring. Record sessions, review animations, verify transitions — frame by frame."
      />

      <div className="relative z-10 flex flex-col items-center gap-6 w-full">
        {/* Phone */}
        <motion.div {...fadeInUp(0.2)}>
          <RecPhone />
        </motion.div>

        {/* Timeline */}
        <motion.div className="w-full flex justify-center" {...fadeInUp(0.5)}>
          <TimelineBar />
        </motion.div>
      </div>
    </ShowcaseSection>
  );
}
```

- [ ] **Step 2: Verify the build**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/showcase-website/website && npx tsc --noEmit && npm run build
```

Expected: no TypeScript errors, build succeeds.

- [ ] **Step 3: Commit**

```bash
git add website/src/components/FeatureShowcase/VideoStreamSection.tsx
git commit -m "feat(showcase): add Live Video Streaming section with timeline waveform"
```

---

### Task 3: Multi-Device Discovery Section

**Files:**
- Create: `website/src/components/FeatureShowcase/DeviceDiscoverySection.tsx`

**Context:** Vertical layout: 3-column device card grid → CLI panel. Accent orange (`#fb923c`) + violet (`#a78bfa`). Refer to spec Section 5.

- [ ] **Step 1: Create DeviceDiscoverySection.tsx**

```tsx
import { motion } from "framer-motion";
import {
  ShowcaseSection,
  SectionHeader,
  NoiseOverlay,
  AmbientLight,
  FloatingParticles,
  fadeInUp,
} from "./shared";

// ---------------------------------------------------------------------------
// Device data
// ---------------------------------------------------------------------------

interface DeviceInfo {
  icon: string;
  name: string;
  os: string;
  connection: "USB" | "Bonjour";
  delay: number;
}

const DEVICES: DeviceInfo[] = [
  { icon: "📱", name: "iPhone 17 Pro", os: "iOS 18.4", connection: "USB", delay: 0 },
  { icon: "📱", name: "iPad Air (M3)", os: "iPadOS 18.4", connection: "USB", delay: 0.5 },
  { icon: "📱", name: "iPhone 16 Sim", os: "iOS 18.0", connection: "Bonjour", delay: 1 },
];

const TAG_STYLES = {
  USB: {
    color: "#fb923c",
    background: "rgba(251,146,60,0.1)",
    border: "1px solid rgba(251,146,60,0.2)",
    dotColor: "#fb923c",
    dotShadow: "0 0 6px rgba(251,146,60,0.5)",
  },
  Bonjour: {
    color: "#a78bfa",
    background: "rgba(167,139,250,0.1)",
    border: "1px solid rgba(167,139,250,0.2)",
    dotColor: "#a78bfa",
    dotShadow: "0 0 6px rgba(167,139,250,0.5)",
  },
};

// ---------------------------------------------------------------------------
// Device card
// ---------------------------------------------------------------------------

function DeviceCard({ device }: { device: DeviceInfo }) {
  const tag = TAG_STYLES[device.connection];

  return (
    <motion.div
      className="relative text-center transition-all duration-300 hover:shadow-[0_0_20px_rgba(251,146,60,0.08)]"
      style={{
        background: "rgba(24,24,27,0.7)",
        border: "1px solid rgba(63,63,70,0.3)",
        borderRadius: 12,
        padding: 16,
      }}
      {...fadeInUp(0.2 + device.delay * 0.3)}
    >
      {/* Status dot */}
      <motion.div
        className="absolute rounded-full"
        style={{
          top: 8,
          right: 8,
          width: 6,
          height: 6,
          background: tag.dotColor,
          boxShadow: tag.dotShadow,
        }}
        animate={{ scale: [1, 1.3, 1], opacity: [0.5, 1, 0.5] }}
        transition={{
          duration: 2,
          delay: device.delay,
          repeat: Infinity,
          ease: "easeInOut",
        }}
      />

      <div className="text-[28px] mb-2">{device.icon}</div>
      <div className="text-[11px] text-zinc-400 font-medium mb-1">
        {device.name}
      </div>
      <div
        className="text-zinc-600"
        style={{
          fontSize: 9,
          fontFamily: "'SF Mono','Fira Code',monospace",
        }}
      >
        {device.os}
      </div>
      <span
        className="inline-block mt-2 font-semibold uppercase"
        style={{
          fontSize: 8,
          letterSpacing: 1,
          padding: "2px 6px",
          borderRadius: 4,
          color: tag.color,
          background: tag.background,
          border: tag.border,
        }}
      >
        {device.connection}
      </span>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// CLI panel
// ---------------------------------------------------------------------------

function CliPanel() {
  return (
    <motion.div
      className="w-full max-w-[480px] mx-auto"
      style={{
        background: "rgba(24,24,27,0.7)",
        border: "1px solid rgba(63,63,70,0.3)",
        borderRadius: 10,
        padding: "14px 16px",
        fontFamily: "'SF Mono','Fira Code',monospace",
        fontSize: 11,
        lineHeight: 1.8,
      }}
      {...fadeInUp(0.7)}
    >
      <div className="text-zinc-700">$ Discover all connected devices</div>
      <div>
        <span className="text-zinc-400">remo</span>{" "}
        <span className="text-emerald-400">devices</span>
      </div>
      <div className="mt-1.5">
        <span className="text-emerald-400">●</span>{" "}
        <span className="text-zinc-400">iPhone 17 Pro</span>{" "}
        <span style={{ color: "#fb923c" }}>USB</span>{" "}
        <span className="text-zinc-700">· iOS 18.4 · 1170×2532</span>
      </div>
      <div>
        <span className="text-emerald-400">●</span>{" "}
        <span className="text-zinc-400">iPad Air (M3)</span>{" "}
        <span style={{ color: "#fb923c" }}>USB</span>{" "}
        <span className="text-zinc-700">· iPadOS 18.4 · 2360×1640</span>
      </div>
      <div>
        <span className="text-emerald-400">●</span>{" "}
        <span className="text-zinc-400">iPhone 16 Sim</span>{" "}
        <span style={{ color: "#a78bfa" }}>Bonjour</span>{" "}
        <span className="text-zinc-700">· iOS 18.0 · 1170×2532</span>
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// DeviceDiscoverySection
// ---------------------------------------------------------------------------

export function DeviceDiscoverySection() {
  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(251,146,60,0.07)"
        secondary="rgba(167,139,250,0.05)"
        primaryPos="50% 35%"
        secondaryPos="35% 60%"
      />
      <FloatingParticles
        particles={[
          { top: "20%", left: "15%", color: "#fb923c", duration: 6, delay: 0 },
          { top: "55%", left: "80%", color: "#a78bfa", duration: 8, delay: 2 },
          { top: "80%", left: "22%", color: "#fb923c", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="Multi-Device Discovery"
        labelColor="#fb923c"
        title="Plug in and go"
        subtitle="USB for physical devices, Bonjour for simulators. Agents find every device automatically — no configuration needed."
      />

      <div className="relative z-10 flex flex-col items-center gap-6 w-full">
        {/* Device grid */}
        <div
          className="grid gap-3 w-full max-w-[480px]"
          style={{ gridTemplateColumns: "repeat(3, 1fr)" }}
        >
          {DEVICES.map((d) => (
            <DeviceCard key={d.name} device={d} />
          ))}
        </div>

        {/* CLI */}
        <CliPanel />
      </div>
    </ShowcaseSection>
  );
}
```

- [ ] **Step 2: Verify the build**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/showcase-website/website && npx tsc --noEmit && npm run build
```

Expected: no TypeScript errors, build succeeds.

- [ ] **Step 3: Commit**

```bash
git add website/src/components/FeatureShowcase/DeviceDiscoverySection.tsx
git commit -m "feat(showcase): add Multi-Device Discovery section with card grid"
```

---

### Task 4: Dynamic Registration Section

**Files:**
- Create: `website/src/components/FeatureShowcase/DynamicRegistrationSection.tsx`

**Context:** Horizontal layout: two phone wireframes (Home vs Detail) with capability lists, connected by navigation arrow. Event panel below. Accent teal (`#2dd4bf`) + violet (`#a78bfa`). Refer to spec Section 6.

- [ ] **Step 1: Create DynamicRegistrationSection.tsx**

```tsx
import { motion } from "framer-motion";
import {
  ShowcaseSection,
  SectionHeader,
  NoiseOverlay,
  AmbientLight,
  FloatingParticles,
  fadeInLeft,
  fadeInRight,
  fadeInUp,
  fadeIn,
} from "./shared";

// ---------------------------------------------------------------------------
// Capability chip
// ---------------------------------------------------------------------------

interface CapChipProps {
  name: string;
  active: boolean;
  accentColor: string;
  glowColor: string;
}

function CapChip({ name, active, accentColor, glowColor }: CapChipProps) {
  return (
    <div
      className="flex items-center gap-1.5"
      style={{
        padding: "5px 10px",
        borderRadius: 6,
        fontSize: 10,
        fontFamily: "'SF Mono','Fira Code',monospace",
        border: active
          ? `1px solid ${glowColor}`
          : "1px dashed rgba(63,63,70,0.3)",
        background: active ? `${glowColor.replace("0.3", "0.06")}` : "rgba(24,24,27,0.5)",
        opacity: active ? 1 : 0.35,
        boxShadow: active ? `0 0 12px ${glowColor.replace("0.3", "0.08")}` : "none",
      }}
    >
      <div
        className="rounded-full flex-shrink-0"
        style={{
          width: 5,
          height: 5,
          background: active ? accentColor : "#3f3f46",
          boxShadow: active ? `0 0 6px ${accentColor}` : "none",
        }}
      />
      <span style={{ color: active ? accentColor : "#52525b" }}>{name}</span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Phone wireframe (simplified, no hover interaction)
// ---------------------------------------------------------------------------

function PhoneMock({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="relative flex-shrink-0"
      style={{ width: 130, height: 260, borderRadius: 22 }}
    >
      <div
        className="absolute inset-0 overflow-hidden"
        style={{
          borderRadius: 22,
          border: "1.5px solid rgba(113,113,122,0.4)",
          background: "rgba(9,9,11,0.8)",
        }}
      >
        {/* Notch */}
        <div
          className="absolute top-[5px] left-1/2 -translate-x-1/2 z-10"
          style={{
            width: 36,
            height: 12,
            background: "#09090b",
            borderRadius: "0 0 8px 8px",
          }}
        />

        {/* Screen */}
        <div
          className="absolute overflow-hidden"
          style={{
            left: "4%",
            right: "4%",
            top: "2.5%",
            bottom: "2.5%",
            borderRadius: 18,
            background: "linear-gradient(180deg, #18181b, #1c1c20)",
          }}
        >
          {children}
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Home screen content
// ---------------------------------------------------------------------------

function HomeScreen() {
  return (
    <div className="flex flex-col h-full">
      {/* Nav */}
      <div
        className="flex items-center justify-center border-b"
        style={{
          height: 28,
          background: "rgba(63,63,70,0.2)",
          borderColor: "rgba(63,63,70,0.15)",
        }}
      >
        <span className="text-zinc-500" style={{ fontSize: 7 }}>
          My App
        </span>
      </div>

      {/* List rows */}
      <div className="flex-1 p-2 pt-3 flex flex-col gap-1">
        {[60, 90, 75, 90, 80, 85, 90, 70].map((w, i) => (
          <div
            key={i}
            className="rounded bg-zinc-700/15"
            style={{ height: 12, width: `${w}%` }}
          />
        ))}
      </div>

      {/* Bottom label */}
      <div className="text-center pb-2" style={{ fontSize: 8, color: "#52525b" }}>
        List View
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Detail screen content
// ---------------------------------------------------------------------------

function DetailScreen() {
  return (
    <div className="flex flex-col h-full">
      {/* Nav */}
      <div
        className="flex items-center border-b px-2"
        style={{
          height: 28,
          background: "rgba(63,63,70,0.2)",
          borderColor: "rgba(63,63,70,0.15)",
        }}
      >
        <div className="flex gap-1">
          <div className="w-1 h-1 rounded-full bg-zinc-600" />
          <div className="w-1 h-1 rounded-full bg-zinc-600" />
        </div>
        <span
          className="text-zinc-500 mx-auto"
          style={{ fontSize: 7 }}
        >
          Detail
        </span>
      </div>

      {/* Content */}
      <div className="flex-1 p-2 pt-3 flex flex-col items-center">
        <div
          className="mb-2"
          style={{
            width: 48,
            height: 48,
            borderRadius: 8,
            background: "rgba(167,139,250,0.1)",
            border: "1px solid rgba(167,139,250,0.2)",
          }}
        />
        <div
          className="rounded bg-zinc-700/20 mb-2 mx-auto"
          style={{ height: 10, width: "50%" }}
        />
        {[90, 85, 70].map((w, i) => (
          <div
            key={i}
            className="rounded bg-zinc-700/15 mb-1 w-full"
            style={{ height: 10, width: `${w}%` }}
          />
        ))}
        <div
          className="mt-2 flex items-center justify-center rounded-lg"
          style={{
            width: "80%",
            height: 16,
            fontSize: 6,
            fontWeight: 500,
            color: "#a78bfa",
            background: "rgba(167,139,250,0.2)",
            border: "1px solid rgba(167,139,250,0.3)",
          }}
        >
          Edit
        </div>
      </div>

      {/* Bottom label */}
      <div className="text-center pb-2" style={{ fontSize: 8, color: "#52525b" }}>
        Detail View
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Navigation arrow
// ---------------------------------------------------------------------------

function NavigationArrow() {
  return (
    <div className="flex flex-col items-center gap-1.5 mx-2 self-center">
      <AnimatedVerticalLine />
      <span
        style={{
          fontSize: 8,
          textTransform: "uppercase",
          letterSpacing: 1.5,
          color: "#52525b",
          writingMode: "vertical-rl",
          textOrientation: "mixed",
        }}
      >
        navigate
      </span>
      <AnimatedVerticalLine />
    </div>
  );
}

function AnimatedVerticalLine() {
  return (
    <div
      className="relative overflow-hidden"
      style={{ width: 1.5, height: 60, background: "rgba(63,63,70,0.3)", borderRadius: 1 }}
    >
      <motion.div
        className="absolute left-0 w-full"
        style={{
          height: "60%",
          borderRadius: 1,
          background:
            "linear-gradient(180deg, transparent, #2dd4bf, #a78bfa, transparent)",
        }}
        animate={{ top: ["-60%", "100%"] }}
        transition={{ duration: 2, ease: "easeInOut", repeat: Infinity }}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Event panel
// ---------------------------------------------------------------------------

function EventPanel() {
  return (
    <motion.div
      className="w-full max-w-[520px] mx-auto"
      style={{
        background: "rgba(24,24,27,0.7)",
        border: "1px solid rgba(63,63,70,0.3)",
        borderRadius: 10,
        padding: "12px 16px",
        fontFamily: "'SF Mono','Fira Code',monospace",
        fontSize: 10,
        lineHeight: 1.8,
      }}
      {...fadeInUp(0.6)}
    >
      <div className="text-zinc-700">
        {"// Agent receives real-time notification"}
      </div>
      <div>
        <span style={{ color: "#2dd4bf" }}>capabilities_changed</span>{" "}
        <span className="text-zinc-400">{"{"}</span>
      </div>
      <div className="pl-4">
        <span className="text-emerald-400">+ detail.getInfo</span>
      </div>
      <div className="pl-4">
        <span className="text-emerald-400">+ detail.edit</span>
      </div>
      <div className="pl-4">
        <span style={{ color: "#ef4444" }}>− list.scroll</span>
      </div>
      <div className="pl-4">
        <span style={{ color: "#ef4444" }}>− app.refresh</span>
      </div>
      <div>
        <span className="text-zinc-400">{"}"}</span>
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// DynamicRegistrationSection
// ---------------------------------------------------------------------------

const HOME_CAPS = [
  { name: "app.refresh", active: true },
  { name: "list.scroll", active: true },
  { name: "detail.getInfo", active: false },
  { name: "detail.edit", active: false },
];

const DETAIL_CAPS = [
  { name: "app.refresh", active: false },
  { name: "list.scroll", active: false },
  { name: "detail.getInfo", active: true },
  { name: "detail.edit", active: true },
];

export function DynamicRegistrationSection() {
  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(45,212,191,0.07)"
        secondary="rgba(167,139,250,0.05)"
        primaryPos="40% 35%"
        secondaryPos="60% 60%"
      />
      <FloatingParticles
        particles={[
          { top: "20%", left: "18%", color: "#2dd4bf", duration: 6, delay: 0 },
          { top: "55%", left: "80%", color: "#a78bfa", duration: 8, delay: 2 },
          { top: "82%", left: "25%", color: "#2dd4bf", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="Dynamic Registration"
        labelColor="#2dd4bf"
        title="Capabilities follow the UI"
        subtitle="Register on appear, unregister on disappear. Agents always see exactly what's available on the current screen."
      />

      <div className="relative z-10 flex flex-col items-center gap-5 w-full max-w-[960px]">
        {/* Phone columns */}
        <div className="flex items-start gap-0 justify-center">
          {/* Home column */}
          <motion.div
            className="flex flex-col items-center gap-3"
            {...fadeInLeft(0.2)}
          >
            <div
              className="font-semibold uppercase"
              style={{
                fontSize: 10,
                letterSpacing: 2,
                color: "#2dd4bf",
              }}
            >
              Home Screen
            </div>
            <PhoneMock>
              <HomeScreen />
            </PhoneMock>
            <div className="flex flex-col gap-1.5">
              {HOME_CAPS.map((c) => (
                <CapChip
                  key={c.name}
                  name={c.name}
                  active={c.active}
                  accentColor="#2dd4bf"
                  glowColor="rgba(45,212,191,0.3)"
                />
              ))}
            </div>
          </motion.div>

          {/* Navigation arrow */}
          <motion.div {...fadeIn(0.4)}>
            <NavigationArrow />
          </motion.div>

          {/* Detail column */}
          <motion.div
            className="flex flex-col items-center gap-3"
            {...fadeInRight(0.3)}
          >
            <div
              className="font-semibold uppercase"
              style={{
                fontSize: 10,
                letterSpacing: 2,
                color: "#a78bfa",
              }}
            >
              Detail Screen
            </div>
            <PhoneMock>
              <DetailScreen />
            </PhoneMock>
            <div className="flex flex-col gap-1.5">
              {DETAIL_CAPS.map((c) => (
                <CapChip
                  key={c.name}
                  name={c.name}
                  active={c.active}
                  accentColor={c.active ? "#a78bfa" : "#2dd4bf"}
                  glowColor={
                    c.active
                      ? "rgba(167,139,250,0.3)"
                      : "rgba(45,212,191,0.3)"
                  }
                />
              ))}
            </div>
          </motion.div>
        </div>

        {/* Event panel */}
        <EventPanel />
      </div>
    </ShowcaseSection>
  );
}
```

- [ ] **Step 2: Verify the build**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/showcase-website/website && npx tsc --noEmit && npm run build
```

Expected: no TypeScript errors, build succeeds.

- [ ] **Step 3: Commit**

```bash
git add website/src/components/FeatureShowcase/DynamicRegistrationSection.tsx
git commit -m "feat(showcase): add Dynamic Registration section with dual-screen capability diff"
```

---

### Task 5: Integrate All Sections and Reorder

**Files:**
- Modify: `website/src/components/FeatureShowcase/FeatureShowcase.tsx`

**Context:** Update the wrapper component to import all 6 sections and render them in the correct order: Capability → View Tree → Screenshot → Video → Discovery → Dynamic Registration.

- [ ] **Step 1: Update FeatureShowcase.tsx**

Replace the entire file content with:

```tsx
import { CapabilitySection } from "./CapabilitySection";
import { ViewTreeSection } from "./ViewTreeSection";
import { ScreenshotSection } from "./ScreenshotSection";
import { VideoStreamSection } from "./VideoStreamSection";
import { DeviceDiscoverySection } from "./DeviceDiscoverySection";
import { DynamicRegistrationSection } from "./DynamicRegistrationSection";

export function FeatureShowcase() {
  return (
    <>
      <CapabilitySection />
      <ViewTreeSection />
      <ScreenshotSection />
      <VideoStreamSection />
      <DeviceDiscoverySection />
      <DynamicRegistrationSection />
    </>
  );
}
```

- [ ] **Step 2: Verify the build**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/showcase-website/website && npx tsc --noEmit && npm run build
```

Expected: no TypeScript errors, build succeeds.

- [ ] **Step 3: Visual verification**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/showcase-website/website && npm run dev
```

Open the dev server URL and scroll through all 6 sections. Verify:
1. Sections appear in order: Capability → View Tree → Screenshot → Video → Discovery → Dynamic Registration
2. Each section occupies full viewport height
3. Scroll-triggered entrance animations fire correctly
4. Shutter flash + captured badge pulse on Screenshot section
5. REC dot blinks and waveform bars pulse on Video section
6. Status dots pulse on device cards in Discovery section
7. Navigation arrow gradient flows in Dynamic Registration section
8. Ambient lighting and floating particles visible on each section

- [ ] **Step 4: Commit**

```bash
git add website/src/components/FeatureShowcase/FeatureShowcase.tsx
git commit -m "feat(showcase): integrate all 6 sections, reorder with Capability first"
```
