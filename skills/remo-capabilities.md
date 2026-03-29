---
name: remo-capabilities
description: Analyze an iOS project's features and routing, then map, register, and document Remo capabilities. Use when onboarding a project to Remo or when the app's screens/navigation have changed significantly.
type: rigid
---

# Remo Capabilities — Map, Register, Document

This skill analyzes an iOS project's feature structure and navigation, then creates a capabilities map: registering what can be automated now, leaving TODOs for what can't, and producing a reference document that stays in sync with the code.

> **Prerequisites:**
> - Remo SDK already integrated (`remo-setup`). This skill focuses on **what capabilities to register**, not how to install the SDK.
> - Remo CLI available at `.remo/bin/remo` (project-local) or `remo` (global).

---

## Workflow

```
Explore → Map → Implement → Document → Maintain
```

---

## Step 1: Explore — Understand the App

Read the project to build a mental model of its features and routing.

### 1a. Read project documentation

Start with the project's own docs:
- `AGENTS.md` / `CLAUDE.md` — architecture, feature boundaries, conventions
- `ARCHITECTURE.md` or equivalent — runtime component map
- `README.md` — feature list, project structure

### 1b. Identify feature domains

List the app's feature domains. Typical iOS app domains include:

- **Navigation** — tab bar, navigation stacks, modal presentation, deep links
- **Auth** — login, logout, session state, guest mode
- **Feed / Content** — list screens, detail screens, pagination state
- **Profile** — own profile, other user profiles, edit flows
- **Settings** — preferences, account management
- **Upload / Creation** — content creation flows, drafts
- **Messaging / Chat** — conversations, notifications
- **Search** — search flows, filters

For each domain, note:
- Entry points (how users reach this feature)
- Key screens (what views/controllers exist)
- State that affects the UI (logged in/out, empty/loaded, error)

### 1c. Map the routing structure

Identify how navigation works:
- **Tab-based:** which tabs exist and their root controllers
- **Push navigation:** which screens push onto navigation stacks
- **Modal presentation:** which screens are presented modally
- **Deep links:** is there a URL scheme or universal link handler?
- **Programmatic navigation:** are there existing navigation helpers (e.g., `AppRouter`, `MainTabBarController.push...()`, `DeepLinkManager`)?

### 1d. Run the app and observe

If the app is running with Remo:

```bash
# See current screen
remo screenshot -a $ADDR -o /tmp/explore-current.jpg

# Inspect view hierarchy to understand navigation structure
remo tree -a $ADDR -m 4

# Check what capabilities already exist
remo list -a $ADDR
```

---

## Step 2: Map — Design the Capabilities

Based on your exploration, design a capabilities map organized by domain. Each capability falls into one of these categories:

### Category: Navigate

Jump to specific screens programmatically. Essential for multi-screen verification.

```
navigate.tab.<name>        → Switch to a tab
navigate.push.<screen>     → Push a screen onto the current navigation stack
navigate.present.<screen>  → Present a screen modally
navigate.back              → Pop / dismiss the current screen
navigate.deep_link         → Trigger a deep link URL
```

### Category: State

Read or write internal state for verification and test setup.

```
state.auth.get             → Current auth status (logged in, user ID, token validity)
state.auth.set_logged_in   → Force a logged-in state (test user)
state.auth.set_logged_out  → Force logout
state.cache.clear          → Clear all caches
state.onboarding.reset     → Reset onboarding flags
state.<domain>.get         → Read domain-specific state
state.<domain>.set         → Write domain-specific state
```

### Category: Data

Seed or manipulate test data.

```
data.feed.seed             → Insert mock feed items
data.feed.clear            → Clear feed data
data.feed.set_empty        → Force empty state
data.feed.set_error        → Force error state
data.<domain>.seed         → Seed domain data
data.<domain>.clear        → Clear domain data
```

### Category: UI

Trigger UI actions or read UI state.

```
ui.scroll_to_top           → Scroll the current list to top
ui.scroll_to_bottom        → Scroll to bottom
ui.pull_to_refresh         → Trigger pull-to-refresh
ui.dismiss_keyboard        → Dismiss any active keyboard
ui.get_visible_cells       → Return info about visible list cells
```

### Prioritization

Not every capability is worth implementing immediately. Prioritize:

1. **Navigation** — highest value, enables multi-screen verification
2. **State reading** — query auth status, feature flags, etc.
3. **State writing** — set up test scenarios (empty, error, logged out)
4. **Data seeding** — useful for testing but often complex to implement
5. **UI actions** — nice to have, lower priority

---

## Step 3: Implement — Register Capabilities

Create a dedicated file for Remo capabilities, separate from production code:

**Suggested location:** `<project>/Debug/RemoCapabilities.swift` or `<project>/Support/RemoCapabilities.swift`

Wrap everything in `#if DEBUG`:

