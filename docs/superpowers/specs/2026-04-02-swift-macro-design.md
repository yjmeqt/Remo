# Swift Macro for Remo Capability Registration

**Date:** 2026-04-02
**Status:** Approved

## Problem

Remo capability registration code has three pain points:

1. **No dead-code elimination.** `Remo.register(...)` compiles in release builds as a no-op stub, but the closure body and surrounding code still ship in the binary. Developers expect debug tooling to vanish completely, like `#Preview`.

2. **Tedious parameter parsing.** Handlers receive `[String: Any]` and must manually cast each parameter:
   ```swift
   Remo.register("counter.increment") { params in
       let amount = params["amount"] as? Int ?? 1  // verbose, error-prone
       ...
   }
   ```

3. **Manual lifecycle management.** Capabilities must be manually registered and unregistered to match view visibility. Forgetting to unregister causes stale capabilities; mismatched names cause silent bugs:
   ```swift
   // SwiftUI — must manually pair .task with .onDisappear
   .task { registerHomeCapabilities(store: store) }
   .onDisappear { Remo.unregister("counter.increment") }

   // UIKit — must remember to unregister in viewDidDisappear
   override func viewDidAppear(_ animated: Bool) {
       super.viewDidAppear(animated)
       Remo.register("counter.increment") { ... }
   }
   override func viewDidDisappear(_ animated: Bool) {
       super.viewDidDisappear(animated)
       Remo.unregister("counter.increment")
   }
   ```

## Solution

A `#remo` Swift macro (freestanding expression) that:
- Strips all enclosed code from release builds (true dead-code elimination)
- Generates type-safe parameter extraction from typed closure parameters
- Provides automatic visibility-scoped lifecycle management for both SwiftUI and UIKit
- Ships inside the existing `RemoSwift` package — `import RemoSwift` gives you `#remo`

**Scoping rule:** Only the top-visible view/VC's capabilities are registered. Pushing a new screen unregisters the previous screen's capabilities. Popping re-registers them.

## Syntax

### Inline form — single capability with typed parameters

```swift
// Typed params: macro extracts from [String: Any] for you
#remo("counter.increment") { (amount: Int = 1) in
    store.counter += amount
    return ["status": "ok"]
}

// Multiple params
#remo("state.set") { (key: String, value: String = "") in
    store.setValue(value, forKey: key)
    return ["status": "ok"]
}

// No params
#remo("items.clear") {
    store.items.removeAll()
    return ["status": "ok"]
}
```

### Block form — group multiple registrations

```swift
#remo {
    Remo.register("counter.increment") { ... }
    Remo.register("counter.decrement") { ... }
}
```

## Macro Expansion

Swift macros expand identically regardless of build configuration — a macro cannot check `#if DEBUG` at expansion time. Instead, the macro wraps its expansion in an immediately-invoked closure containing `#if DEBUG`, which the compiler evaluates at build time.

### Inline form expansion

```swift
// Source:
#remo("counter.increment") { (amount: Int = 1) in
    store.counter += amount
    return ["status": "ok"]
}

// Always expands to (same in all builds):
{
    #if DEBUG
    Remo.register("counter.increment") { (__params: [String: Any]) -> [String: Any] in
        let amount = __params["amount"] as? Int ?? 1
        store.counter += amount
        return ["status": "ok"]
    }
    #endif
}()
```

In DEBUG builds, the `#if DEBUG` block compiles normally. In RELEASE builds, the compiler strips the entire block — the closure body becomes empty, achieving true dead-code elimination at the source level (not optimizer-dependent).

### Block form expansion

```swift
// Source:
#remo {
    Remo.register("counter.increment") { ... }
    Remo.register("counter.decrement") { ... }
}

// Always expands to:
{
    #if DEBUG
    Remo.register("counter.increment") { ... }
    Remo.register("counter.decrement") { ... }
    #endif
}()
```

## Supported Parameter Types

The macro generates `as? T` casts for JSON-compatible types from `[String: Any]`:

