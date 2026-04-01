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

Capabilities are scoped to view visibility — only the top-visible screen's capabilities are registered.

### SwiftUI — `.remo()` view modifier

A macro-powered view modifier that auto-registers on appear and auto-unregisters on disappear:

```swift
struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack { ... }
            .remo(#remo("counter.increment") { (amount: Int = 1) in
                store.counter += amount
                return ["status": "ok"]
            })
            .remo(#remo("counter.reset") {
                store.counter = 0
                return ["status": "ok"]
            })
    }
}
```

The `#remo(...)` macro returns a `RemoCapability` value (name + handler with typed param extraction). The `.remo()` view modifier manages the lifecycle.

**Macro expansion:**

```swift
// #remo("counter.increment") { (amount: Int = 1) in ... }
// expands to:
{
    #if DEBUG
    RemoCapability(name: "counter.increment") { (__params: [String: Any]) -> [String: Any] in
        let amount = __params["amount"] as? Int ?? 1
        store.counter += amount
        return ["status": "ok"]
    }
    #else
    RemoCapability.noop
    #endif
}()
```

**View modifier (provided by RemoSwift, not macro-generated):**

```swift
#if DEBUG
extension View {
    public func remo(_ capability: RemoCapability) -> some View {
        self
            .onAppear { Remo.register(capability.name, handler: capability.handler) }
            .onDisappear { Remo.unregister(capability.name) }
    }
}
#else
extension View {
    @inlinable
    public func remo(_ capability: RemoCapability) -> some View { self }
}
#endif
```

### UIKit — `RemoCapable` protocol

A protocol that declaratively defines a VC's capabilities. Registration/unregistration is tied to `viewDidAppear`/`viewDidDisappear` automatically via one-time method swizzling (debug builds only).

```swift
class DetailViewController: UIViewController, RemoCapable {
    var item: String = ""

    var remoCapabilities: [RemoCapability] {
        [
            #remo("detail.getInfo") { [weak self] in
                return ["item": self?.item ?? ""]
            },
            #remo("detail.setTitle") { [weak self] (title: String) in
                self?.title = title
                return ["status": "ok"]
            }
        ]
    }
}
// Push DetailVC → capabilities registered
// Push another VC on top → capabilities unregistered
// Pop back to DetailVC → capabilities re-registered
```

**How `RemoCapable` works:**

1. Protocol declares `var remoCapabilities: [RemoCapability]`
2. On first conformance (via `+load` or `initialize`), swizzles `viewDidAppear(_:)` and `viewDidDisappear(_:)` on `UIViewController`
3. Swizzled `viewDidAppear`: if `self` conforms to `RemoCapable`, register all capabilities
4. Swizzled `viewDidDisappear`: if `self` conforms to `RemoCapable`, unregister all capabilities
5. All swizzling and registration is gated behind `#if DEBUG` — zero footprint in release

```swift
#if DEBUG
public protocol RemoCapable: UIViewController {
    var remoCapabilities: [RemoCapability] { get }
}
#else
public protocol RemoCapable: UIViewController {
    // Empty in release — no swizzling, no registration
}
#endif
```

### Global capabilities (no lifecycle)

For app-wide capabilities that should always be available, use the block form or direct `#remo` calls at setup time — no view modifier or protocol needed:

```swift
// In app startup
#remo {
    Remo.register("navigate") { ... }
    Remo.register("state.get") { ... }
}
```

### `RemoCapability` struct

Shared value type used by both SwiftUI and UIKit:

```swift
public struct RemoCapability {
    public let name: String
    public let handler: ([String: Any]) -> [String: Any]

    #if !DEBUG
    /// No-op capability for release builds (macro expands to this)
    public static let noop = RemoCapability(name: "", handler: { _ in [:] })
    #endif
}
```

## Package Structure

```
swift/RemoSwift/
├── Package.swift                          # Updated with macro targets
├── Sources/
│   ├── RemoSwift/
│   │   ├── Remo.swift                     # Existing (unchanged)
│   │   ├── RemoCapability.swift           # RemoCapability struct
│   │   ├── RemoViewModifier.swift         # SwiftUI .remo() view modifier
│   │   └── RemoCapable.swift              # UIKit RemoCapable protocol + swizzling
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

- **SwiftUI:** `.remo()` view modifier for visibility-scoped capabilities, `#remo` block form for global setup
- **UIKit:** `RemoCapable` protocol for visibility-scoped capabilities, `#remo` block form for global setup
- **Both:** `#remo` macro provides typed params and dead-code elimination in all contexts

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
- Update example app to use `#remo` macro, `.remo()` modifier, and `RemoCapable` protocol
- Verify Debug build registers/unregisters capabilities correctly
- Verify Release build compiles with zero Remo footprint
- Verify SwiftUI view appear/disappear triggers register/unregister
- Verify UIKit VC push/pop triggers register/unregister via `RemoCapable`
