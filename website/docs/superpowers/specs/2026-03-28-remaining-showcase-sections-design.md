# Remaining Showcase Sections — Design Spec

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this spec.

**Goal:** Add 4 new full-viewport showcase sections (Screenshot Capture, Live Video Streaming, Multi-Device Discovery, Dynamic Registration) to the existing FeatureShowcase, and reorder all 6 sections.

**Prerequisite:** The shared design system (`shared.tsx`), `PhoneWireframe.tsx`, `ViewTreeSection.tsx`, and `CapabilitySection.tsx` already exist. All new sections reuse the shared primitives.

---

## Section Order

The full page order after this work:

1. **Capability Invocation** (existing — `CapabilitySection.tsx`)
2. **View Tree Inspection** (existing — `ViewTreeSection.tsx`)
3. **Screenshot Capture** (new)
4. **Live Video Streaming** (new)
5. **Multi-Device Discovery** (new)
6. **Dynamic Registration** (new)

Update `FeatureShowcase.tsx` to render sections in this order.

---

## Shared Design System (Reference)

All sections use the existing shared primitives from `shared.tsx`:

- `ShowcaseSection` — full-viewport wrapper (`min-h-screen`)
- `SectionHeader` — 11px label + 48px gradient title + 17px subtitle
- `GlassPanel` — glassmorphism panel with backdrop-blur and colored top-edge glow
- `NoiseOverlay` — SVG fractalNoise at 3% opacity
- `AmbientLight` — dual radial gradients
- `FloatingParticles` — 3 animated dots
- `GradientConnector` — animated vertical line between panels
- Animation helpers: `fadeInUp`, `fadeInLeft`, `fadeInRight`, `fadeIn`
- Viewport trigger: `{ once: true, amount: 0.3 }`

### Code Syntax Colors (shared across all code panels)

| Token | Color | Tailwind class |
|-------|-------|----------------|
| Keyword | `#c084fc` (violet-400) | `text-violet-400` |
| Function/method | `#34d399` (emerald-400) | `text-emerald-400` |
| String literal | `#fbbf24` (amber-400) | `text-amber-400` |
| Comment | `#3f3f46` (zinc-700) | `text-zinc-700` |
| Plain/identifier | `#a1a1aa` (zinc-400) | `text-zinc-400` |
| Result marker (✓) | `#34d399` (emerald-400) | `text-emerald-400` |

---

## Section 3: Screenshot Capture

**File:** `ScreenshotSection.tsx`

**Accent color:** Pink (`#f472b6`)

**Section label:** "Screenshot Capture"
**Title:** "Instant visual verification"
**Subtitle:** "Capture the screen after every action. Agents verify UI state autonomously — no manual checking, no guesswork."

### Demo Layout

Vertical layout, centered:

```
     ┌────────────────┐
     │  Phone (160px)  │
     │  + shutter flash│
     └────────────────┘

  [ #1 ][ #2 ][ #3 ][ #4 ]
       thumbnail strip

  ┌──────────────────────┐
  │  CLI panel            │
  └──────────────────────┘
```

### Phone with Shutter Flash