| Type | Cast | Example |
|------|------|---------|
| `Int` | `as? Int` | `(count: Int = 0)` |
| `Double` | `as? Double` | `(ratio: Double = 1.0)` |
| `Bool` | `as? Bool` | `(force: Bool = false)` |
| `String` | `as? String` | `(name: String = "")` |
| `[String]` | `as? [String]` | `(tags: [String] = [])` |
| `[Int]` | `as? [Int]` | `(ids: [Int] = [])` |
| `[String: Any]` | `as? [String: Any]` | `(meta: [String: Any] = [:])` |

Parameters with defaults use `?? defaultValue`. Parameters without defaults are required — the macro generates an error return if missing:

```swift
// Source:
#remo("user.set") { (name: String) in ...  }

// Expands to:
Remo.register("user.set") { (__params: [String: Any]) -> [String: Any] in
    guard let name = __params["name"] as? String else {
        return ["error": "missing required parameter: name"]
    }
    ...
}
```

## Lifecycle Management

Capabilities are scoped to view visibility — only the top-visible screen's capabilities are registered. All supporting types are `#if DEBUG` only — nothing leaks into release builds.

**Design principle:** Like `#Preview`, every Remo artifact vanishes completely in release. No protocols, no view modifier extensions, no structs — the macro wraps everything in `#if DEBUG` at the expansion site.

### SwiftUI — macro-powered modifier

The `#remo` macro expands to a `ViewModifier` in debug and `EmptyModifier()` in release:

```swift
struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack { ... }
            .modifier(#remo("counter.increment") { (amount: Int = 1) in
                store.counter += amount
                return ["status": "ok"]
            })
            .modifier(#remo("counter.reset") {
                store.counter = 0
                return ["status": "ok"]
            })
    }
}
```

**Macro expansion:**

```swift
// Source:
.modifier(#remo("counter.increment") { (amount: Int = 1) in
    store.counter += amount
    return ["status": "ok"]
})

// Expands to (all builds):
.modifier({
    #if DEBUG
    _RemoModifier(name: "counter.increment") { (__params: [String: Any]) -> [String: Any] in
        let amount = __params["amount"] as? Int ?? 1
        store.counter += amount
        return ["status": "ok"]
    }
    #else
    EmptyModifier()
    #endif
}())
```

`_RemoModifier` is a `#if DEBUG`-only `ViewModifier` that registers on appear and unregisters on disappear. `EmptyModifier` is SwiftUI's built-in no-op — zero cost, already exists.

**`_RemoModifier` (debug only, provided by RemoSwift):**

```swift
#if DEBUG
internal struct _RemoModifier: ViewModifier {
    let name: String
    let handler: ([String: Any]) -> [String: Any]

    func body(content: Content) -> some View {
        content
            .onAppear { Remo.register(name, handler: handler) }
            .onDisappear { Remo.unregister(name) }
    }
}
#endif
```

### UIKit — macro with `scopedTo:`

The `#remo` macro with a `scopedTo:` parameter auto-manages registration tied to VC visibility. No protocol conformance needed:

```swift
class DetailViewController: UIViewController {
    var item: String = ""

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        #remo("detail.getInfo", scopedTo: self) { [weak self] in
            return ["item": self?.item ?? ""]
        }
        #remo("detail.setTitle", scopedTo: self) { [weak self] (title: String) in
            self?.title = title
            return ["status": "ok"]
        }
    }
    // No viewDidDisappear override needed — auto-unregistration handled
}
// Push DetailVC → capabilities registered
// Push another VC on top → capabilities unregistered
// Pop back to DetailVC → capabilities re-registered
```

**Macro expansion:**

```swift
// Source:
#remo("detail.getInfo", scopedTo: self) { [weak self] in
    return ["item": self?.item ?? ""]
}

// Expands to (all builds):
{
    #if DEBUG
    _RemoLifecycle.registerScoped(owner: self, name: "detail.getInfo") {
        (__params: [String: Any]) -> [String: Any] in
        return ["item": self?.item ?? ""]
    }
    #endif
}()
```

**`_RemoLifecycle` (debug only, provided by RemoSwift):**

