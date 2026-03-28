# Premium Capability Showcase — Design Spec

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this spec.

**Goal:** Replace the flat 6-card feature grid with full-viewport, scroll-animated showcase sections — starting with 2 proof-of-concept sections (View Tree Inspection, Capability Invocation).

**Style:** Apple product page cinema — each capability owns a full viewport. Dark theme with glassmorphism panels, scroll-triggered entrance animations, ambient lighting, and interactive demos.

---

## Scope

Build 2 sections as proof of concept. The remaining 4 capabilities (Screenshot Capture, Live Video Streaming, Multi-Device Discovery, Dynamic Registration) will reuse the same design system and be added later.

**Sections to build:**
1. View Tree Inspection
2. Capability Invocation

**What stays:** The existing FeaturesSection flat card grid is removed and replaced by these new sections in the same position (between VisionSection and Footer).

---

## Shared Design System

All showcase sections share a unified visual language. These elements are extracted into reusable components/utilities.

### Layout

Each section is a full-viewport (`min-h-screen`) flex container, vertically and horizontally centered. Max content width: 960px. Padding: 80px vertical, 40px horizontal.

### Typography

- **Section label**: 11px, uppercase, letter-spacing 3px, font-weight 600, colored per section accent
- **Section title**: 48px, font-weight 700, letter-spacing -1.5px, gradient text (white → zinc-400 top-to-bottom via `background-clip: text`)
- **Section subtitle**: 17px, color zinc-500, max-width 500-520px, centered, line-height 1.6

### Ambient Lighting

Each section has 2 radial gradients positioned behind the demo area. Primary gradient uses the section's accent color at 7-8% opacity, secondary uses a complementary color at 5-6% opacity. Ellipse sizes: 400-600px wide, 300-400px tall.

### Noise Texture

SVG fractalNoise overlay at 3% opacity, covering the full section. Provides film-grain tactile depth. Shared across all sections (same SVG data URI).

### Glassmorphism Panels

All code/demo panels share:
- `background: rgba(24,24,27, 0.5)` (semi-transparent zinc-900)
- `backdrop-filter: blur(20px)`
- `border: 1px solid rgba(63,63,70, 0.4)` (zinc-700 at 40%)
- `border-radius: 16px`
- `box-shadow: 0 0 0 1px rgba(255,255,255,0.03), 0 16px 48px rgba(0,0,0,0.4)`
- Top-edge glow: pseudo-element, 1px height, horizontal gradient using section accent color at ~50% opacity, positioned left 15% to right 15%

### Floating Particles

3 small dots (2px) per section, positioned absolutely, using the section's accent colors. Animated with a 6-8s ease-in-out float (translateY -20px + scale 1.5), staggered delays.

### Scroll-Triggered Entrance

All animations trigger when the section enters the viewport (Framer Motion `whileInView` with `viewport={{ once: true, amount: 0.3 }}`). Elements use staggered fade-in + translateY (starting 30-40px below, animating to 0). Easing: `[0.25, 0.4, 0.25, 1]` (smooth deceleration). Duration: 0.6-0.8s per element, 0.15s stagger between siblings.

### Code Syntax Colors

| Token | Color | CSS class |
|-------|-------|-----------|
| Keyword (Remo, return, in) | `#c084fc` (violet-400) | `.kw` |
| Function/method name | `#34d399` (emerald-400) | `.fn` |
| String literal | `#fbbf24` (amber-400) | `.str` |
| Number | `#fbbf24` (amber-400) | `.num` |
| JSON key | `#a78bfa` (violet-300) | `.json-key` |
| JSON string value | `#34d399` (emerald-400) | `.json-str` |
| Comment | `#3f3f46` (zinc-700) | `.comment` |
| Plain/identifier | `#a1a1aa` (zinc-400) | `.plain` |
| Braces/structure | `#52525b` (zinc-600) | `.json-brace` |
| Success marker (✓) | `#34d399` (emerald-400) | `.result` |

---

## Section 1: View Tree Inspection

**Accent color:** Purple (`#8b5cf6`)

**Section label:** "View Tree Inspection"
**Title:** "See what your agent sees"
**Subtitle:** "Every UIView, every frame, every property — structured as JSON that agents can parse and reason about."

### Demo Layout

Horizontal layout with 3 elements centered in the stage:

```
[ Phone Wireframe ]  ---beam--->  [ JSON Panel ]
```

### Phone Wireframe

A schematic device outline (220×440px) with dashed-border rectangles representing UI elements. Not a real screenshot — pure geometric wireframe.

- **Container**: 1.5px solid border (zinc-700 at 60%), border-radius 36px, semi-transparent background with backdrop-blur. Notch represented by a dark pill shape at top.
- **UI elements** (stacked vertically inside the phone):
  - NavigationBar (height ~42px)
  - ContentView (height ~160px, contains child elements: Text "Counter: 3", Button "Increment")
  - List section (height ~100px, contains 3 rows: Item 1, Item 2, Item 3)
  - TabBar (height ~44px)
- **Element style**: 1px dashed border `rgba(139,92,246, 0.25)`, border-radius 8px, subtle fill `rgba(139,92,246, 0.04)`, text is element name at 10px in purple at 50% opacity.
- **Hover effect**: border-color brightens to 60%, text brightens to 90%, box-shadow adds 20px purple glow + inner glow.

### Scan Line Animation

A horizontal gradient bar (2px height) sweeps top-to-bottom inside the phone wireframe. Gradient: `transparent → #8b5cf6 → #c084fc → #8b5cf6 → transparent`. Box-shadow provides a 20px + 60px purple glow. Animation: 3s ease-in-out, infinite, fading in at 10% progress and out at 90%.