A phone wireframe (160×320px) with:
- Border-radius 28px, 1.5px solid border (zinc-700 at 40%), dark background
- Notch pill at top (44px wide, 15px height)
- Screen content: simple counter UI (nav bar, large "4" number, "Increment" button styled like the View Tree section's UI)

**Shutter flash:** An absolute overlay inside the screen with `background: rgba(244,114,182,0.08)`. Animated with a 3s cycle: invisible for most of the duration, then a quick pink flash at 85% progress, fading out by 92%. This creates a periodic "camera shutter" pulse.

**Captured badge:** Positioned absolute at top-right of screen (z-index 3). Font-size 8px, uppercase, letter-spacing 1.5px, font-weight 600. Color `#f472b6`, background `rgba(244,114,182,0.15)`, border `1px solid rgba(244,114,182,0.25)`, border-radius 4px, padding 2px 6px. Animated in sync with the shutter flash (appears at 85%, disappears by 95% of the 3s cycle).

### Thumbnail Strip

Horizontal row of 4 thumbnail cards below the phone:
- Each thumbnail: 64×110px, border-radius 10px, border 1px solid zinc-700 at 40%, background `rgba(24,24,27,0.6)`
- Inner content: 3px inset, miniaturized counter UI (tiny nav bar, number text, tiny button)
- Bottom-right corner: frame number label (#1, #2, #3, #4) in zinc-600, 7px font
- **Active thumbnail** (last one, #4): border-color `rgba(244,114,182,0.5)`, box-shadow `0 0 20px rgba(244,114,182,0.15)`, number label in pink
- Hover effect on all thumbnails: border-color brightens to pink at 40%, subtle glow

### CLI Panel

Below the thumbnail strip. Max-width 400px, centered. Uses shared code panel styling (dark background, zinc border, border-radius 10px, monospace 11px, line-height 1.8).

Content:
```
$ Agent's verification loop
remo call counter.increment '{"amount": 1}'
remo screenshot --format jpeg
✓ Δ detected — counter 3→4, UI verified
```

Color coding: comment for `$` line, plain for `remo call`, function color for `counter.increment`, string for JSON arg, function color for `screenshot`, string for `--format jpeg`. Result line: emerald `✓`, pink `Δ detected`, comment for description.

### Entrance Animation

1. Section header fades in (0.6s)
2. Phone fades in from above (fadeInUp, 0.2s delay)
3. Thumbnails fade in one by one left to right (fadeInUp, 0.4s/0.5s/0.6s/0.7s delays)
4. CLI panel fades in (fadeInUp, 0.9s delay)

---

## Section 4: Live Video Streaming

**File:** `VideoStreamSection.tsx`

**Accent color:** Sky blue (`#38bdf8`)

**Section label:** "Live Video Streaming"
**Title:** "Stream the screen in real time"
**Subtitle:** "H.264 hardware-encoded mirroring. Record sessions, review animations, verify transitions — frame by frame."

### Demo Layout

Vertical layout, centered:

```
     ┌────────────────┐
     │  Phone (150px)  │
     │  + REC badge    │
     └────────────────┘

  ┌──────────────────────────┐
  │  Timeline bar             │
  │  [waveform visualization] │
  │  [playhead track]         │
  │  0:00   0:02   0:04  0:06│
  └──────────────────────────┘
```

### Phone with REC Badge

Phone wireframe (150×300px), border-radius 26px. Same construction as Screenshot section phone.

**REC badge:** Positioned absolute at top-left of screen. Display flex, align-items center, gap 4px. Font-size 8px, uppercase, letter-spacing 1.5px, font-weight 700. Color `#ef4444` (red-500), background `rgba(239,68,68,0.15)`, border `1px solid rgba(239,68,68,0.3)`, border-radius 4px, padding 2px 7px.

**REC dot:** 4px circle, background `#ef4444`, animated blink (opacity 0.4→1→0.4, 1.5s ease-in-out infinite).

**Screen content:** Same counter UI layout (nav bar, large number, button). Below the button, a list section with 3 rows that have a subtle scroll-up animation (translateY 0→-4px, 4s ease-in-out infinite, staggered delays 0/0.3s/0.6s) to suggest the screen is "alive" and being recorded.

### Timeline Bar

Max-width 500px, centered below phone. Background `rgba(24,24,27,0.7)`, border 1px solid zinc-700 at 30%, border-radius 10px, padding 16px 20px.

**Header row:** flex, space-between. Left: "Recording" label in sky blue, 10px, uppercase, letter-spacing 1.5px, font-weight 600. Right: "00:04.2 / 00:06.5" in zinc-600, 10px monospace.

**Waveform:** Horizontal row of ~30 bars (3px wide, 1.5px gap). Each bar: border-radius 1.5px, background `rgba(56,189,248,0.4)` (sky blue at 40%). Heights vary between 10px and 40px (randomized but fixed). Each bar has a subtle pulse animation (opacity 0.3→0.8→0.3, 2s ease-in-out infinite, staggered delays spread across 0-2s).

**Playhead track:** Below waveform, margin-top 8px. Full width, 2px height, background zinc-700 at 30%, border-radius 1px. Fill: 65% width, gradient `linear-gradient(90deg, #38bdf8, #818cf8)`. Playhead dot: 8px circle at the 65% mark, background `#38bdf8`, border 2px solid `#09090b`, box-shadow `0 0 8px rgba(56,189,248,0.4)`.

**Frame markers:** Below playhead, flex space-between. Labels: "0:00", "0:02", "0:04", "0:06" in zinc-800, 7px monospace.

### Entrance Animation

1. Section header fades in (0.6s)
2. Phone fades in (fadeInUp, 0.2s delay)
3. Timeline bar fades in (fadeInUp, 0.5s delay)

---

## Section 5: Multi-Device Discovery

**File:** `DeviceDiscoverySection.tsx`

**Accent color:** Orange (`#fb923c`) primary, Violet (`#a78bfa`) for Bonjour

**Section label:** "Multi-Device Discovery"
**Title:** "Plug in and go"
**Subtitle:** "USB for physical devices, Bonjour for simulators. Agents find every device automatically — no configuration needed."

### Demo Layout

Vertical layout, centered:

```
  ┌─────────┐ ┌─────────┐ ┌─────────┐
  │ iPhone  │ │ iPad    │ │ iPhone  │
  │ 17 Pro  │ │ Air     │ │ 16 Sim  │
  │   USB   │ │   USB   │ │ Bonjour │
  └─────────┘ └─────────┘ └─────────┘

  ┌──────────────────────────────────┐
  │  $ remo devices                  │
  │  ● iPhone 17 Pro  USB  · 18.4   │
  │  ● iPad Air (M3)  USB  · 18.4   │
  │  ● iPhone 16 Sim  Bonjour · 18.0│
  └──────────────────────────────────┘
```

### Device Card Grid

3-column grid (`grid-template-columns: repeat(3, 1fr)`), gap 12px, max-width 480px, centered.

Each card:
- Background `rgba(24,24,27,0.7)`, border 1px solid zinc-700 at 30%, border-radius 12px, padding 16px, text-align center
- Hover: border-color `rgba(251,146,60,0.3)`, box-shadow `0 0 20px rgba(251,146,60,0.08)`
- **Status dot:** Absolute positioned top-right (8px, 8px). 6px circle, animated pulse (scale 1→1.3, opacity 0.5→1, 2s ease-in-out infinite, staggered 0/0.5s/1s).
  - USB devices: orange dot with orange glow
  - Bonjour devices: violet dot with violet glow
- **Device icon:** 28px emoji (📱), margin-bottom 8px
- **Device name:** 11px, zinc-400, font-weight 500, margin-bottom 4px
- **OS version:** 9px, zinc-600, monospace
- **Connection tag:** Inline-block, 8px, padding 2px 6px, border-radius 4px, font-weight 600, uppercase, letter-spacing 1px, margin-top 8px
  - USB tag: orange text, `rgba(251,146,60,0.1)` background, `rgba(251,146,60,0.2)` border
  - Bonjour tag: violet text, `rgba(167,139,250,0.1)` background, `rgba(167,139,250,0.2)` border

**Devices shown:**
1. iPhone 17 Pro — iOS 18.4 — USB
2. iPad Air (M3) — iPadOS 18.4 — USB
3. iPhone 16 Sim — iOS 18.0 — Bonjour

### CLI Panel

Below the grid. Max-width 480px, centered. Same code panel styling as other sections. Monospace 11px, line-height 1.8.

Content:
```
$ Discover all connected devices
remo devices
● iPhone 17 Pro  USB  · iOS 18.4 · 1170×2532
● iPad Air (M3)  USB  · iPadOS 18.4 · 2360×1640
● iPhone 16 Sim  Bonjour  · iOS 18.0 · 1170×2532
```

Color coding: comment for `$` line, plain for `remo`, function for `devices`. Each device line: emerald `●`, plain name, orange `USB` or violet `Bonjour`, comment for OS/resolution details.

### Entrance Animation

1. Section header fades in (0.6s)
2. Device cards fade in left-to-right (fadeInUp, 0.2s/0.35s/0.5s delays)
3. CLI panel fades in (fadeInUp, 0.7s delay)

---

## Section 6: Dynamic Registration

**File:** `DynamicRegistrationSection.tsx`

**Accent color:** Teal (`#2dd4bf`) primary, Violet (`#a78bfa`) for detail screen

**Section label:** "Dynamic Registration"
**Title:** "Capabilities follow the UI"
**Subtitle:** "Register on appear, unregister on disappear. Agents always see exactly what's available on the current screen."

### Demo Layout

Horizontal layout with two phone columns and navigation arrow between them, plus an event panel below:

```
  Home Screen          Detail Screen
  ┌──────────┐  nav   ┌──────────┐
  │ List View│ ────→  │Detail View│
  └──────────┘        └──────────┘
  ● app.refresh       ○ app.refresh
  ● list.scroll       ○ list.scroll
  ○ detail.getInfo    ● detail.getInfo
  ○ detail.edit       ● detail.edit

  ┌─────────────────────────────────┐
  │ capabilities_changed {          │
  │   + detail.getInfo              │
  │   + detail.edit                 │
  │   − list.scroll                 │
  │   − app.refresh                 │
  │ }                               │
  └─────────────────────────────────┘
```

### Phone Wireframes

Two phone wireframes (130×260px each), border-radius 22px. Similar construction to other phone mocks.

**Home Screen phone:**
- Title label above: "Home Screen" in teal, 10px, uppercase, letter-spacing 2px, font-weight 600
- Screen content: simple nav bar ("My App" title), list of rows (9 placeholder bars at varying widths 60-90%), label at bottom "List View" in zinc-600

**Detail Screen phone:**
- Title label above: "Detail Screen" in violet, same styling
- Screen content: nav bar with back dots + "Detail" title, centered square icon (48×48px, border-radius 8px, violet tinted background/border), centered name bar, description rows, "Edit" button (violet tinted), label "Detail View"

### Capability Lists

Below each phone, a list of capability chips (4 items per phone):

Each chip: flex row, gap 6px, padding 5px 10px, border-radius 6px, font-size 10px, monospace. Border 1px solid zinc-700 at 30%, background `rgba(24,24,27,0.5)`.

**Active chip:** Border-color tinted with accent color at 30%, background tinted at 6%, box-shadow `0 0 12px` at 8% opacity. Dot: 5px circle with accent color and glow.

**Inactive chip:** opacity 0.35, border-style dashed. Dot: 5px circle, zinc-800 background, no glow.

**Home Screen capabilities:**
- `app.refresh` — active (teal)
- `list.scroll` — active (teal)
- `detail.getInfo` — inactive
- `detail.edit` — inactive

**Detail Screen capabilities:**
- `app.refresh` — inactive
- `list.scroll` — inactive
- `detail.getInfo` — active (violet)
- `detail.edit` — active (violet)

### Navigation Arrow

Between the two phone columns, centered vertically. Two vertical animated gradient lines (1.5px wide, 60px tall) with a "navigate" label between them (8px, uppercase, letter-spacing 1.5px, zinc-600, `writing-mode: vertical-rl`).

Line gradient: `linear-gradient(180deg, transparent, #2dd4bf, #a78bfa, transparent)`, animated flowing downward (2s ease-in-out infinite), same technique as `GradientConnector`.

### Event Panel

Below the phone columns, centered, max-width 520px. Same code panel styling (dark background, monospace 10px, line-height 1.8).

Content:
```
// Agent receives real-time notification
capabilities_changed {
  + detail.getInfo
  + detail.edit
  − list.scroll
  − app.refresh
}
```

Color coding: comment for `//` line, teal for `capabilities_changed`, plain for braces. Added capabilities: emerald-400 (`#34d399`). Removed capabilities: red-500 (`#ef4444`).

### Entrance Animation

1. Section header fades in (0.6s)
2. Home phone column fades in from left (fadeInLeft, 0.2s delay)
3. Navigation arrow fades in (fadeIn, 0.4s delay)
4. Detail phone column fades in from right (fadeInRight, 0.3s delay)
5. Event panel fades in (fadeInUp, 0.6s delay)

---

## File Structure

```
src/components/FeatureShowcase/
├── FeatureShowcase.tsx            — updated: renders all 6 sections in new order
├── shared.tsx                     — existing (no changes needed)
├── ViewTreeSection.tsx            — existing (no changes)
├── PhoneWireframe.tsx             — existing (no changes)
├── CapabilitySection.tsx          — existing (no changes)
├── ScreenshotSection.tsx          — NEW
├── VideoStreamSection.tsx         — NEW
├── DeviceDiscoverySection.tsx     — NEW
└── DynamicRegistrationSection.tsx — NEW
```

### FeatureShowcase.tsx Change

Update to import and render all 6 sections in the new order:

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

---

## Technical Notes

- All new sections use existing shared primitives — no new shared components needed.
- Phone wireframes in the new sections are simpler than `PhoneWireframe.tsx` (no hover interaction, just static UI mockups). They are built inline in each section file rather than reusing `PhoneWireframe.tsx`, which is specifically designed for the View Tree section's interactive hover-highlighting.
- CSS animations (shutter flash, REC blink, waveform pulse, scroll-up) use inline `style` with `@keyframes` via Framer Motion's `animate` prop or Tailwind's `animate-` utilities where possible.
- No new dependencies required.
- Each section file should be self-contained — all section-specific sub-components are defined within the file (not exported).
