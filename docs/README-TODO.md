# README Improvement Plan

Optimizations to make the repo more attractive and increase GitHub stars.

## High Priority

### 1. Hero visual (demo GIF/video)
30-second recording: left side terminal with agent running commands, right side simulator UI reacting. More persuasive than any text. Place at the very top of README after tagline.

### 2. "The Problem" section — paint the pain
Add a before/after contrast before "Why Remo?". Something like:
> AI agents can write Swift code and trigger builds — but they're blind.
> They can't see the screen, can't verify UI changes, can't tap buttons.
> Every iOS iteration still needs a human to look at the simulator and say "looks right."
> Remo closes this gap.

### 3. Sharper tagline
"Infrastructure for agentic iOS development" is technically accurate but forgettable. Consider:
- "Give your AI agent eyes and hands on iOS."
- "Let AI agents see and control iOS apps."

### 4. Badges
Add CI status, version, license, platform badges at the top. Without badges the repo looks immature to GitHub users scanning READMEs.

## Medium Priority

### 5. Shorter Quick Start
Current 4 steps → aim for "3 lines to get running". SPM dependency + 2 lines Swift + 1 CLI command. Lower the barrier.

### 6. Positioning / comparison table
Users will ask "how is this different from Appium / XCTest / accessibility inspector?" A brief table clarifying: Remo is not a test framework — it's the perception layer for AI agents.

| | Remo | Appium | XCTest |
|---|---|---|---|
| Primary user | AI agents | QA engineers | Developers |
| Setup | Embed SDK, zero config | WebDriver server | Xcode project |
| Capabilities | Custom Swift handlers | UI automation | Unit/UI tests |
| Visual feedback | Screenshot + video | Screenshot | None |

## Low Priority

### 7. "Built with Remo" / use case showcase
Once real users exist, add a section showing real agent workflows or integrations.

### 8. Animated architecture diagram
Replace ASCII art with a cleaner SVG or Mermaid diagram.

## Infrastructure / Tooling

### 9. Extract `remo-tart` CLI to its own repository

Context: the `remo-tart` CLI (see `docs/specs/2026-04-24-remo-tart-cli-design.md`) is ~90% generic Tart project-VM tooling. Lives under `tools/remo-tart/` inside Remo for now so iteration stays cheap while the CLI stabilizes — schema changes happen in one PR instead of two.

Trigger to act (any of):
- A second consumer project wants to use `remo-tart`.
- The CLI has been stable for 2+ releases with no schema churn.
- A contributor outside the Remo team asks to collaborate on the CLI itself.

Plan when triggered:
1. `git subtree split --prefix=tools/remo-tart -b remo-tart-extract` (preserves history).
2. Push to a new repo (tentative: `yjmeqt/remo-tart`).
3. Add standalone README, LICENSE, CHANGELOG, and CI (lint + tests on `ubuntu-latest`).
4. Tag first release, e.g. `v0.1.0`.
5. In Remo: delete `tools/remo-tart/`; update docs to install via `uv tool install git+https://github.com/yjmeqt/remo-tart@v0.1.0` (or `--editable` against a local clone for dev).
6. Coordinate schema changes across both repos going forward.

Why parked: only one consumer today; extracting now is premature generalization. `git subtree split` preserves history, so the cost of extraction later is minutes, not days.
