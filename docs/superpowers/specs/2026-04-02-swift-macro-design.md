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
- Provides ergonomic typed parameter access via a `RemoParams` wrapper (replaces manual `as? T ?? default` casts)
- Provides automatic visibility-scoped lifecycle management for UIKit via `scopedTo:`
- Provides a `Remo.keepAlive(_ names:)` async helper for SwiftUI task-based lifecycle
- Ships inside the existing `RemoSwift` package — `import RemoSwift` gives you `#remo`

**Scoping rule:** Only the top-visible view/VC's capabilities are registered. Pushing a new screen unregisters the previous screen's capabilities. Popping re-registers them.

**Note on typed closure parameters:** Swift does not allow default values in closure parameters (`{ (amount: Int = 1) in }` is a parse error). Instead, `RemoParams` provides subscript-based access with defaults: `params["amount", default: 1]`.

## Syntax

### Inline form — single capability with `RemoParams`

```swift
// RemoParams subscript provides typed access with defaults
#remo("counter.increment") { params in
    let amount: Int = params["amount", default: 1]
    store.counter += amount
    return ["status": "ok"]
}

// Multiple params
#remo("state.set") { params in
    let key: String = params["key", default: ""]
    let value: String = params["value", default: ""]
    store.setValue(value, forKey: key)
    return ["status": "ok"]
}

// Optional param (nil if missing, user handles default inline)
#remo("user.rename") { params in
    guard let name: String = params["name"] else {
        return ["error": "missing required parameter: name"]
    }
    store.username = name
    return ["status": "ok"]
}
```

### UIKit scoped form — auto-unregisters on `viewDidDisappear`

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    #remo("detail.getInfo", scopedTo: self) { [weak self] params in
        return ["item": self?.item ?? ""]
    }
    // No viewDidDisappear override needed
}
```

### SwiftUI lifecycle — `.task` + `Remo.keepAlive`

```swift
.task {
    #remo("counter.increment") { params in
        let amount: Int = params["amount", default: 1]
        store.counter += amount
        return ["status": "ok"]
    }
    await Remo.keepAlive("counter.increment")
    // When view disappears, SwiftUI cancels the task.
    // keepAlive sleeps until cancellation, then unregisters all named capabilities.
}
```

For multiple capabilities:
```swift
.task {
    #remo("counter.increment") { params in ... }
    #remo("counter.reset") { params in ... }
    await Remo.keepAlive("counter.increment", "counter.reset")
}
```

### Block form — group multiple registrations (global setup)

```swift
#remo {
    Remo.register("navigate") { ... }
    Remo.register("state.get") { ... }
}
```

## Macro Expansion

Swift macros expand identically regardless of build configuration — a macro cannot check `#if DEBUG` at expansion time. Instead, the macro wraps its expansion in an immediately-invoked closure containing `#if DEBUG`, which the compiler evaluates at build time.

### Inline form expansion

```swift
// Source:
#remo("counter.increment") { params in
    let amount: Int = params["amount", default: 1]
    store.counter += amount
    return ["status": "ok"]
}

// Always expands to (same in all builds):
{
    #if DEBUG
    Remo.register("counter.increment") { (__rawParams: [String: Any]) -> [String: Any] in
        let params = RemoParams(__rawParams)
        let amount: Int = params["amount", default: 1]
        store.counter += amount
        return ["status": "ok"]
    }
    #endif
}()
```

In DEBUG builds, `RemoParams` wraps the raw dictionary and the handler is registered. In RELEASE builds, the compiler strips the entire block — the closure body becomes empty, achieving true dead-code elimination at the source level (not optimizer-dependent). `RemoParams` itself is also `#if DEBUG` only so it has zero release footprint.

### UIKit scoped form expansion

```swift
// Source:
#remo("detail.getInfo", scopedTo: self) { [weak self] params in
    return ["item": self?.item ?? ""]
}

// Always expands to:
{
    #if DEBUG
    _RemoLifecycle.registerScoped(owner: self, name: "detail.getInfo") {
        (__rawParams: [String: Any]) -> [String: Any] in
        let params = RemoParams(__rawParams)
        return ["item": self?.item ?? ""]
    }
    #endif
}()
```

### Block form expansion

```swift
// Source:
#remo {
    Remo.register("navigate") { ... }
    Remo.register("state.get") { ... }
}

// Always expands to:
{
    #if DEBUG
    Remo.register("navigate") { ... }
    Remo.register("state.get") { ... }
    #endif
}()
```

## RemoParams

`RemoParams` is a `#if DEBUG`-only wrapper around `[String: Any]` that provides typed subscript access:

```swift
#if DEBUG
public struct RemoParams {
    private let dict: [String: Any]
    public init(_ dict: [String: Any]) { self.dict = dict }

    /// Optional access — returns nil if key missing or type mismatch
    public subscript<T>(_ key: String) -> T? { dict[key] as? T }

    /// Access with default — returns defaultValue if key missing or type mismatch
    public subscript<T>(_ key: String, default value: T) -> T { dict[key] as? T ?? value }
}
#endif
```

Supports any JSON-compatible type via `as? T`: `Int`, `Double`, `Bool`, `String`, `[String]`, `[Int]`, `[String: Any]`, etc.

**Before (current):**
```swift
let amount = params["amount"] as? Int ?? 1
let name = params["name"] as? String ?? ""
```

**After (with RemoParams):**
```swift
let amount: Int = params["amount", default: 1]
let name: String = params["name", default: ""]
```

## Lifecycle Management

