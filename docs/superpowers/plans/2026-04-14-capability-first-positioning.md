# Capability-First Positioning Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reposition Remo's public docs and website around app-defined capabilities and semantic runtime control, while explicitly delegating simulator automation and capture messaging to `xcodebuildmcp`.

**Architecture:** Update the top-level docs and website copy together so they tell the same story. Remove screenshot/video sections from the marketing page, insert a short tool-boundary section, and keep screenshot/mirror discoverable only in operational reference material.

**Tech Stack:** Markdown, React, TypeScript, Vite, Tailwind CSS.

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `docs/superpowers/specs/2026-04-14-capability-first-positioning-design.md` | Approved design for the repositioning |
| `docs/superpowers/plans/2026-04-14-capability-first-positioning.md` | Implementation plan for the approved design |
| `website/src/components/FeatureShowcase/ToolBoundarySection.tsx` | New marketing section that explains the `xcodebuildmcp` boundary |

### Modified files

| File | Changes |
|---|---|
| `README.md` | Rewrite top-level positioning, quick-start interaction step, and skills wording |
| `skills/README.md` | Remove "eyes and hands" phrasing and make capability workflows primary |
| `website/src/components/DemoHero/DemoHero.tsx` | Capability-first hero copy |
| `website/src/components/DemoHero/timeline.ts` | Remove `remo screenshot` beats from the hero story |
| `website/src/components/VisionSection.tsx` | New capability-first value props |
| `website/src/components/FeatureShowcase/FeatureShowcase.tsx` | Remove screenshot/video sections and insert tool-boundary section |
| `website/README.md` | Update showcase rationale and architecture documentation |

## Chunk 1: Documentation repositioning

### Task 1: Rewrite top-level Remo positioning docs

**Files:**
- Modify: `README.md`
- Modify: `skills/README.md`

- [ ] **Step 1: Rewrite the README hero and demo intro**

Change the opening copy so it leads with capability registration, discovery, and semantic invocation rather than screenshots and mirroring.

- [ ] **Step 2: Rewrite the README value proposition**

Update "Why Remo?" so the bullets emphasize programmable app control, runtime capability registration, device discovery, and debug-only integration.

- [ ] **Step 3: Update README quick-start interaction guidance**

Change the interaction step to discovery + capability invocation, then add one explicit note that `xcodebuildmcp` is the preferred tool for simulator automation, screenshots, recording, and inspection.

- [ ] **Step 4: Update the skills overview README**

Remove "eyes and hands" wording and reframe the `remo` workflow as capability-driven development with verification artifacts as a supporting mechanism.

- [ ] **Step 5: Review the copy for consistency**

Confirm `README.md` and `skills/README.md` use the same product boundary and do not market screenshot/video as the thesis.

## Chunk 2: Website marketing surface

### Task 2: Reorder and rewrite the public website

**Files:**
- Modify: `website/src/components/DemoHero/DemoHero.tsx`
- Modify: `website/src/components/DemoHero/timeline.ts`
- Modify: `website/src/components/VisionSection.tsx`
- Modify: `website/src/components/FeatureShowcase/FeatureShowcase.tsx`
- Create: `website/src/components/FeatureShowcase/ToolBoundarySection.tsx`

- [ ] **Step 1: Rewrite hero copy**

Replace "eyes and hands" language with capability-first language while keeping the existing two-column demo layout and video asset.

- [ ] **Step 2: Remove screenshot beats from the hero timeline**

Edit the terminal script so the story is about registering and calling capabilities, observing app changes, and moving through app-defined workflows.

- [ ] **Step 3: Rewrite the value props**

Replace the current cards with capability-first messaging: programmable app control, debug-only integration, and runtime discovery.

- [ ] **Step 4: Remove screenshot/video showcase sections**

Stop rendering `ScreenshotSection` and `VideoStreamSection` in `FeatureShowcase.tsx`.

- [ ] **Step 5: Add the tool-boundary section**

Create a short section that explicitly says `xcodebuildmcp` handles simulator automation, screenshots, recording, and broader inspection, while Remo focuses on in-app semantic control.

- [ ] **Step 6: Reorder showcase sections**

Render the sections in this order: capability invocation, dynamic registration, view tree inspection, device discovery, tool boundary.

## Chunk 3: Website internal docs and verification

### Task 3: Align internal website docs and verify the build

**Files:**
- Modify: `website/README.md`

- [ ] **Step 1: Update the website README overview**

Describe the site as a capability-first showcase rather than a visual-verification showcase.

- [ ] **Step 2: Update section-order documentation**

Reflect the new section ordering and remove screenshot/video as conceptual pillars.

- [ ] **Step 3: Update the architecture section**

Replace the removed showcase components with the new tool-boundary component in the file map.

- [ ] **Step 4: Build the website**

Run: `cd website && pnpm build`
Expected: successful production build with no missing imports after section removal/addition.

- [ ] **Step 5: Review the diff**

Run: `git diff -- README.md skills/README.md website/README.md website/src/components`
Expected: only the approved positioning changes plus the new tool-boundary component.
