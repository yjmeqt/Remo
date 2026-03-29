---
name: remo-design-review
description: Use when comparing a running iOS app against Figma designs, constructing the required app state for each screen, capturing screenshots, and writing a design compliance report.
---

# Remo Design Review

Use this skill to compare real app output against Figma, not to guess from code.

Read `references/cli.md` before running capture commands, when you need exact screenshot flags, or when you want to record interactions and need to account for current `mirror` caveats.

## Workflow

1. Analyze the Figma file and list the target screens.
2. Define the app state required for each screen.
3. Add or extend capabilities needed to construct that state.
4. Capture the matching app screenshots.
5. Compare Figma and app output.
6. Write a report with concrete issues and action items.

## Step 1: Build the Screen Inventory

From the Figma file, record for each target:

- human-readable screen name
- Figma node
- required auth state
- required content state
- required navigation state
- important variants such as empty, error, or alternate visual states

Confirm the inventory before you build capabilities around it.

## Step 2: Design the Required App State

For each screen, define the exact conditions the app must satisfy:

- user or auth mode
- seeded data
- navigation location
- error or empty state
- appearance conditions if relevant

Then map those needs to concrete capabilities. If the needed capability does not exist, either add it or mark the screen as blocked.

## Step 3: Build Missing Capabilities

Common design-review helpers include:

- login or logout helpers
- seeded data loaders
- force-empty or force-error helpers
- direct navigation helpers

Keep them debug-only and prefer deterministic setup over manual tapping.

## Step 4: Capture the App

For each screen:

1. set up the required state
2. wait for the UI to settle
3. capture the screenshot in PNG
4. save the corresponding Figma screenshot

Use stable filenames so the report is easy to audit.

Use `references/cli.md` for exact capture commands and PNG syntax.

## Step 5: Compare

Assess each screen for:

- layout and spacing
- typography
- colors
- component styling
- screen state correctness
- navigation correctness

Use a simple scale:

- match
- minor deviation
- mismatch
- skipped

Every mismatch should describe the exact visual difference, where it appears, and what code area likely owns it.

## Step 6: Report

Write the review to `.remo/design-reviews/<review-id>/report.md`.

Include:

- report header with date, branch, device, and Figma link
- screen inventory summary
- side-by-side evidence for each reviewed screen
- issue list with severity and likely fix location
- skipped screens with blockers
- action items

If a screen is skipped because a capability is missing, add that capability to `.remo/capabilities.md` and call it out in the report.
