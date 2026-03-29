---
name: remo
description: Structured verification workflow for iOS development — capture baseline, add verification checkpoints, produce a reviewable timeline with screenshots and capability results. Use when working on an iOS project that has Remo SDK integrated.
type: flexible
---

# Remo — Verified iOS Development

Remo gives AI agents a closed-loop verification workflow for iOS development. Instead of writing code and hoping it works, you **capture evidence at every step** and produce a reviewable verification report with screenshots, capability results, and a timeline.

> **Prerequisites:**
> - Remo SDK integrated and app running on a simulator/device. If not, use `remo-setup` first.
> - Remo CLI available at `.remo/bin/remo` (project-local) or `remo` (global). If neither, run `remo-setup` Step 1.

---

## Core Workflow

Every task follows this loop:

```
Connect → Baseline → [Code → Build → Checkpoint]... → Report
```

1. **Connect** — discover the device and confirm connectivity
2. **Baseline** — capture the current state before any changes
3. **Code → Build → Checkpoint** — repeat for each change: modify code, rebuild, then capture evidence (screenshot, view tree, capability result) and assess pass/fail
4. **Report** — write the verification timeline to a markdown file with embedded assets

The report is the deliverable — it lets the user (or a future reviewer) see exactly what happened, what was verified, and what the app looked like at each step.

---

## Step 0: Connect

```bash
remo devices
```

Store the address and verify connectivity:

```bash
ADDR="127.0.0.1:<port>"
remo call -a $ADDR "__ping" '{}'
remo info -a $ADDR
```

Record the device and app info — you will need it for the report header.

---

## Step 1: Start a Verification Session

Create a directory to hold all artifacts for this task:

```bash
mkdir -p .remo/verifications/<task-id>/assets
```

Use a short, descriptive `<task-id>` — e.g., `fix-avatar-radius`, `add-settings-screen`.

Initialize the report file at `.remo/verifications/<task-id>/report.md`:

```markdown
# Verification: <task description>

- **Date:** <YYYY-MM-DD HH:MM>
- **Device:** <name> (<OS version>, <Simulator|Device>)
- **App:** <bundle-id> (<version>)
- **Branch:** <git branch>

## Timeline
```

---

## Step 2: Capture Baseline

Before making any changes, capture the current state as your reference point:

```bash
# Screenshot the relevant screen(s)
remo screenshot -a $ADDR -o .remo/verifications/<task-id>/assets/00-baseline.jpg

# Optionally capture view tree for structural reference
remo tree -a $ADDR > .remo/verifications/<task-id>/assets/00-baseline-tree.txt

# If relevant, capture internal state via capabilities
remo call -a $ADDR "get_state" '{}' > .remo/verifications/<task-id>/assets/00-baseline-state.json
```

Append to the report:

```markdown
### Step 0: Baseline
- **Screenshot:** ![baseline](assets/00-baseline.jpg)
- **Observation:** <describe the current state — what you see, what's wrong, what needs to change>
```

---

## Step 3: Code → Build → Checkpoint (repeat)

For each meaningful change:

### 3a. Make the code change

Follow the project's coding standards and conventions (its AGENTS.md, CLAUDE.md, etc.). Remo does not change how you write code — only how you verify it.

### 3b. Build and deploy

Use the project's own build commands (e.g., `make ios_build`, `xcodebuild`, etc.). Remo does not handle building.

### 3c. Checkpoint — capture and assess

After the app reloads with your changes:

```bash
# Screenshot
remo screenshot -a $ADDR -o .remo/verifications/<task-id>/assets/01-<description>.jpg

# View tree (if layout changed)
remo tree -a $ADDR -m 5

# Invoke capabilities to check state (if relevant)
remo call -a $ADDR "<capability>" '<params>'
```

**Read the screenshot** to see the actual result. Compare with your expectation. Assess: **pass** or **fail**.

Append to the report:

```markdown
### Step 1: <what you changed>
- **Action:** <what code was modified and why>
- **Build:** ✓ Succeeded | ✗ Failed (<error>)
- **Screenshot:** ![step-01](assets/01-<description>.jpg)
- **Observation:** <what you see in the screenshot — be specific>
- **Status:** ✓ Pass | ✗ Fail — <reason>
```

If a step **fails**, iterate: fix the code, rebuild, checkpoint again. Each attempt gets its own numbered entry in the timeline.

### 3d. Navigate and verify related screens

Use capabilities or built-in commands to navigate to other screens that might be affected:

```bash
# Navigate via capability
remo call -a $ADDR "navigate" '{"route":"profile"}'
remo screenshot -a $ADDR -o .remo/verifications/<task-id>/assets/02-profile-check.jpg

# Or inspect the view tree to understand the navigation state
remo tree -a $ADDR -m 3
```

---

## Step 4: Write the Report Summary

After all steps are complete, append a summary to the report:

```markdown
## Summary

| Step | Description | Status |
|------|------------|--------|
| 0 | Baseline | ✓ Captured |
| 1 | <change description> | ✓ Pass |
| 2 | <related screen check> | ✓ Pass |

- **Total steps:** N
- **Passed:** N
- **Failed:** 0
```

The final report lives at `.remo/verifications/<task-id>/report.md` with all screenshot assets alongside it. This is reviewable by the user or any future reviewer.

---

## Adding Verification Nodes (Custom Capabilities)

