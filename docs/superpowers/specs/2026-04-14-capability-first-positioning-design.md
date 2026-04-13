# Capability-First Positioning Design

## Goal

Reposition Remo's public docs and showcase website around app-defined capability registration and semantic runtime control, while keeping screenshot and mirror functionality in the product and reference docs without marketing them as the product's core value.

## Scope

- Rewrite top-level documentation to make capability registration, discovery, and invocation the primary story.
- Remove screenshot and video streaming from the website marketing surface.
- Add an explicit tool-boundary statement that points users to `xcodebuildmcp` for simulator automation, screenshots, recording, and broader inspection.
- Keep existing screenshot and mirror commands documented in CLI reference material.
- Keep dashboard mirroring available as an operational feature, not a headline feature.

## Non-Goals

- Remove screenshot or mirror codepaths from the product.
- Change CLI behavior or built-in capabilities.
- Rework the dashboard implementation.
- Rewrite internal design-review workflows that still need screenshots.

## Current Problem

The current public surface overstates Remo's role in visual capture:

- `README.md` leads with "eyes and hands" and centers screenshots/mirroring in the core loop.
- The website hero and value props imply Remo owns the entire verification stack.
- The showcase dedicates full sections to screenshot capture and live video streaming, which makes Remo look like it is competing with more capable external tooling.
- `skills/README.md` repeats the same "eyes and hands" framing.

This creates a blurry boundary with `xcodebuildmcp`, which already covers simulator automation, screenshots, recording, and broader inspection well.

## Positioning Decision

### Product thesis

Remo is the in-app semantic control layer for AI-driven iOS development:

- developers register app-defined capabilities
- agents discover those capabilities at runtime
- agents invoke them with structured input and output
- discovery works across physical devices and simulators

### Tool boundary

Public docs and website should state this directly:

> `xcodebuildmcp` already handles simulator automation, screenshots, recording, and broader inspection well. Remo focuses on the part it does not provide: app-defined capability registration and semantic runtime control inside the running app.

### Marketing boundary

- Keep the website hero demo video as proof that capability invocations produce real app changes.
- Do not market screenshot capture or mirroring as reasons to adopt Remo.
- Do not mention `simctl` in the public positioning copy.

## Design Changes

### README

- Replace the hero paragraph and demo intro with capability-first language.
- Rewrite "Why Remo?" around:
  - programmable app control
  - runtime capability registration
  - discovery across USB and Bonjour
  - debug-only integration
- Change the quick-start interaction step from screenshot/mirror-heavy examples to discovery + invocation examples plus a short pairing note about `xcodebuildmcp`.
- Keep the CLI command list and built-in capability table intact so operational features remain discoverable.
- Update the skills section so `remo` is described as capability-first rather than screenshot-first.

### Skills overview

- Remove "eyes and hands" phrasing from `skills/README.md`.
- Reframe the `remo` workflow as capability-driven development with verification artifacts, instead of leading with screenshots.

### Website

- Update the hero heading and subtitle so the site sells capability registration and semantic control.
- Rewrite the value props to emphasize:
  - programmable app control
  - debug-only integration
  - runtime discovery
- Remove `ScreenshotSection` and `VideoStreamSection` from the marketing page.
- Promote `DynamicRegistrationSection` ahead of `ViewTreeSection` so the site leans harder into distinctive capability behavior.
- Add a short `ToolBoundarySection` that explicitly positions `xcodebuildmcp` as the preferred tool for simulator automation and capture.
- Update the hero timeline so the terminal story shows capability registration and invocation, not `remo screenshot`.

### Website internal docs

- Update `website/README.md` so its design rationale matches the new marketing order.
- Keep the demo-video implementation notes, but frame them as site-production details rather than product claims.

## Verification

- `README.md`, `skills/README.md`, and `website/README.md` no longer use "eyes and hands" for Remo's public positioning.
- Website code no longer renders screenshot or video showcase sections.
- Website includes an explicit `xcodebuildmcp` boundary section.
- Hero and value-prop copy emphasize capability registration and semantic runtime control.
- `pnpm build` succeeds in `website/`.

## Risks

- Removing too much mention of visual tooling from top-level docs could make existing operational features harder to discover.
- The hero still uses recorded video, so copy needs to avoid implying the recording itself is a Remo feature.

## Mitigations

- Keep screenshot and mirror commands in CLI/reference docs.
- Use the hero video strictly as proof of capability-driven app behavior.
- Add one explicit tool-boundary section instead of trying to hide the relationship with `xcodebuildmcp`.
