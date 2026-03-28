# Premium Capability Showcase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat feature card grid with 2 full-viewport, scroll-animated showcase sections (View Tree Inspection + Capability Invocation) using an Apple-product-page visual style.

**Architecture:** A `FeatureShowcase/` component directory with shared primitives (SectionHeader, GlassPanel, ambient effects) composed into two section-level components. Each section is a standalone full-viewport block with scroll-triggered Framer Motion entrance animations. The existing `FeaturesSection.tsx` is deleted and replaced in `App.tsx`.

**Tech Stack:** React 19, TypeScript, Tailwind CSS 4, Framer Motion 12

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `src/components/FeatureShowcase/shared.tsx` | Reusable primitives: ShowcaseSection, SectionHeader, GlassPanel, NoiseOverlay, AmbientLight, FloatingParticles, GradientConnector |
| Create | `src/components/FeatureShowcase/PhoneWireframe.tsx` | Schematic phone outline with UI element slots, scan line, hover state |
| Create | `src/components/FeatureShowcase/ViewTreeSection.tsx` | View Tree Inspection full-viewport section |
| Create | `src/components/FeatureShowcase/CapabilitySection.tsx` | Capability Invocation full-viewport section |
| Create | `src/components/FeatureShowcase/FeatureShowcase.tsx` | Wrapper composing both sections |
| Modify | `src/App.tsx:4,17` | Swap FeaturesSection import/usage for FeatureShowcase |
| Delete | `src/components/FeaturesSection.tsx` | Replaced by FeatureShowcase |

---

### Task 1: Shared Primitives

**Files:**
- Create: `website/src/components/FeatureShowcase/shared.tsx`

- [ ] **Step 1: Create shared.tsx with all reusable components**