Capabilities are scoped to view visibility — only the top-visible screen's capabilities are registered. All supporting types are `#if DEBUG` only — nothing leaks into release builds.

**Design principle:** Like `#Preview`, every Remo artifact vanishes completely in release. No protocols, no view modifier extensions — the macro wraps everything in `#if DEBUG` at the expansion site.

### SwiftUI — `.task {}` + `Remo.keepAlive`

SwiftUI's `.task {}` modifier automatically cancels the task when the view disappears. `Remo.keepAlive` uses this cancellation to auto-unregister capabilities:

```swift
struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack { ... }
            .task {
                #remo("counter.increment") { params in
                    let amount: Int = params["amount", default: 1]
                    store.counter += amount
                    return ["status": "ok"]
                }
                #remo("counter.reset") { _ in
                    store.counter = 0
                    return ["status": "ok"]
                }
                await Remo.keepAlive("counter.increment", "counter.reset")
                // keepAlive sleeps until task is cancelled (view disappears),
                // then unregisters all named capabilities.
            }
    }
}
```

**`Remo.keepAlive` (added to Remo.swift):**

```swift
#if DEBUG
/// Sleep indefinitely, then unregister capabilities when the task is cancelled.
/// Call at the end of a .task {} block after all #remo registrations.
public static func keepAlive(_ names: String...) async {
    try? await Task.sleep(nanoseconds: .max)
    names.forEach { unregister($0) }
}
#else
@inlinable
public static func keepAlive(_ names: String...) async {}
#endif
```

In release builds, `keepAlive` is an inlinable no-op — the compiler eliminates it entirely.

### UIKit — `scopedTo:` form

The `#remo("name", scopedTo: self)` form auto-manages registration tied to `viewDidAppear`/`viewDidDisappear` via one-time method swizzling (debug only):

```swift
class DetailViewController: UIViewController {
    var item: String = ""

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #remo("detail.getInfo", scopedTo: self) { [weak self] params in
            return ["item": self?.item ?? ""]
        }
        #remo("detail.setTitle", scopedTo: self) { [weak self] params in
            let title: String = params["title", default: ""]
            self?.navigationItem.title = title
            return ["status": "ok"]
        }
        // No viewDidDisappear override needed
    }
}
// Push DetailVC → capabilities registered
// Push another VC on top → capabilities unregistered
// Pop back to DetailVC → capabilities re-registered
```

**`_RemoLifecycle` (debug only, `Sources/RemoSwift/_RemoLifecycle.swift`):**

```swift
#if DEBUG
import UIKit

internal enum _RemoLifecycle {
    private static var swizzled = false
    private static let swizzleLock = NSLock()

    /// Keys an associated-object array of registered names on each VC instance.
    private static let capabilityNamesKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    static func registerScoped(
        owner: UIViewController,
        name: String,
        handler: @escaping ([String: Any]) -> [String: Any]
    ) {
        swizzleOnce()
        var names = objc_getAssociatedObject(owner, capabilityNamesKey) as? [String] ?? []
        names.append(name)
        objc_setAssociatedObject(owner, capabilityNamesKey, names, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        Remo.register(name, handler: handler)
    }

    private static func swizzleOnce() {
        swizzleLock.lock()
        defer { swizzleLock.unlock() }
        guard !swizzled else { return }
        swizzled = true

        let cls = UIViewController.self
        let originalSel = #selector(UIViewController.viewDidDisappear(_:))
        let swizzledSel = #selector(UIViewController._remo_viewDidDisappear(_:))
        guard
            let original = class_getInstanceMethod(cls, originalSel),
            let swizzled = class_getInstanceMethod(cls, swizzledSel)
        else { return }
        method_exchangeImplementations(original, swizzled)
    }
}

extension UIViewController {
    @objc func _remo_viewDidDisappear(_ animated: Bool) {
        _remo_viewDidDisappear(animated)  // calls original (names are swapped)
        if let names = objc_getAssociatedObject(self, _RemoLifecycle.capabilityNamesKey) as? [String] {
            names.forEach { Remo.unregister($0) }
            objc_setAssociatedObject(self, _RemoLifecycle.capabilityNamesKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
#endif
```

### Global capabilities (no lifecycle)

For app-wide capabilities that should always be available, use the block form at app startup:

```swift
#remo {
    Remo.register("navigate") { ... }
    Remo.register("state.get") { ... }
}
```

## Package Structure

```
swift/RemoSwift/
├── Package.swift                          # Updated: swift-syntax dep + macro targets
├── Sources/
│   ├── RemoSwift/
│   │   ├── Remo.swift                     # +keepAlive(), +@_exported import RemoMacros
│   │   ├── RemoParams.swift               # #if DEBUG only, typed dict wrapper
│   │   └── _RemoLifecycle.swift           # #if DEBUG only, UIKit swizzling
│   ├── RemoMacros/                        # Public macro declarations (library target)
│   │   └── RemoMacros.swift               # @freestanding(expression) macro decls
│   └── RemoMacrosPlugin/                  # Compiler plugin (.macro target)
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

- **SwiftUI:** `.task { #remo(...); await Remo.keepAlive(...) }` for visibility-scoped capabilities, `#remo { }` for global setup
- **UIKit:** `#remo(..., scopedTo: self)` in `viewDidAppear` for visibility-scoped capabilities, `#remo { }` for global setup
- **Both:** `#remo` macro provides `RemoParams` ergonomics, dead-code elimination, and zero release footprint
- **Nothing leaks:** `RemoParams` and `_RemoLifecycle` are `#if DEBUG` only; `Remo.keepAlive` is an inlinable no-op in release

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
