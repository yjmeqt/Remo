---
name: remo-setup
description: One-time integration of Remo SDK into an iOS project. Use when the project has not yet added Remo as a dependency.
type: rigid
---

# Remo Setup — Integrate Remo SDK into an iOS Project

This skill walks you through adding the Remo SDK to an existing iOS project so that AI agents gain eyes and hands: screenshots, view-tree inspection, capability invocation, and screen mirroring.

> **Run this skill once per project.** After setup, use the `remo` skill for daily workflows.

---

## Prerequisites

Before you begin, verify:

1. **The iOS project builds and runs** on a simulator. This skill does not handle build setup — that is the project's own responsibility.

2. **You have identified the app entry point** — either `AppDelegate` (UIKit) or the `@main` App struct (SwiftUI).

---

## Step 1 — Install Remo CLI

Install the Remo CLI binary to the project-local `.remo/bin/` directory. This keeps the CLI version pinned to the project and avoids requiring a global install.

### 1a. Download and install locally

```bash
curl -fsSL https://github.com/yjmeqt/Remo/releases/latest/download/install-remo.sh \
  | REMO_INSTALL_PREFIX=.remo bash
```

This downloads the correct binary for the current architecture (arm64/x86_64), verifies the SHA-256 checksum, and installs to `.remo/bin/remo`.

### 1b. Verify the installation

```bash
.remo/bin/remo --version
```

### 1c. (Optional) Install globally

If the user prefers a system-wide install, offer these options:

```bash
# Option A: Homebrew (recommended — handles updates automatically)
brew install yjmeqt/tap/remo

# Option B: Copy the local binary to a system path
cp .remo/bin/remo /usr/local/bin/remo
```

When installed globally, you can use `remo` directly instead of `.remo/bin/remo`.

### 1d. Pin the version (optional)

To install a specific version instead of latest:

```bash
curl -fsSL https://github.com/yjmeqt/Remo/releases/latest/download/install-remo.sh \
  | REMO_INSTALL_PREFIX=.remo bash -s -- --version 0.4.3
```

### CLI resolution convention

All `remo` commands in the Remo skills refer to the CLI binary. The agent should resolve it in this order:

1. `.remo/bin/remo` — project-local (preferred)
2. `remo` — global (PATH)

If neither is found, run this step first.

---

## Step 2 — Add the SDK Dependency

### Swift Package Manager (recommended)

Add the Remo SPM package to the project. The exact method depends on the project structure:

**If the project uses a `Package.swift` (e.g., a local SPM package or app-as-package):**

Add to the `dependencies` array:
```swift
.package(url: "https://github.com/yjmeqt/remo-spm.git", from: "0.4.0"),
```

Then add `"RemoSwift"` to the relevant target's dependencies:
```swift
.product(name: "RemoSwift", package: "remo-spm"),
```

**If the project uses an `.xcodeproj` / `.xcworkspace` without a Package.swift at the app level:**

The agent cannot add SPM packages via code alone. Instruct the user:
> Add the Swift package `https://github.com/yjmeqt/remo-spm.git` to the Xcode project via File → Add Package Dependencies.

### CocoaPods (alternative)

Add to the `Podfile`:
```ruby
# Swift
pod 'Remo', :podspec => 'https://raw.githubusercontent.com/yjmeqt/remo-spm/main/Remo.podspec'

# Objective-C (if needed)
pod 'Remo/ObjC', :podspec => 'https://raw.githubusercontent.com/yjmeqt/remo-spm/main/Remo.podspec'
```

Then run `pod install`.

---

## Step 3 — Wire Remo in the App Lifecycle

Remo must only run in DEBUG builds. Add the startup call wrapped in `#if DEBUG`.

### UIKit (AppDelegate)

In `application(_:didFinishLaunchingWithOptions:)`:
```swift
#if DEBUG
import RemoSwift

// In didFinishLaunchingWithOptions:
Remo.start()
#endif
```

### SwiftUI (@main App)

In the `App` struct's `init()` or via an `.onAppear` on the root view:
```swift
#if DEBUG
import RemoSwift
#endif

@main
struct MyApp: App {
    init() {
        #if DEBUG
        Remo.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Important Notes

- `Remo.start()` is idempotent — calling it multiple times is safe.
- The SDK compiles to no-ops in Release builds, but wrapping in `#if DEBUG` is still recommended for clarity.
- On simulators, Remo uses Bonjour/mDNS for discovery (random port). On real devices, it uses USB on port 9930.

---

## Step 4 — Verify the Integration

1. Build and run the app on a simulator.
2. Discover the device:
   ```bash
   remo devices
   ```
   You should see the simulator listed with a Bonjour address.

3. Test connectivity:
   ```bash
   remo call -a <ADDRESS> "__ping" '{}'
   ```

4. Take a screenshot to confirm visual access:
   ```bash
   remo screenshot -a <ADDRESS> -o /tmp/remo-verify.jpg
   ```

5. Inspect the view hierarchy:
   ```bash
   remo tree -a <ADDRESS>
   ```

If all commands succeed, Remo is integrated. You can now use the `remo` skill for development, debugging, testing, and exploration.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `remo devices` shows nothing | App not running or Remo.start() not called | Ensure the app is running on simulator and Remo.start() is in the DEBUG code path |
| Connection refused | Wrong address | Re-run `remo devices` to get the current address (port changes each launch for simulators) |
| Capability call hangs | App is in background | Bring the simulator to foreground |
| Build error on `import RemoSwift` | SPM package not resolved | Run `xcodebuild -resolvePackageDependencies` or resolve in Xcode |

---

## What's Next

Use the **`remo`** skill to leverage Remo during your daily iOS development workflow — visual verification, debugging, testing, and codebase exploration.