### Connection Beam

Between phone and JSON panel: two horizontal lines (80px wide, 1.5px height) with a label "remo tree" between them. Lines have an animated gradient that flows left-to-right: `transparent → #8b5cf6 → #34d399 → transparent`, 2s ease-in-out infinite.

### JSON Panel

Glassmorphism panel (max-width 380px) displaying a formatted JSON view tree. Uses the shared code syntax colors. Content represents the UIWindow → ContentView → Text/Button hierarchy matching the phone wireframe.

Line height: 2.0 for readability. Font: SF Mono / Fira Code, 12px.

### Hover Interaction

Hovering a UI element rectangle on the phone highlights the corresponding JSON node (matching background tint + border glow). Hovering a JSON line highlights the corresponding rectangle on the phone. Bidirectional — implemented via shared React state tracking the hovered element ID.

### Entrance Animation

1. Section label + title + subtitle fade in together (0.6s)
2. Phone wireframe fades in from left (translateX -30px → 0, 0.7s, 0.2s delay)
3. Scan line begins sweeping
4. JSON panel fades in from right (translateX 30px → 0, 0.7s, 0.4s delay)
5. Beam connector fades in (0.5s, 0.6s delay)

---

## Section 2: Capability Invocation

**Accent color:** Emerald (`#34d399`) primary, with a 3-stage color progression: Purple (register) → Emerald (invoke) → Amber (response)

**Section label:** "Capability Invocation"
**Title:** "Register in Swift. Call from anywhere."
**Subtitle:** "Define named handlers in your app. Agents discover and invoke them at runtime — structured input, structured output."

### Demo Layout

Vertical pipeline with 3 glassmorphism panels connected by animated gradient lines:

```
┌─────────────────────────┐
│  ● Register   (purple)  │
│  Swift code block        │
└────────────┬────────────┘
             │ ← animated gradient connector
┌────────────▼────────────┐
│  ● Invoke   (emerald)   │
│  CLI command             │
└────────────┬────────────┘
             │ ← animated gradient connector
┌────────────▼────────────┐
│  ● Response  (amber)    │
│  JSON result             │
└─────────────────────────┘
```

Max pipeline width: 580px.

### Panel 1: Register (Purple)

- **Status chip**: "Register" with pulsing purple dot, purple-tinted background
- **Top-edge glow**: Purple
- **Content** (monospace, 13px):
  ```
  // Your iOS app — one line to expose a capability
  Remo.register("counter.increment") { params in
    counter += params["amount"] as? Int ?? 1
    return ["count": counter]
  }
  ```

### Panel 2: Invoke (Emerald)

- **Status chip**: "Invoke" with pulsing emerald dot, emerald-tinted background
- **Top-edge glow**: Emerald
- **Content**:
  ```
  $ Agent calls via CLI or JSON-RPC
  remo call counter.increment '{"amount": 1}'
  ```

### Panel 3: Response (Amber)

- **Status chip**: "Response" with pulsing amber dot, amber-tinted background
- **Top-edge glow**: Amber
- **Content**:
  ```
  ✓ { "count": 4 }    ← 3ms round-trip
  ```

### Status Chip

Each panel has a status chip in the top-left: colored dot (5px, pulsing scale 1→1.4 over 2s) + uppercase label (10px, letter-spacing 1.5px). Background is accent color at 10% opacity, border at 20%.

Pulse animation stagger: Register 0s, Invoke 0.6s, Response 1.2s — creating a cascading "heartbeat" effect.

### Gradient Connectors

Between each panel: a vertical line (1.5px wide, 48px tall) with an animated gradient blob that flows downward.

- Register → Invoke: `transparent → #8b5cf6 → #34d399 → transparent`
- Invoke → Response: `transparent → #34d399 → #fbbf24 → transparent`

Animation: 2s ease-in-out infinite, flowing from top to bottom.

### Entrance Animation

1. Section label + title + subtitle fade in (0.6s)
2. Register panel slides in from above (translateY -30px → 0, 0.7s, 0.2s delay)
3. First connector fades in (0.4s, 0.5s delay)
4. Invoke panel slides in (0.7s, 0.6s delay)
5. Second connector fades in (0.4s, 0.9s delay)
6. Response panel slides in (0.7s, 1.0s delay)

The cascading entrance reinforces the top-to-bottom pipeline narrative.

---

## File Structure

```
src/components/
├── FeatureShowcase/
│   ├── FeatureShowcase.tsx        — wraps all showcase sections
│   ├── shared.tsx                 — shared components (SectionHeader, GlassPanel, NoiseOverlay, AmbientLight, FloatingParticles)
│   ├── ViewTreeSection.tsx        — View Tree Inspection section
│   ├── CapabilitySection.tsx      — Capability Invocation section
│   └── PhoneWireframe.tsx         — reusable phone wireframe with UI element slots
```

**App.tsx change:** Replace `<FeaturesSection />` with `<FeatureShowcase />`. Delete `FeaturesSection.tsx` — the flat card grid is fully replaced by the showcase sections. The 4 capabilities not yet built (Screenshot, Video, Discovery, Dynamic Registration) are omitted for now and will be added as future showcase sections.

---

## Technical Notes

- All animations use Framer Motion (`motion.div`, `whileInView`, `useInView`).
- `viewport={{ once: true, amount: 0.3 }}` — animate once when 30% of section is visible.
- Hover interactions use React state (`useState<string | null>` for hovered element ID), no external libraries.
- Noise texture is a single inline SVG data URI, no external asset.
- `backdrop-filter: blur()` has good support but no fallback needed (dark semi-transparent bg is acceptable without blur).
- No new dependencies required — React, Framer Motion, and Tailwind CSS are sufficient.