Built-in capabilities (`__screenshot`, `__view_tree`, `__device_info`, `__app_info`, `__ping`) cover visual and structural inspection. But for deeper verification, you can **register custom capabilities** as verification nodes — hooks into the app's internal state that you can query at each checkpoint.

### When to Add a Verification Node

- You need to check internal state that isn't visible on screen (e.g., is a cache populated? is the user logged in?)
- You need to navigate to a specific screen programmatically
- You need to set up a specific state to verify against (e.g., empty list, error state, logged-out state)
- You want to read a computed value (e.g., item count, scroll offset, animation state)

### How to Add One

Write a capability in Swift, inside `#if DEBUG`:

```swift
#if DEBUG
import RemoSwift

// Query node — read internal state
Remo.register("verify.feed_count") { _ in
    let count = FeedRepository.shared.items.count
    return ["count": count]
}

// Action node — set up a specific state
Remo.register("verify.set_empty_state") { _ in
    await MainActor.run {
        FeedRepository.shared.clearAll()
    }
    return ["status": "cleared"]
}

// Navigation node — jump to a screen
Remo.register("verify.go_to") { params in
    guard let screen = params["screen"] as? String else {
        return ["error": "missing 'screen'"]
    }
    await MainActor.run {
        AppRouter.shared.navigate(to: screen)
    }
    return ["status": "navigated", "screen": screen]
}
#endif
```

### Use in a Checkpoint

```bash
# Set up empty state
remo call -a $ADDR "verify.set_empty_state" '{}'
remo screenshot -a $ADDR -o .remo/verifications/<task-id>/assets/03-empty-state.jpg

# Check internal state after action
remo call -a $ADDR "verify.feed_count" '{}'
# → {"count": 0}
```

Record both the capability result and the screenshot in the report.

### Suggesting Nodes to the User

When you identify a verification gap — something you can't confirm visually or through existing capabilities — suggest adding a verification node:

> "I can see the profile screen looks correct, but I can't verify that the follow count is actually updated in the data layer. Would you like me to register a `verify.follow_count` capability to check that?"

---

## Verification Modes

Remo supports different verification needs depending on the task:

### Visual Verification (most common)

Screenshot before and after. Compare visually.

```bash
remo screenshot -a $ADDR -o .remo/verifications/<task-id>/assets/before.jpg
# ... make changes, rebuild ...
remo screenshot -a $ADDR -o .remo/verifications/<task-id>/assets/after.jpg
```

### Structural Verification

Inspect the view tree to verify layout structure, view nesting, or the presence/absence of specific views.

```bash
remo tree -a $ADDR -m 5
```

Look for: correct view class names, expected nesting depth, non-zero frames, visibility flags.

### State Verification

Use capabilities to query internal state and verify data correctness.

```bash
remo call -a $ADDR "verify.feed_count" '{}'
remo call -a $ADDR "verify.user_state" '{}'
```

### Multi-Screen Verification

Navigate through multiple screens to verify a change doesn't break related views.

```bash
remo call -a $ADDR "verify.go_to" '{"screen":"feed"}'
remo screenshot -a $ADDR -o .../assets/check-feed.jpg

remo call -a $ADDR "verify.go_to" '{"screen":"profile"}'
remo screenshot -a $ADDR -o .../assets/check-profile.jpg

remo call -a $ADDR "verify.go_to" '{"screen":"settings"}'
remo screenshot -a $ADDR -o .../assets/check-settings.jpg
```

---

## Commands Reference

| Command | Purpose | Example |
|---------|---------|---------|
| `remo devices` | Discover devices | `remo devices` |
| `remo screenshot` | Capture screen | `remo screenshot -a $ADDR -o path.jpg` |
| `remo tree` | View hierarchy | `remo tree -a $ADDR -m 5` |
| `remo call` | Invoke capability | `remo call -a $ADDR "name" '{}'` |
| `remo list` | List capabilities | `remo list -a $ADDR` |
| `remo info` | Device/app metadata | `remo info -a $ADDR` |
| `remo watch` | Stream events | `remo watch -a $ADDR` |
| `remo mirror` | Record video | `remo mirror -a $ADDR --save out.mp4` |

### Screenshot Options

- `-o <path>` — output file (default: `screenshot.jpg`)
- `-f jpeg|png` — format (default: `jpeg`)
- `-q 0.0-1.0` — JPEG quality (default: `0.8`)

### Tree Options

- `-m <depth>` — max depth (omit for full tree)

### Call Options

- `-t <seconds>` — timeout (default: `10`)

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `remo devices` empty | App not running or `Remo.start()` not called |
| Connection refused | Address changed — re-run `remo devices` |
| Capability not found | Check `remo list -a $ADDR` for available names |
| Screenshot is black | Bring simulator to foreground |
| Tree is huge | Use `remo tree -a $ADDR -m 3` |
| Call timeout | Increase with `-t 30` |

---

## `.remo/` Directory Structure

```
.remo/
└── verifications/
    ├── fix-avatar-radius/
    │   ├── report.md              # Verification timeline
    │   └── assets/
    │       ├── 00-baseline.jpg
    │       ├── 01-after-fix.jpg
    │       └── 02-profile-check.jpg
    ├── add-settings-screen/
    │   ├── report.md
    │   └── assets/
    │       ├── 00-baseline.jpg
    │       ├── 01-settings-layout.jpg
    │       └── 02-navigation-check.jpg
    └── ...
```

Add `.remo/` to `.gitignore` if verification artifacts should not be committed, or commit them if the team wants reviewable evidence in the repo history.