```swift
#if DEBUG
import RemoSwift

enum RemoCapabilities {
    static func registerAll() {
        registerNavigation()
        registerState()
        registerData()
    }
}

// MARK: - Navigation

extension RemoCapabilities {
    static func registerNavigation() {
        Remo.register("navigate.tab") { params in
            guard let tab = params["tab"] as? String else {
                return ["error": "missing 'tab' parameter"]
            }
            await MainActor.run {
                // Adapt to the project's tab switching mechanism
                MainTabBarController.shared?.switchTo(tab: tab)
            }
            return ["status": "ok", "tab": tab]
        }

        Remo.register("navigate.back") { _ in
            await MainActor.run {
                // Adapt to the project's navigation pattern
                let nav = UIApplication.topNavigationController()
                nav?.popViewController(animated: false)
            }
            return ["status": "ok"]
        }

        // TODO: navigate.push.<screen> — needs router integration
        // TODO: navigate.deep_link — needs DeepLinkManager access
    }
}

// MARK: - State

extension RemoCapabilities {
    static func registerState() {
        Remo.register("state.auth.get") { _ in
            let user = AuthManager.shared.currentUser
            return [
                "isLoggedIn": user != nil,
                "userId": user?.id ?? "",
                "username": user?.username ?? ""
            ]
        }

        // TODO: state.auth.set_logged_in — requires mock auth flow
        // TODO: state.cache.clear — identify all cache managers
    }
}

// MARK: - Data

extension RemoCapabilities {
    static func registerData() {
        // TODO: data.feed.seed — requires ContentRepository access
        // TODO: data.feed.set_empty — requires clearing feed state
    }
}
#endif
```

Then call `RemoCapabilities.registerAll()` right after `Remo.start()`:

```swift
#if DEBUG
Remo.start()
RemoCapabilities.registerAll()
#endif
```

### Implementation rules

- **One file per project** — keep all capabilities in a single file (or a small group) for discoverability
- **Always `#if DEBUG`** — capabilities must never ship in release builds
- **`await MainActor.run`** — any UIKit access must be on the main thread
- **Return structured JSON** — always return a dict with at least `"status"` or `"error"`
- **Mark TODOs clearly** — if a capability is too complex or risky to implement now, leave a `// TODO:` with the reason and what would be needed
- **Adapt to the project** — use the project's actual class names, singletons, navigation patterns. Do not invent abstractions.

---

## Step 4: Document — Write the Capabilities Reference

Create `.remo/capabilities.md` as the single source of truth for what capabilities are available.

```markdown
# Remo Capabilities Reference

> Auto-generated by remo-capabilities skill. Keep in sync with `RemoCapabilities.swift`.
> Last updated: <YYYY-MM-DD>

## Registered

| Capability | Category | Description | Parameters |
|-----------|----------|-------------|------------|
| `navigate.tab` | Navigate | Switch to a tab | `{"tab": "feed\|profile\|messages"}` |
| `navigate.back` | Navigate | Pop/dismiss current screen | `{}` |
| `state.auth.get` | State | Get current auth status | `{}` |

## TODO (not yet registered)

| Capability | Category | Reason | Blocked by |
|-----------|----------|--------|------------|
| `navigate.push.profile` | Navigate | Needs router access | Router refactor |
| `navigate.deep_link` | Navigate | Needs DeepLinkManager integration | — |
| `state.auth.set_logged_in` | State | Requires mock auth token flow | Auth module access |
| `state.cache.clear` | State | Multiple cache managers to identify | Code audit needed |
| `data.feed.seed` | Data | Requires ContentRepository access | — |
| `data.feed.set_empty` | Data | Requires clearing feed state | — |

## Built-in (always available)

| Capability | Description |
|-----------|-------------|
| `__ping` | Connectivity check |
| `__list_capabilities` | List all capabilities |
| `__view_tree` | View hierarchy as JSON |
| `__screenshot` | Capture screen |
| `__device_info` | Device model, OS, screen info |
| `__app_info` | Bundle ID, version, build |
| `__start_mirror` / `__stop_mirror` | Screen mirroring |
```

---

## Step 5: Maintain — Keep Docs in Sync

### When to update `.remo/capabilities.md`

- **After registering a new capability** — move it from TODO to Registered
- **After removing a capability** — remove it from Registered
- **After changing a capability's parameters** — update the Parameters column
- **After a feature refactor that changes navigation or state** — re-audit the map

### When to suggest new capabilities

During normal development (using the `remo` skill), if you encounter a situation where a capability would have been useful but doesn't exist, **add it to the TODO section** of `capabilities.md` with context:

```markdown
| `navigate.push.settings` | Navigate | Needed during settings screen verification | — |
```

Then inform the user:

> "I've added `navigate.push.settings` to the capabilities TODO list. It would make verifying the settings screen faster. Want me to implement it now?"

### When to re-run this skill

- Major navigation refactor (tabs added/removed, routing changed)
- New feature domain added to the app
- Significant architecture change (e.g., migrating from singletons to DI)

---

## Checklist

Use this to track progress when running this skill:

- [ ] Read project docs (AGENTS.md, ARCHITECTURE.md, README.md)
- [ ] Identify feature domains and key screens
- [ ] Map routing structure (tabs, push, modal, deep links)
- [ ] Run app and observe with `remo screenshot` / `remo tree` / `remo list`
- [ ] Design capabilities map (navigate, state, data, ui)
- [ ] Create `RemoCapabilities.swift` with `#if DEBUG`
- [ ] Register navigation capabilities (highest priority)
- [ ] Register state-reading capabilities
- [ ] Leave TODOs for complex/risky capabilities
- [ ] Wire `RemoCapabilities.registerAll()` after `Remo.start()`
- [ ] Verify registered capabilities work: `remo list`, `remo call`
- [ ] Write `.remo/capabilities.md` reference
- [ ] Add `.remo/` to `.gitignore` or commit as needed