```tsx
import { type ReactNode } from "react";
import { motion } from "framer-motion";

// ---------------------------------------------------------------------------
// Animation constants
// ---------------------------------------------------------------------------

const EASE = [0.25, 0.4, 0.25, 1] as const;

export const fadeInUp = (delay = 0) => ({
  initial: { opacity: 0, y: 30 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, amount: 0.3 },
  transition: { duration: 0.7, delay, ease: EASE },
});

export const fadeInLeft = (delay = 0) => ({
  initial: { opacity: 0, x: -30 },
  whileInView: { opacity: 1, x: 0 },
  viewport: { once: true, amount: 0.3 },
  transition: { duration: 0.7, delay, ease: EASE },
});

export const fadeInRight = (delay = 0) => ({
  initial: { opacity: 0, x: 30 },
  whileInView: { opacity: 1, x: 0 },
  viewport: { once: true, amount: 0.3 },
  transition: { duration: 0.7, delay, ease: EASE },
});

export const fadeIn = (delay = 0) => ({
  initial: { opacity: 0 },
  whileInView: { opacity: 1 },
  viewport: { once: true, amount: 0.3 },
  transition: { duration: 0.5, delay, ease: EASE },
});

// ---------------------------------------------------------------------------
// ShowcaseSection — full-viewport wrapper
// ---------------------------------------------------------------------------

export function ShowcaseSection({ children }: { children: ReactNode }) {
  return (
    <section className="relative min-h-screen flex flex-col items-center justify-center px-10 py-20 overflow-hidden">
      {children}
    </section>
  );
}

// ---------------------------------------------------------------------------
// SectionHeader — label + gradient title + subtitle
// ---------------------------------------------------------------------------

interface SectionHeaderProps {
  label: string;
  labelColor: string;
  title: string;
  subtitle: string;
}

export function SectionHeader({
  label,
  labelColor,
  title,
  subtitle,
}: SectionHeaderProps) {
  return (
    <motion.div className="text-center mb-16" {...fadeInUp(0)}>
      <p
        className="text-[11px] font-semibold uppercase tracking-[3px] mb-4"
        style={{ color: labelColor }}
      >
        {label}
      </p>
      <h2 className="text-4xl md:text-[48px] font-bold tracking-[-1.5px] leading-[1.1] bg-gradient-to-b from-white to-zinc-400 bg-clip-text text-transparent">
        {title}
      </h2>
      <p className="text-[17px] text-zinc-500 mt-3 max-w-[520px] mx-auto leading-relaxed">
        {subtitle}
      </p>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// GlassPanel — glassmorphism code panel with colored top-edge glow
// ---------------------------------------------------------------------------

interface GlassPanelProps {
  children: ReactNode;
  glowColor: string;
  className?: string;
}

export function GlassPanel({ children, glowColor, className }: GlassPanelProps) {
  return (
    <div
      className={`relative rounded-2xl p-6 md:p-7 font-mono text-[13px] leading-[1.9] overflow-hidden ${className ?? ""}`}
      style={{
        background: "rgba(24,24,27,0.5)",
        backdropFilter: "blur(20px)",
        border: "1px solid rgba(63,63,70,0.4)",
        boxShadow:
          "0 0 0 1px rgba(255,255,255,0.03), 0 16px 48px rgba(0,0,0,0.4)",
      }}
    >
      {/* Top-edge glow */}
      <div
        className="absolute top-[-1px] left-[15%] right-[15%] h-px"
        style={{
          background: `linear-gradient(90deg, transparent, ${glowColor}, transparent)`,
        }}
      />
      {children}
    </div>
  );
}

// ---------------------------------------------------------------------------
// NoiseOverlay — SVG fractalNoise film grain
// ---------------------------------------------------------------------------

const NOISE_SVG =
  "url(\"data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")";

export function NoiseOverlay() {
  return (
    <div
      className="absolute inset-0 pointer-events-none opacity-[0.03]"
      style={{ backgroundImage: NOISE_SVG }}
    />
  );
}

// ---------------------------------------------------------------------------
// AmbientLight — dual radial gradients
// ---------------------------------------------------------------------------

interface AmbientLightProps {
  primary: string; // e.g. "rgba(139,92,246,0.08)"
  secondary: string;
  primaryPos?: string; // e.g. "35% 40%"
  secondaryPos?: string;
}

export function AmbientLight({
  primary,
  secondary,
  primaryPos = "35% 40%",
  secondaryPos = "65% 55%",
}: AmbientLightProps) {
  return (
    <div
      className="absolute inset-0 pointer-events-none"
      style={{
        background: `radial-gradient(ellipse 600px 400px at ${primaryPos}, ${primary} 0%, transparent 100%), radial-gradient(ellipse 500px 300px at ${secondaryPos}, ${secondary} 0%, transparent 100%)`,
      }}
    />
  );
}

// ---------------------------------------------------------------------------
// FloatingParticles — 3 animated dots
// ---------------------------------------------------------------------------

interface ParticleConfig {
  top: string;
  left: string;
  color: string;
  duration: number;
  delay: number;
}

export function FloatingParticles({
  particles,
}: {
  particles: ParticleConfig[];
}) {
  return (
    <>
      {particles.map((p, i) => (
        <motion.div
          key={i}
          className="absolute w-[2px] h-[2px] rounded-full"
          style={{ top: p.top, left: p.left, background: p.color }}
          animate={{
            y: [0, -20, 0],
            scale: [1, 1.5, 1],
            opacity: [0.3, 0.6, 0.3],
          }}
          transition={{
            duration: p.duration,
            delay: p.delay,
            repeat: Infinity,
            ease: "easeInOut",
          }}
        />
      ))}
    </>
  );
}

// ---------------------------------------------------------------------------
// GradientConnector — animated vertical line between panels
// ---------------------------------------------------------------------------

interface GradientConnectorProps {
  fromColor: string;
  toColor: string;
  height?: number;
}

export function GradientConnector({
  fromColor,
  toColor,
  height = 48,
}: GradientConnectorProps) {
  return (
    <div
      className="relative overflow-hidden mx-auto"
      style={{ width: 1.5, height }}
    >
      <div
        className="absolute inset-0 rounded-sm"
        style={{ background: "rgba(63,63,70,0.2)" }}
      />
      <motion.div
        className="absolute left-0 w-full rounded-sm"
        style={{
          height: "60%",
          background: `linear-gradient(180deg, transparent, ${fromColor}, ${toColor}, transparent)`,
        }}
        animate={{ top: ["-60%", "100%"] }}
        transition={{ duration: 2, ease: "easeInOut", repeat: Infinity }}
      />
    </div>
  );
}
```

- [ ] **Step 2: Verify build compiles**

Run: `cd website && npx tsc --noEmit`
Expected: No errors (file has no consumers yet but must type-check).

- [ ] **Step 3: Commit**

```bash
git add website/src/components/FeatureShowcase/shared.tsx
git commit -m "feat(showcase): add shared design system primitives"
```

---

### Task 2: Phone Wireframe Component

