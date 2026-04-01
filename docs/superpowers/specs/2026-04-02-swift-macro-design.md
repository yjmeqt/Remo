# Swift Macro for Remo Capability Registration

**Date:** 2026-04-02
**Status:** Approved

## Problem

Remo capability registration code has two pain points:

1. **No dead-code elimination.** `Remo.register(...)` compiles in release builds as a no-op stub, but the closure body and surrounding code still ship in the binary. Developers expect debug tooling to vanish completely, like `#Preview`.

2. **Tedious parameter parsing.** Handlers receive `[String: Any]` and must manually cast each parameter:
   ```swift
   Remo.register("counter.increment") { params in
       let amount = params["amount"] as? Int ?? 1  // verbose, error-prone
       ...
   }
   ```

## Solution

A `#remo` Swift macro (freestanding expression) that:
- Strips all enclosed code from release builds (true dead-code elimination)
- Generates type-safe parameter extraction from typed closure parameters
- Ships inside the existing `RemoSwift` package — `import RemoSwift` gives you `#remo`

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

## Package Structure

```
swift/RemoSwift/
├── Package.swift                          # Updated with macro targets
├── Sources/
│   ├── RemoSwift/
│   │   └── Remo.swift                     # Existing (unchanged)
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

- **SwiftUI:** `#remo` inside `.task {}`, `.onAppear {}`, view `init`, or anywhere expressions are valid
- **UIKit:** `#remo` inside `viewDidLoad()`, lifecycle methods, or any method body
- Both work identically — the macro is framework-agnostic

## Constraints

- Requires Swift 5.9+ (macro support)
- SwiftSyntax adds ~30s to first clean build of the macro plugin
- The macro plugin runs on the host (macOS), not the target device
- `#remo` block form contents are opaque to the macro — no typed parameter extraction inside the block form; use inline form for that

## Testing Strategy

- Unit tests using `assertMacroExpansion` from `SwiftSyntaxMacrosTestSupport`
- Test DEBUG expansion with typed params (defaults, required, multiple)
- Test RELEASE expansion (empty)
- Test block form expansion
- Test unsupported types produce compile-time diagnostics
- Integration: update the example app to use `#remo` and verify it builds for both Debug and Release
