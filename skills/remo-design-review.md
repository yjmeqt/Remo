---
name: remo-design-review
description: Compare running iOS app against Figma designs. Analyze Figma to identify required screens, build capabilities to construct each screen's state, capture screenshots, and produce a side-by-side design compliance report.
type: rigid
---

# Remo Design Review — Figma ↔ App Compliance

This skill compares the running iOS app against Figma designs. It analyzes the design file to identify required screens, constructs the exact app state needed for each screen (specific data, auth state, navigation), captures screenshots via Remo, and produces a side-by-side compliance report.

> **Prerequisites:**
> - Remo SDK integrated and app running (`remo-setup`)
> - Remo CLI available at `.remo/bin/remo` (project-local) or `remo` (global)
> - Figma MCP server available (for `get_design_context`, `get_screenshot`)
> - Capabilities registered or ready to be added (`remo-capabilities`)

---

## Workflow

```
Figma Analysis → State Design → Capability Build → Capture → Compare → Report
```

---

## Step 1: Analyze Figma — Identify Target Screens

### 1a. Get the design file

The user provides a Figma URL. Parse it to extract `fileKey` and `nodeId`:

```
figma.com/design/:fileKey/:fileName?node-id=:nodeId
```

Convert `-` to `:` in `nodeId`.

### 1b. Fetch design context

Use Figma MCP to retrieve the design structure:

```
get_design_context(fileKey, nodeId)
get_screenshot(fileKey, nodeId)
```

### 1c. Build the screen inventory

From the Figma file, identify every distinct screen/state that needs to be verified. For each screen, extract:

| Field | Description |
|-------|-------------|
| **Screen name** | Human-readable name (e.g., "Feed - Loaded", "Profile - Own") |
| **Figma node** | The specific nodeId for this frame |
| **State requirements** | What data/auth/navigation state the app needs to be in |
| **Variants** | If the design shows multiple states (empty, loaded, error, dark mode) |

**Example inventory:**

```markdown
| # | Screen | Figma Node | State Required |
|---|--------|-----------|----------------|
| 1 | Feed - Loaded | 123:456 | Logged in, feed has 10+ items with images |
| 2 | Feed - Empty | 123:789 | Logged in, feed is empty |
| 3 | Profile - Own | 124:100 | Logged in, has avatar, 50 followers, 3 posts |
| 4 | Profile - Other | 124:200 | Logged in, viewing another user with follow button |
| 5 | Settings | 125:100 | Logged in |
| 6 | Login | 126:100 | Logged out |
| 7 | Feed - Error | 123:900 | Logged in, network error state |
```

Present this inventory to the user for confirmation before proceeding.

---

## Step 2: Design State Requirements

For each screen in the inventory, define what state the app needs to be in. This is the most critical step — the accuracy of the comparison depends on matching the design's assumed state.

### State dimensions

| Dimension | Examples |
|-----------|---------|
| **Auth** | Logged out, guest, logged in (specific user) |
| **User data** | Username, avatar, follower/following counts, post count |
| **Content data** | Feed items (count, types, images), chat messages, notifications |
| **Navigation** | Which tab, which screen in the stack, modal state |
| **UI state** | Scroll position, expanded/collapsed, keyboard visible |
| **Appearance** | Light/dark mode, dynamic type size |

### Map each screen to required capabilities

For each screen, list what capabilities are needed to construct its state:

```markdown
### Screen 1: Feed - Loaded
- `state.auth.login_test_user` — login with a test account that has feed data
- `navigate.tab` → "feed" — switch to feed tab
- Wait for feed to load
- Verify: `state.feed.count` returns >= 10

### Screen 3: Profile - Own
- `state.auth.login_test_user` — login with test account
- `data.profile.set` → {"avatar": "...", "followers": 50, "posts": 3}
- `navigate.tab` → "profile"

### Screen 6: Login
- `state.auth.logout` — force logout
- App should show login screen automatically

### Screen 7: Feed - Error
- `state.auth.login_test_user`
- `data.feed.set_error` — force network error state
- `navigate.tab` → "feed"
```

---

## Step 3: Build Capabilities

Implement the capabilities needed to construct each screen's state. This extends the work from `remo-capabilities` skill.

### Test account management

Most screens require a logged-in user with specific data. Create capabilities to manage test accounts:

```swift
#if DEBUG
// Create or reuse a test account with specific attributes
Remo.register("design_review.setup_user") { params in
    let profile = params["profile"] as? [String: Any] ?? [:]

    await MainActor.run {
        // Login to test account
        TestAccountManager.loginTestUser()

        // Configure profile data if specified
        if let avatar = profile["avatar"] as? String {
            TestAccountManager.setAvatar(url: avatar)
        }
        if let followers = profile["followers"] as? Int {
            TestAccountManager.setFollowerCount(followers)
        }
    }
    return ["status": "ok"]
}

// Force logout to capture logged-out screens
Remo.register("design_review.logout") { _ in
    await MainActor.run {
        AuthManager.shared.logout()
    }
    return ["status": "ok"]
}
#endif
```