**Files:**
- Create: `website/src/components/FeatureShowcase/PhoneWireframe.tsx`

- [ ] **Step 1: Create PhoneWireframe.tsx**

```tsx
import { motion } from "framer-motion";

// UI element IDs used for bidirectional hover linking with JSON panel
export type ElementId =
  | "window"
  | "nav"
  | "content"
  | "text"
  | "button"
  | "list"
  | "list-1"
  | "list-2"
  | "list-3"
  | "tab";

interface PhoneWireframeProps {
  hoveredId: ElementId | null;
  onHover: (id: ElementId | null) => void;
}

function UiElement({
  id,
  hoveredId,
  onHover,
  label,
  className,
  children,
}: {
  id: ElementId;
  hoveredId: ElementId | null;
  onHover: (id: ElementId | null) => void;
  label: string;
  className?: string;
  children?: React.ReactNode;
}) {
  const isHovered = hoveredId === id;

  return (
    <div
      className={`relative flex items-center justify-center rounded-lg text-[10px] font-medium tracking-wide transition-all duration-300 cursor-default ${className ?? ""}`}
      style={{
        border: `1px dashed rgba(139,92,246,${isHovered ? 0.6 : 0.25})`,
        color: `rgba(139,92,246,${isHovered ? 0.9 : 0.5})`,
        background: `rgba(139,92,246,${isHovered ? 0.08 : 0.04})`,
        boxShadow: isHovered
          ? "0 0 20px rgba(139,92,246,0.15), inset 0 0 20px rgba(139,92,246,0.05)"
          : "none",
      }}
      onMouseEnter={() => onHover(id)}
      onMouseLeave={() => onHover(null)}
    >
      {children ?? label}
    </div>
  );
}

export function PhoneWireframe({ hoveredId, onHover }: PhoneWireframeProps) {
  return (
    <div
      className="relative flex flex-col gap-1.5 flex-shrink-0"
      style={{
        width: 220,
        height: 440,
        borderRadius: 36,
        border: "1.5px solid rgba(63,63,70,0.6)",
        padding: "16px 12px",
        background: "rgba(24,24,27,0.4)",
        backdropFilter: "blur(20px)",
        boxShadow:
          "0 0 0 1px rgba(255,255,255,0.03), 0 20px 60px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.05)",
      }}
    >
      {/* Notch */}
      <div
        className="absolute top-2 left-1/2 -translate-x-1/2 rounded-[10px]"
        style={{
          width: 60,
          height: 20,
          background: "rgba(9,9,11,0.8)",
          border: "1px solid rgba(63,63,70,0.4)",
        }}
      />

      {/* Scan line */}
      <motion.div
        className="absolute left-0 right-0 h-[2px] pointer-events-none"
        style={{
          background:
            "linear-gradient(90deg, transparent 0%, #8b5cf6 30%, #c084fc 50%, #8b5cf6 70%, transparent 100%)",
          boxShadow:
            "0 0 20px rgba(139,92,246,0.6), 0 0 60px rgba(139,92,246,0.3)",
        }}
        animate={{ top: ["5%", "95%"], opacity: [0, 0.8, 0.8, 0] }}
        transition={{
          duration: 3,
          ease: "easeInOut",
          repeat: Infinity,
          times: [0, 0.1, 0.9, 1],
        }}
      />

      {/* NavigationBar */}
      <UiElement
        id="nav"
        hoveredId={hoveredId}
        onHover={onHover}
        label="NavigationBar"
        className="h-[42px] mt-5"
      />

      {/* ContentView */}
      <UiElement
        id="content"
        hoveredId={hoveredId}
        onHover={onHover}
        label="ContentView"
        className="h-[160px] flex-col gap-1"
      >
        <span className="text-[10px]" style={{ color: "inherit" }}>
          ContentView
        </span>
        <div className="flex flex-col gap-1 w-[80%]">
          <div
            className="h-[22px] rounded flex items-center justify-center text-[8px] cursor-default transition-all duration-300"
            style={{
              border: `1px dashed rgba(167,139,250,${hoveredId === "text" ? 0.5 : 0.2})`,
              color: `rgba(167,139,250,${hoveredId === "text" ? 0.8 : 0.4})`,
              background: `rgba(167,139,250,${hoveredId === "text" ? 0.06 : 0})`,
            }}
            onMouseEnter={() => onHover("text")}
            onMouseLeave={() => onHover(null)}
          >
            Text "Counter: 3"
          </div>
          <div
            className="h-[22px] rounded flex items-center justify-center text-[8px] cursor-default transition-all duration-300"
            style={{
              border: `1px dashed rgba(167,139,250,${hoveredId === "button" ? 0.5 : 0.2})`,
              color: `rgba(167,139,250,${hoveredId === "button" ? 0.8 : 0.4})`,
              background: `rgba(167,139,250,${hoveredId === "button" ? 0.06 : 0})`,
            }}
            onMouseEnter={() => onHover("button")}
            onMouseLeave={() => onHover(null)}
          >
            Button "Increment"
          </div>
        </div>
      </UiElement>

      {/* List */}
      <UiElement
        id="list"
        hoveredId={hoveredId}
        onHover={onHover}
        label=""
        className="h-[100px] flex-col gap-0.5"
      >
        {(["list-1", "list-2", "list-3"] as const).map((id, i) => (
          <div
            key={id}
            className="w-[90%] h-[24px] rounded flex items-center pl-2 text-[8px] cursor-default transition-all duration-300"
            style={{
              border: `1px dashed rgba(167,139,250,${hoveredId === id ? 0.5 : 0.15})`,
              color: `rgba(167,139,250,${hoveredId === id ? 0.7 : 0.3})`,
            }}
            onMouseEnter={() => onHover(id)}
            onMouseLeave={() => onHover(null)}
          >
            ▸ Item {i + 1}
          </div>
        ))}
      </UiElement>

      {/* TabBar */}
      <UiElement
        id="tab"
        hoveredId={hoveredId}
        onHover={onHover}
        label="TabBar"
        className="h-[44px]"
      />
    </div>
  );
}
```