```swift
#if DEBUG
internal enum _RemoLifecycle {
    /// Register a capability scoped to a UIViewController's visibility.
    ///
    /// On first call, swizzles `viewDidDisappear(_:)` on UIViewController (once).
    /// Uses associated objects to track registered capability names per VC instance.
    /// When the VC disappears, all its scoped capabilities are unregistered.
    /// When it reappears and `viewDidAppear` calls `#remo` again, they re-register.
    static func registerScoped(
        owner: UIViewController,
        name: String,
        handler: @escaping ([String: Any]) -> [String: Any]
    ) {
        swizzleViewDidDisappearOnce()
        trackCapability(name, on: owner)
        Remo.register(name, handler: handler)
    }
}
#endif
```

### Global capabilities (no lifecycle)

For app-wide capabilities that should always be available, use the block form or direct `#remo` calls at setup time:

```swift
// In app startup
#remo {
    Remo.register("navigate") { ... }
    Remo.register("state.get") { ... }
}
```

## Package Structure

```
swift/RemoSwift/
├── Package.swift                          # Updated with macro targets
├── Sources/
│   ├── RemoSwift/
│   │   ├── Remo.swift                     # Existing (unchanged)
│   │   ├── _RemoModifier.swift            # #if DEBUG ViewModifier for SwiftUI
│   │   └── _RemoLifecycle.swift           # #if DEBUG VC swizzling for UIKit
│   ├── RemoMacros/                        # Public macro declarations
│   │   └── RemoMacros.swift               # @freestanding(expression) macro decl
│   └── RemoMacrosPlugin/                  # Compiler plugin (host-side)
│       └── RemoMacrosPlugin.swift         # SwiftSyntax expansion logic
└── Tests/
    └── RemoMacrosTests/
        └── RemoMacrosTests.swift          # assertMacroExpansion tests
```

### Package.swift changes

- Add `swift-syntax` dependency (version 600.0.0+ for Swift 6 toolchain)
- Add `RemoMacros` target (library) — declares the `#remo` macro
- Add `RemoMacrosPlugin` target (macro) — implements the expansion
- Add `RemoMacrosTests` target — tests macro expansion
- `RemoSwift` gains a dependency on `RemoMacros` and re-exports it
- Minimum swift-tools-version stays 5.9 (macros supported since 5.9)

### Re-export strategy

`RemoMacros/RemoMacros.swift` declares the public macro. `RemoSwift/Remo.swift` adds `@_exported import RemoMacros` so users get `#remo` via `import RemoSwift`.

## Platform Support

- **SwiftUI:** `.modifier(#remo(...))` for visibility-scoped capabilities, `#remo` block form for global setup
- **UIKit:** `#remo(..., scopedTo: self)` for visibility-scoped capabilities, `#remo` block form for global setup
- **Both:** `#remo` macro provides typed params, dead-code elimination, and zero release footprint in all contexts
- **Nothing leaks:** All internal types (`_RemoModifier`, `_RemoLifecycle`) are `#if DEBUG` only

## Constraints

- Requires Swift 5.9+ (macro support)
- SwiftSyntax adds ~30s to first clean build of the macro plugin
- The macro plugin runs on the host (macOS), not the target device
- `#remo` block form contents are opaque to the macro — no typed parameter extraction inside the block form; use inline form for that

## Testing Strategy

**Macro expansion tests** (using `assertMacroExpansion` from `SwiftSyntaxMacrosTestSupport`):
- Inline form: typed params with defaults, required params, multiple params, no params
- Block form: wraps arbitrary code in `#if DEBUG`
- Capability form: returns `RemoCapability` with param extraction
- Unsupported types produce compile-time diagnostics

**Integration tests:**
- Update example app to use `#remo` macro and `.modifier(#remo(...))` pattern
- Verify Debug build registers/unregisters capabilities correctly
- Verify Release build compiles with zero Remo footprint (no symbols from `_RemoModifier` or `_RemoLifecycle`)
- Verify SwiftUI view appear/disappear triggers register/unregister
- Verify UIKit VC push/pop triggers register/unregister via `scopedTo:` pattern
