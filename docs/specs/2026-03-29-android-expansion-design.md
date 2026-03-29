# Android Platform Expansion Design

> **Status:** TODO — forward-looking design, not for immediate implementation
> **Date:** 2026-03-29
> **Goal:** Expand Remo from iOS-only to support Android, enabling AI agents to control Android apps with the same capabilities as iOS

## Motivation

1. **Agent capability parity** — AI agents should be able to control Android apps the same way they control iOS apps
2. **Market reach** — many SDK users develop for both platforms and need unified tooling
3. **Contributor accessibility** — the repo should be welcoming to developers of all backgrounds (Rust, iOS, Android, Web)

## Architecture: Parallel Crates (Approach A)

Add Android-specific crates alongside existing iOS ones. Shared core stays untouched. No refactoring of existing iOS code required.

```
crates/
  ── Shared (no change) ──────────────
  remo-protocol/        # JSON-RPC framing, message types
  remo-transport/       # TCP connection, listener
  remo-sdk/             # Server + capability registry + FFI
  remo-bonjour/         # mDNS discovery

  ── iOS only (no change) ────────────
  remo-objc/            # ObjC runtime bridge (UIKit)
  remo-usbmuxd/         # USB device discovery (macOS)

  ── Android (NEW) ───────────────────
  remo-jni/             # JNI bridge: screenshot, view tree, video, app/device info
  remo-adb/             # ADB wrapper: device listing, port forwarding

  ── Desktop (extend) ────────────────
  remo-desktop/         # Add Android device manager alongside iOS
  remo-daemon/          # Unified connection pool for both platforms
  remo-cli/             # Unified CLI: `remo devices` shows both

android/
  RemoAndroid/          # Kotlin SDK wrapper (thin, ~100 LOC)
  examples/             # Android example app
```

### Why Parallel Crates

- Clean separation — iOS code untouched
- Maximum code reuse in protocol/transport/registry layers
- Each crate can be developed and tested independently
- Natural contributor boundaries (see below)

## SDK Layer Comparison

| Layer | iOS (today) | Android (new) |
|---|---|---|
| Public API | Swift (~100 LOC) | Kotlin (~100 LOC), Java interop guaranteed |
| Native bridge | `remo-objc` (ObjC runtime via `objc2`) | `remo-jni` (Android APIs via JNI) |
| Built-in capabilities | UIKit screenshot, UIView tree, H.264 via ObjC | PixelCopy screenshot, View tree, MediaCodec H.264 |
| Distribution | SPM + CocoaPods (XCFramework) | Maven Central / GitHub Packages (AAR with `.so`) |
| Debug-only guard | `#if DEBUG` | `BuildConfig.DEBUG` check |
| Design philosophy | Maximize Rust, thin Swift wrapper | Maximize Rust, thin Kotlin wrapper |

## Built-in Capabilities — Android Implementation

Performance matters for agent iteration loops (`screenshot → analyze → act → repeat`), so all performance-critical capabilities are implemented in-app via the SDK, not via ADB.

| Capability | Android API | Called from | Why in-app |
|---|---|---|---|
| `__screenshot` | `PixelCopy` / `View.drawToBitmap()` | Rust via JNI | ~100ms vs ~1-2s via ADB |
| `__view_tree` | `View.getRootView()` traversal | Rust via JNI | Needs app context |
| `__device_info` | `Build.MODEL`, `Build.VERSION` | Rust via JNI | Trivial |
| `__app_info` | `PackageManager` | Rust via JNI | Needs app context |
| `__start_mirror` | `MediaCodec` H.264 encoder | Rust via JNI | Real-time streaming |
| Custom capabilities | Same registry as iOS | Rust `remo-sdk` (shared) | Core architecture |

### Performance: ADB vs In-App

| | ADB (external) | In-app (SDK) |
|---|---|---|
| Screenshot latency | ~1-2s (spawn process + PNG + USB) | ~50-100ms (GPU readback + JPEG + TCP) |
| Video latency | ~200-500ms startup | Real-time, ~16ms/frame |
| Format control | PNG only, limited | JPEG/PNG, custom quality/resolution |
| Scope | Full screen only | Can capture specific View |

## Device Discovery & Connection

### ADB-Based (Primary)

The desktop side uses ADB for device discovery and TCP tunneling, analogous to how `remo-usbmuxd` uses usbmuxd for iOS.

```
1. adb devices               ← discover Android devices (real + emulator)
2. adb forward tcp:LOCAL tcp:9930   ← tunnel to Remo SDK's server port
3. Connect over TCP           ← same JSON-RPC protocol as iOS
```

**ADB integration approach:**
- **Primary:** Shell out to `adb` binary (same pattern as scrcpy — require `adb` on PATH)
- **Future option:** Native Rust ADB protocol implementation (`remo-adb` crate) for zero external dependencies

### Comparison with iOS

| | iOS (today) | Android (new) |
|---|---|---|
| Real device | `remo-usbmuxd` (macOS usbmuxd socket) | `remo-adb` (shell out to `adb`) |
| Emulator/Simulator | `remo-bonjour` (mDNS) | `remo-adb` (`adb devices`) |
| Tunnel | usbmuxd TCP relay | `adb forward tcp:LOCAL tcp:9930` |

## Contributor Boundaries

A first-class design goal: contributors should NOT need cross-platform expertise. Each zone has its own README, build instructions, and can be developed/tested independently.

```
┌─────────────────────────────────────────────────┐
│  "I know Rust"                                  │
│  → remo-protocol, remo-transport, remo-sdk,     │
│    remo-adb, remo-desktop, remo-cli             │
├─────────────────────────────────────────────────┤
│  "I know Android (Kotlin/Java)"                 │
│  → android/RemoAndroid (Kotlin wrapper),         │
│    android/examples, remo-jni (JNI helpers)     │
├─────────────────────────────────────────────────┤
│  "I know iOS (Swift)"                           │
│  → swift/RemoSwift, examples/ios                │
├─────────────────────────────────────────────────┤
│  "I know Web (React/TS)"                        │
│  → website/, dashboard UI                       │
└─────────────────────────────────────────────────┘
```

**Risk:** The initial `remo-jni` implementation requires someone with both Rust + Android expertise (rare combo). After that, maintenance is mostly independent — Rust core changes rarely break the thin JNI layer, and Kotlin API changes don't require Rust knowledge.

## Distribution

| Channel | Format | Registry |
|---|---|---|
| Gradle (primary) | AAR containing `.so` + Kotlin sources | Maven Central or GitHub Packages |
| Direct download | AAR from GitHub Releases | Same release workflow as iOS XCFramework |

## CI/CD Additions

- `ci.yml`: Add Android lint + unit test job (Gradle)
- `e2e.yml`: Add Android emulator E2E job (similar to iOS simulator job)
- `release.yml`: Build `.so` for `aarch64-linux-android` + `x86_64-linux-android`, package AAR, publish

## Open Design Decisions

To be resolved when implementation begins:

1. **ADB integration:** Shell out to `adb` (primary) vs native Rust ADB protocol (future zero-dependency option)
2. **NDK version:** Which minimum Android NDK to target
3. **Minimum Android version:** API 24 (Android 7)? API 26 (Android 8)?
4. **Cross-compilation toolchain:** `cargo-ndk` vs manual NDK toolchain setup
5. **JNI ergonomics:** `jni` crate vs `robusta` vs raw JNI
6. **Unified CLI UX:** How `remo devices` presents mixed iOS + Android device lists
7. **Protocol extensions:** Any Android-specific capabilities beyond the iOS set (e.g., Intent triggering, Activity lifecycle)