- [ ] **Step 2: Verify build**

Run: `cd website && npx tsc --noEmit`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add website/src/components/FeatureShowcase/PhoneWireframe.tsx
git commit -m "feat(showcase): add phone wireframe component with hover interaction"
```

---

### Task 3: View Tree Inspection Section

**Files:**
- Create: `website/src/components/FeatureShowcase/ViewTreeSection.tsx`

- [ ] **Step 1: Create ViewTreeSection.tsx**

```tsx
import { useState } from "react";
import { motion } from "framer-motion";
import {
  ShowcaseSection,
  SectionHeader,
  GlassPanel,
  NoiseOverlay,
  AmbientLight,
  FloatingParticles,
  fadeInLeft,
  fadeInRight,
  fadeIn,
} from "./shared";
import { PhoneWireframe, type ElementId } from "./PhoneWireframe";

// Map element IDs to JSON line indices for hover highlighting
const ELEMENT_LINES: Record<string, number[]> = {
  window: [0, 1, 2, 10, 11],
  nav: [],
  content: [3, 4, 5, 6, 9],
  text: [7],
  button: [8],
  list: [],
  "list-1": [],
  "list-2": [],
  "list-3": [],
  tab: [],
};

interface JsonLine {
  indent: number;
  content: React.ReactNode;
  elementId?: ElementId;
}

function buildJsonLines(): JsonLine[] {
  const k = (s: string) => <span className="text-violet-300">{s}</span>;
  const s = (v: string) => <span className="text-emerald-400">{v}</span>;
  const n = (v: string) => <span className="text-amber-400">{v}</span>;
  const b = (v: string) => <span className="text-zinc-600">{v}</span>;

  return [
    { indent: 0, content: b("{"), elementId: "window" },
    {
      indent: 1,
      content: <>{k('"type"')}: {s('"UIWindow"')},</>,
      elementId: "window",
    },
    {
      indent: 1,
      content: <>{k('"frame"')}: {b("{")} {n("0")}, {n("0")}, {n("390")}, {n("844")} {b("}")},</>,
      elementId: "window",
    },
    {
      indent: 1,
      content: <>{k('"children"')}: {b("[{")}</>,
      elementId: "content",
    },
    {
      indent: 2,
      content: <>{k('"type"')}: {s('"ContentView"')},</>,
      elementId: "content",
    },
    {
      indent: 2,
      content: <>{k('"frame"')}: {b("{")} {n("0")}, {n("91")}, {n("390")}, {n("663")} {b("}")},</>,
      elementId: "content",
    },
    {
      indent: 2,
      content: <>{k('"children"')}: {b("[")}</>,
      elementId: "content",
    },
    {
      indent: 3,
      content: <>{b("{")} {k('"type"')}: {s('"Text"')}, {k('"value"')}: {s('"Counter: 3"')} {b("}")},</>,
      elementId: "text",
    },
    {
      indent: 3,
      content: <>{b("{")} {k('"type"')}: {s('"Button"')}, {k('"label"')}: {s('"Increment"')} {b("}")}</>,
      elementId: "button",
    },
    { indent: 2, content: b("]"), elementId: "content" },
    { indent: 1, content: b("}]"), elementId: "window" },
    { indent: 0, content: b("}"), elementId: "window" },
  ];
}