### Content/data state

```swift
#if DEBUG
// Seed feed with specific content for design review
Remo.register("design_review.seed_feed") { params in
    let count = params["count"] as? Int ?? 10
    let withImages = params["withImages"] as? Bool ?? true

    await MainActor.run {
        TestDataSeeder.seedFeed(count: count, withImages: withImages)
    }
    return ["status": "ok", "seeded": count]
}

// Force empty state
Remo.register("design_review.clear_feed") { _ in
    await MainActor.run {
        FeedRepository.shared.clearAll()
    }
    return ["status": "ok"]
}

// Force error state
Remo.register("design_review.force_error") { params in
    let screen = params["screen"] as? String ?? "feed"
    await MainActor.run {
        ErrorSimulator.simulateNetworkError(for: screen)
    }
    return ["status": "ok", "screen": screen]
}
#endif
```

### Navigation

```swift
#if DEBUG
Remo.register("design_review.navigate") { params in
    guard let screen = params["screen"] as? String else {
        return ["error": "missing 'screen'"]
    }

    await MainActor.run {
        switch screen {
        case "feed": MainTabBarController.shared?.switchToTab(.feed)
        case "profile": MainTabBarController.shared?.switchToTab(.profile)
        case "settings": MainTabBarController.shared?.pushSettings()
        // ... add more as needed
        default: break
        }
    }

    // Wait for navigation animation to settle
    try? await Task.sleep(for: .milliseconds(500))

    return ["status": "ok", "screen": screen]
}
#endif
```

### Implementation priority

Only implement capabilities required by the current screen inventory. Mark others as TODO. Use the `// TODO:` convention from `remo-capabilities`.

If a capability is too complex to implement (e.g., requires backend test account creation), note it in the report and skip that screen or use a manual workaround.

---

## Step 4: Capture — Screenshot Each Screen

For each screen in the inventory, execute the state setup and capture:

```bash
# Create output directory
mkdir -p .remo/design-reviews/<review-id>/assets/app
mkdir -p .remo/design-reviews/<review-id>/assets/figma

# Example: Screen 1 - Feed Loaded
remo call -a $ADDR "design_review.setup_user" '{"profile":{"followers":50}}'
remo call -a $ADDR "design_review.seed_feed" '{"count":10,"withImages":true}'
remo call -a $ADDR "design_review.navigate" '{"screen":"feed"}'
# Wait for content to render
sleep 1
remo screenshot -a $ADDR -o .remo/design-reviews/<review-id>/assets/app/01-feed-loaded.png --format png

# Example: Screen 6 - Login
remo call -a $ADDR "design_review.logout" '{}'
sleep 1
remo screenshot -a $ADDR -o .remo/design-reviews/<review-id>/assets/app/06-login.png --format png
```

**Use PNG format** for design comparison — lossless quality matters for pixel accuracy.

**Wait after state changes** — some state transitions need time for UI to settle (animations, data loading). Use `sleep 0.5-2` as needed.

Also save the Figma screenshots for each corresponding screen:

```
get_screenshot(fileKey, nodeId_for_screen_1)
→ save to .remo/design-reviews/<review-id>/assets/figma/01-feed-loaded.png
```

---

## Step 5: Compare — Assess Each Screen

For each screen, read both images (Figma design and app screenshot) and assess compliance.

### What to compare

| Aspect | What to look for |
|--------|-----------------|
| **Layout** | Spacing, alignment, padding, margins |
| **Typography** | Font family, size, weight, line height, color |
| **Colors** | Background, text, accent, border colors |
| **Components** | Button style, card shape, avatar shape, icon usage |
| **Content** | Placeholder text matches, image aspect ratios |
| **State** | Correct elements shown/hidden for the state |
| **Navigation** | Tab bar highlight, back button, header title |

### Assessment scale

For each screen, rate compliance:

- **✓ Match** — design and app are visually consistent
- **△ Minor deviation** — small differences that may be intentional or acceptable (e.g., dynamic data vs placeholder, platform-specific rendering)
- **✗ Mismatch** — clear visual discrepancy that needs to be fixed

For each deviation or mismatch, describe:
- What specifically is different
- Where in the screen (top/middle/bottom, which component)
- Severity (cosmetic, functional, blocking)

---

## Step 6: Report

Write the design review report at `.remo/design-reviews/<review-id>/report.md`:

```markdown
# Design Review: <feature/page name>

- **Date:** <YYYY-MM-DD>
- **Figma:** <figma URL>
- **Branch:** <git branch>
- **Device:** <simulator name> (<OS version>)
- **Reviewer:** AI Agent (Remo)

## Screen Inventory

| # | Screen | Status | Issues |
|---|--------|--------|--------|
| 1 | Feed - Loaded | ✓ Match | — |
| 2 | Feed - Empty | △ Minor | Placeholder text differs |
| 3 | Profile - Own | ✗ Mismatch | Avatar corner radius wrong, follower count font |
| 4 | Profile - Other | ✓ Match | — |
| 5 | Settings | △ Minor | Divider color slightly off |
| 6 | Login | ✓ Match | — |
| 7 | Feed - Error | ⊘ Skipped | Error state capability not implemented |

## Detailed Comparison

### Screen 1: Feed - Loaded — ✓ Match

| Figma | App |
|-------|-----|
| ![figma](assets/figma/01-feed-loaded.png) | ![app](assets/app/01-feed-loaded.png) |

Layout, typography, and colors are consistent with the design.

---

### Screen 3: Profile - Own — ✗ Mismatch

| Figma | App |
|-------|-----|
| ![figma](assets/figma/03-profile-own.png) | ![app](assets/app/03-profile-own.png) |

**Issues found:**

1. **Avatar corner radius** — Design shows fully circular (cornerRadius = width/2), app shows rounded rect (cornerRadius = 12). Location: profile header, avatar image.
   - Severity: **Medium** — visually noticeable
   - Fix: Update `ProfileAvatarView.swift` cornerRadius

2. **Follower count font** — Design uses Poppins SemiBold 16pt, app appears to use Rethink Sans Medium 14pt. Location: stats row below avatar.
   - Severity: **Low** — subtle but inconsistent with design system
   - Fix: Check `ProfileStatsView.swift` font token

---

### Screen 7: Feed - Error — ⊘ Skipped

Capability `design_review.force_error` not yet implemented. Added to `.remo/capabilities.md` TODO list.

---

## Summary

- **Total screens:** 7
- **Match:** 3
- **Minor deviation:** 2
- **Mismatch:** 1 (2 issues found)
- **Skipped:** 1

## Action Items

| Priority | Issue | Screen | Fix |
|----------|-------|--------|-----|
| Medium | Avatar corner radius | Profile - Own | Update ProfileAvatarView.swift |
| Low | Follower count font | Profile - Own | Check ProfileStatsView font token |
| — | Implement error state capability | Feed - Error | Add design_review.force_error |
```

---

## Maintaining Design Reviews

### When to re-run

- After fixing issues found in a previous review
- After implementing new screens that have Figma designs
- After a design system update (colors, fonts, spacing)
- Before a release — final compliance check

### Incremental reviews

For re-runs, only re-capture screens that were changed or previously had issues. Reference the previous report:

```markdown
## Re-review: Profile - Own (follow-up from <previous review date>)

Previously: ✗ Mismatch (avatar radius, font)
Now: ✓ Match — both issues fixed in commit <sha>
```

### Connecting to remo-capabilities

When a screen is skipped because a required capability doesn't exist:

1. Add it to `.remo/capabilities.md` TODO table
2. Note it in the design review report
3. Suggest to the user: "Screen X was skipped because we can't construct its state yet. Want me to implement the `design_review.force_error` capability?"

---

## Directory Structure

```
.remo/
├── capabilities.md                         # Capabilities reference
├── design-reviews/
│   ├── feed-redesign-2026-03/
│   │   ├── report.md                       # Comparison report
│   │   └── assets/
│   │       ├── figma/                      # Design screenshots
│   │       │   ├── 01-feed-loaded.png
│   │       │   └── 03-profile-own.png
│   │       └── app/                        # App screenshots
│   │           ├── 01-feed-loaded.png
│   │           └── 03-profile-own.png
│   └── profile-update-2026-04/
│       ├── report.md
│       └── assets/...
└── verifications/                          # From remo skill
```

---

## Checklist

- [ ] Get Figma URL from user
- [ ] Fetch design context and screenshots from Figma
- [ ] Build screen inventory with state requirements
- [ ] Confirm inventory with user
- [ ] Identify needed capabilities for state construction
- [ ] Implement capabilities (or mark TODO for complex ones)
- [ ] For each screen: set state → navigate → wait → screenshot
- [ ] Save Figma screenshots alongside app screenshots
- [ ] Compare each screen: layout, typography, colors, components
- [ ] Rate each screen: match / minor deviation / mismatch / skipped
- [ ] Write detailed findings for deviations and mismatches
- [ ] Generate action items with priority and fix suggestions
- [ ] Update `.remo/capabilities.md` if new TODOs were found