function ConnectionBeam() {
  return (
    <div className="flex flex-col items-center gap-1.5 flex-shrink-0">
      <BeamLine />
      <span className="text-[9px] uppercase tracking-[2px] text-zinc-600 font-medium">
        remo tree
      </span>
      <BeamLine />
    </div>
  );
}

function BeamLine() {
  return (
    <div
      className="relative overflow-hidden rounded-sm"
      style={{ width: 80, height: 1.5, background: "rgba(63,63,70,0.3)" }}
    >
      <motion.div
        className="absolute top-0 h-full rounded-sm"
        style={{
          width: "60%",
          background:
            "linear-gradient(90deg, transparent, #8b5cf6, #34d399, transparent)",
        }}
        animate={{ left: ["-60%", "100%"] }}
        transition={{ duration: 2, ease: "easeInOut", repeat: Infinity }}
      />
    </div>
  );
}

export function ViewTreeSection() {
  const [hoveredId, setHoveredId] = useState<ElementId | null>(null);
  const jsonLines = buildJsonLines();

  // Which line indices should highlight
  const highlightedLines = hoveredId ? (ELEMENT_LINES[hoveredId] ?? []) : [];

  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(139,92,246,0.08)"
        secondary="rgba(52,211,153,0.06)"
      />
      <FloatingParticles
        particles={[
          { top: "20%", left: "15%", color: "#8b5cf6", duration: 6, delay: 0 },
          { top: "60%", left: "80%", color: "#34d399", duration: 8, delay: 2 },
          { top: "80%", left: "25%", color: "#8b5cf6", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="View Tree Inspection"
        labelColor="#8b5cf6"
        title="See what your agent sees"
        subtitle="Every UIView, every frame, every property — structured as JSON that agents can parse and reason about."
      />

      {/* Demo stage */}
      <div className="relative z-10 flex items-center gap-12 justify-center w-full max-w-[960px]">
        {/* Phone */}
        <motion.div {...fadeInLeft(0.2)}>
          <PhoneWireframe hoveredId={hoveredId} onHover={setHoveredId} />
        </motion.div>

        {/* Beam */}
        <motion.div {...fadeIn(0.6)}>
          <ConnectionBeam />
        </motion.div>

        {/* JSON */}
        <motion.div {...fadeInRight(0.4)} className="flex-1 min-w-0 max-w-[380px]">
          <GlassPanel glowColor="rgba(139,92,246,0.5)">
            {jsonLines.map((line, i) => (
              <div
                key={i}
                className="whitespace-nowrap transition-all duration-200 rounded px-1 -mx-1 cursor-default"
                style={{
                  paddingLeft: line.indent * 16,
                  background: highlightedLines.includes(i)
                    ? "rgba(139,92,246,0.08)"
                    : "transparent",
                  boxShadow: highlightedLines.includes(i)
                    ? "inset 2px 0 0 #8b5cf6"
                    : "none",
                }}
                onMouseEnter={() => line.elementId && setHoveredId(line.elementId)}
                onMouseLeave={() => setHoveredId(null)}
              >
                {line.content}
              </div>
            ))}
          </GlassPanel>
        </motion.div>
      </div>
    </ShowcaseSection>
  );
}
```

- [ ] **Step 2: Verify build**

Run: `cd website && npx tsc --noEmit`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add website/src/components/FeatureShowcase/ViewTreeSection.tsx
git commit -m "feat(showcase): add View Tree Inspection section with phone-to-JSON demo"
```

---

### Task 4: Capability Invocation Section

**Files:**
- Create: `website/src/components/FeatureShowcase/CapabilitySection.tsx`

- [ ] **Step 1: Create CapabilitySection.tsx**

```tsx
import { motion } from "framer-motion";
import {
  ShowcaseSection,
  SectionHeader,
  GlassPanel,
  NoiseOverlay,
  AmbientLight,
  FloatingParticles,
  GradientConnector,
  fadeInUp,
  fadeIn,
} from "./shared";

// ---------------------------------------------------------------------------
// StatusChip — colored dot + label
// ---------------------------------------------------------------------------

function StatusChip({
  label,
  color,
  bgColor,
  borderColor,
  delay,
}: {
  label: string;
  color: string;
  bgColor: string;
  borderColor: string;
  delay: number;
}) {
  return (
    <div
      className="inline-flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-[1.5px] px-2.5 py-1 rounded-md mb-4"
      style={{
        fontFamily: "inherit",
        color,
        background: bgColor,
        border: `1px solid ${borderColor}`,
      }}
    >
      <motion.span
        className="w-[5px] h-[5px] rounded-full"
        style={{ background: color }}
        animate={{ scale: [1, 1.4, 1], opacity: [0.5, 1, 0.5] }}
        transition={{
          duration: 2,
          delay,
          repeat: Infinity,
          ease: "easeInOut",
        }}
      />
      {label}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Code content helpers
// ---------------------------------------------------------------------------

const kw = "text-violet-400";
const fn = "text-emerald-400";
const str = "text-amber-400";
const comment = "text-zinc-700";
const plain = "text-zinc-400";
const result = "text-emerald-400";

function RegisterCode() {
  return (
    <div style={{ fontFamily: "'SF Mono','Fira Code',monospace" }}>
      <div className={comment}>
        {"// Your iOS app — one line to expose a capability"}
      </div>
      <div>
        <span className={kw}>Remo</span>
        {"."}<span className={fn}>register</span>
        {"("}<span className={str}>"counter.increment"</span>
        {") { params "}
        <span className={kw}>in</span>
      </div>
      <div className="pl-4">
        <span className={plain}>counter</span>
        {" += params["}
        <span className={str}>"amount"</span>
        {"] "}
        <span className={kw}>as?</span>
        {" "}<span className={plain}>Int</span>
        {" ?? "}<span className={plain}>1</span>
      </div>
      <div className="pl-4">
        <span className={kw}>return</span>
        {" ["}
        <span className={str}>"count"</span>
        {": "}
        <span className={plain}>counter</span>
        {"]"}
      </div>
      <div>{"}"}</div>
    </div>
  );
}

function InvokeCode() {
  return (
    <div style={{ fontFamily: "'SF Mono','Fira Code',monospace" }}>
      <div className={comment}>$ Agent calls via CLI or JSON-RPC</div>
      <div>
        <span className={plain}>remo call</span>{" "}
        <span className={fn}>counter.increment</span>{" "}
        <span className={str}>{"'{\"amount\": 1}'"}</span>
      </div>
    </div>
  );
}

function ResponseCode() {
  return (
    <div style={{ fontFamily: "'SF Mono','Fira Code',monospace" }}>
      <span className={result}>✓</span>{" "}
      <span className={plain}>{"{"}</span>{" "}
      <span className={str}>"count"</span>
      {": "}
      <span className={plain}>4</span>{" "}
      <span className={plain}>{"}"}</span>
      <span className={`${comment} ml-4`}>← 3ms round-trip</span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// CapabilitySection
// ---------------------------------------------------------------------------

export function CapabilitySection() {
  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(52,211,153,0.07)"
        secondary="rgba(139,92,246,0.05)"
        primaryPos="50% 35%"
        secondaryPos="30% 65%"
      />
      <FloatingParticles
        particles={[
          { top: "15%", left: "12%", color: "#34d399", duration: 6, delay: 0 },
          { top: "55%", left: "85%", color: "#8b5cf6", duration: 8, delay: 2 },
          { top: "85%", left: "20%", color: "#fbbf24", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="Capability Invocation"
        labelColor="#34d399"
        title="Register in Swift. Call from anywhere."
        subtitle="Define named handlers in your app. Agents discover and invoke them at runtime — structured input, structured output."
      />

      {/* Pipeline */}
      <div className="relative z-10 flex flex-col items-center w-full max-w-[580px]">
        {/* Register */}
        <motion.div className="w-full" {...fadeInUp(0.2)}>
          <GlassPanel glowColor="rgba(139,92,246,0.5)">
            <StatusChip
              label="Register"
              color="#c084fc"
              bgColor="rgba(139,92,246,0.1)"
              borderColor="rgba(139,92,246,0.2)"
              delay={0}
            />
            <RegisterCode />
          </GlassPanel>
        </motion.div>

        {/* Connector 1 */}
        <motion.div {...fadeIn(0.5)}>
          <GradientConnector fromColor="#8b5cf6" toColor="#34d399" />
        </motion.div>

        {/* Invoke */}
        <motion.div className="w-full" {...fadeInUp(0.6)}>
          <GlassPanel glowColor="rgba(52,211,153,0.5)">
            <StatusChip
              label="Invoke"
              color="#34d399"
              bgColor="rgba(52,211,153,0.1)"
              borderColor="rgba(52,211,153,0.2)"
              delay={0.6}
            />
            <InvokeCode />
          </GlassPanel>
        </motion.div>

        {/* Connector 2 */}
        <motion.div {...fadeIn(0.9)}>
          <GradientConnector fromColor="#34d399" toColor="#fbbf24" />
        </motion.div>

        {/* Response */}
        <motion.div className="w-full" {...fadeInUp(1.0)}>
          <GlassPanel glowColor="rgba(251,191,36,0.4)">
            <StatusChip
              label="Response"
              color="#fbbf24"
              bgColor="rgba(251,191,36,0.1)"
              borderColor="rgba(251,191,36,0.2)"
              delay={1.2}
            />
            <ResponseCode />
          </GlassPanel>
        </motion.div>
      </div>
    </ShowcaseSection>
  );
}
```

- [ ] **Step 2: Verify build**

Run: `cd website && npx tsc --noEmit`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add website/src/components/FeatureShowcase/CapabilitySection.tsx
git commit -m "feat(showcase): add Capability Invocation section with pipeline demo"
```

---

### Task 5: Feature Showcase Wrapper + App Integration

**Files:**
- Create: `website/src/components/FeatureShowcase/FeatureShowcase.tsx`
- Modify: `website/src/App.tsx:1-24`
- Delete: `website/src/components/FeaturesSection.tsx`

- [ ] **Step 1: Create FeatureShowcase.tsx**

```tsx
import { ViewTreeSection } from "./ViewTreeSection";
import { CapabilitySection } from "./CapabilitySection";

export function FeatureShowcase() {
  return (
    <>
      <ViewTreeSection />
      <CapabilitySection />
    </>
  );
}
```

- [ ] **Step 2: Update App.tsx — replace FeaturesSection with FeatureShowcase**

Replace the full content of `website/src/App.tsx` with:

```tsx
import { Navbar } from "@/components/Navbar";
import { DemoHero } from "@/components/DemoHero/DemoHero";
import { VisionSection } from "@/components/VisionSection";
import { FeatureShowcase } from "@/components/FeatureShowcase/FeatureShowcase";
import { Footer } from "@/components/Footer";

// TODO: add Quick Start section with install + code snippet
// TODO: add comparison table (Remo vs Appium vs XCTest)
// TODO: add SEO meta tags (og:image, description, etc.)
function App() {
  return (
    <div className="min-h-screen bg-[#09090b] text-zinc-50 flex flex-col">
      <Navbar />
      <main className="flex-1">
        <DemoHero />
        <VisionSection />
        <FeatureShowcase />
      </main>
      <Footer />
    </div>
  );
}

export default App;
```

- [ ] **Step 3: Delete FeaturesSection.tsx**

```bash
rm website/src/components/FeaturesSection.tsx
```

- [ ] **Step 4: Verify build**

Run: `cd website && npx tsc --noEmit`
Expected: No errors. No references to deleted FeaturesSection remain.

- [ ] **Step 5: Visual verification**

Run: `cd website && npm run dev`
Open http://localhost:5173/Remo/ in the browser. Scroll down past the DemoHero and VisionSection.

Verify:
- View Tree section appears at full viewport height with phone wireframe on left, JSON on right
- Scan line animates across the phone
- Beam connector pulses between phone and JSON
- Hovering phone elements highlights JSON lines (and vice versa)
- Capability Invocation section appears below with 3-panel pipeline
- Status chip dots pulse with staggered timing
- Gradient connectors flow downward between panels
- Both sections have ambient lighting, noise texture, floating particles
- Scroll-triggered entrance animations fire once on first scroll into view

- [ ] **Step 6: Commit**

```bash
git add website/src/components/FeatureShowcase/FeatureShowcase.tsx website/src/App.tsx
git rm website/src/components/FeaturesSection.tsx
git commit -m "feat(showcase): integrate showcase sections, replace flat feature grid"
```
