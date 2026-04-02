# #remo Swift Macro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `#remo` Swift macro to `RemoSwift` that provides dead-code elimination in release builds, ergonomic `RemoParams` parameter access, and automatic lifecycle management for both SwiftUI and UIKit.

**Architecture:** A SwiftSyntax compiler plugin (`RemoMacrosPlugin`) expands `#remo` calls into `#if DEBUG`-wrapped IIFE blocks. Three macro forms: inline registration, UIKit-scoped registration (`scopedTo:`), and block wrapping. A `RemoParams` wrapper and `Remo.keepAlive()` async helper ship alongside. All support types are `#if DEBUG` only.

**Tech Stack:** Swift 5.9+, SwiftSyntax 600.0.0, SwiftCompilerPlugin, SwiftSyntaxMacros, SwiftSyntaxMacrosTestSupport, UIKit (swizzling for UIKit lifecycle)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `swift/RemoSwift/Package.swift` | Modify | Add swift-syntax dep, RemoMacros + RemoMacrosPlugin + RemoMacrosTests targets |
| `swift/RemoSwift/Sources/RemoSwift/Remo.swift` | Modify | Add `@_exported import RemoMacros`, add `keepAlive()` |
| `swift/RemoSwift/Sources/RemoSwift/RemoParams.swift` | Create | `#if DEBUG`-only typed dict wrapper |
| `swift/RemoSwift/Sources/RemoSwift/_RemoLifecycle.swift` | Create | `#if DEBUG`-only UIKit `viewDidDisappear` swizzling |
| `swift/RemoSwift/Sources/RemoMacros/RemoMacros.swift` | Create | Public `@freestanding(expression)` macro declarations |
| `swift/RemoSwift/Sources/RemoMacrosPlugin/RemoMacrosPlugin.swift` | Create | SwiftSyntax macro expansion implementations |
| `swift/RemoSwift/Tests/RemoMacrosTests/RemoMacrosTests.swift` | Create | `assertMacroExpansion` tests for all three macro forms |
| `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/ContentView.swift` | Modify | Update to use `#remo` and `Remo.keepAlive` |

---

## Task 1: Update Package.swift

**Files:**
- Modify: `swift/RemoSwift/Package.swift`

- [ ] **Step 1: Add swift-syntax dependency and macro targets**

Replace the entire file content:

```swift
// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "RemoSwift",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "RemoSwift", targets: ["RemoSwift"]),
        .library(name: "RemoObjC", targets: ["RemoObjC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "CRemo",
            path: "../RemoSDK.xcframework"
        ),
        .macro(
            name: "RemoMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "RemoMacros",
            dependencies: ["RemoMacrosPlugin"]
        ),
        .target(
            name: "RemoSwift",
            dependencies: ["CRemo", "RemoMacros"],
            path: "Sources/RemoSwift",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Security"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .target(
            name: "RemoObjC",
            dependencies: ["CRemo"],
            path: "Sources/RemoObjC",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Security"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .testTarget(
            name: "RemoMacrosTests",
            dependencies: [
                "RemoMacros",
                "RemoMacrosPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Create the directory structure**

```bash
mkdir -p swift/RemoSwift/Sources/RemoMacros
mkdir -p swift/RemoSwift/Sources/RemoMacrosPlugin
mkdir -p swift/RemoSwift/Tests/RemoMacrosTests
```

- [ ] **Step 3: Verify the package resolves**

```bash
cd swift/RemoSwift && swift package resolve 2>&1 | tail -5
```

Expected: no errors, swift-syntax fetched.

- [ ] **Step 4: Commit**

```bash
git add swift/RemoSwift/Package.swift
git commit -m "build: add swift-syntax dependency and macro targets"
```

---

## Task 2: Create RemoParams

**Files:**
- Create: `swift/RemoSwift/Sources/RemoSwift/RemoParams.swift`

- [ ] **Step 1: Write the file**

```swift
// swift/RemoSwift/Sources/RemoSwift/RemoParams.swift

#if DEBUG
/// Type-safe wrapper around a Remo capability's raw `[String: Any]` parameter dict.
///
/// Created automatically by the `#remo` macro — you never instantiate this directly.
///
/// Usage:
/// ```swift
/// #remo("counter.increment") { params in
///     let amount: Int = params["amount", default: 1]
///     let label: String? = params["label"]
/// }
/// ```
public struct RemoParams {
    private let dict: [String: Any]

    public init(_ dict: [String: Any]) {
        self.dict = dict
    }

    /// Returns the value for `key` cast to `T`, or `defaultValue` if missing or wrong type.
    public subscript<T>(_ key: String, default defaultValue: T) -> T {
        dict[key] as? T ?? defaultValue
    }

    /// Returns the value for `key` cast to `T`, or `nil` if missing or wrong type.
    public subscript<T>(_ key: String) -> T? {
        dict[key] as? T
    }
}
#endif
```

- [ ] **Step 2: Build to verify it compiles**

```bash
cd swift/RemoSwift && swift build 2>&1 | grep -E "error:|warning:|Build complete"
```

Expected: `Build complete!` (or only pre-existing warnings).

- [ ] **Step 3: Commit**

```bash
git add swift/RemoSwift/Sources/RemoSwift/RemoParams.swift
git commit -m "feat: add RemoParams typed parameter wrapper (debug only)"
```

---

## Task 3: Add `Remo.keepAlive()` and re-export

**Files:**
- Modify: `swift/RemoSwift/Sources/RemoSwift/Remo.swift`

- [ ] **Step 1: Add `keepAlive` to the DEBUG section**

In `Remo.swift`, inside the `#if DEBUG` section, add after `listCapabilities()`:

```swift
    /// Sleep until the current Swift Task is cancelled, then unregister named capabilities.
    ///
    /// Call at the end of a SwiftUI `.task {}` block after all `#remo` registrations:
    /// ```swift
    /// .task {
    ///     #remo("my.capability") { params in ... }
    ///     await Remo.keepAlive("my.capability")
    /// }
    /// ```
    /// When the view disappears, SwiftUI cancels the task, this function returns,
    /// and all named capabilities are unregistered.
    public static func keepAlive(_ names: String...) async {
        try? await Task.sleep(nanoseconds: .max)
        names.forEach { unregister($0) }
    }
```

- [ ] **Step 2: Add the no-op stub to the RELEASE section**

In the `#else` section (release stubs), add after the `listCapabilities` stub:

```swift
    @inlinable
    public static func keepAlive(_ names: String...) async {}
```

- [ ] **Step 3: Add `@_exported import RemoMacros` at the top of the DEBUG section**

At the very top of `Remo.swift`, before `#if DEBUG`:

```swift
@_exported import RemoMacros
```

Note: this goes at the top of the file, before the `#if DEBUG` block. It must be unconditional so the macro is available in all builds (the macro itself is safe in release — its expansions produce `#if DEBUG` blocks).

- [ ] **Step 4: Build to verify**

```bash
cd swift/RemoSwift && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: error about `RemoMacros` module not found — that's expected since we haven't created it yet. Proceed.

Actually — skip this build check until RemoMacros exists. Instead:

- [ ] **Step 4: Commit**

```bash
git add swift/RemoSwift/Sources/RemoSwift/Remo.swift
git commit -m "feat: add Remo.keepAlive() for SwiftUI task-based lifecycle"
```

---

## Task 4: Create `_RemoLifecycle` (UIKit, debug only)

**Files:**
- Create: `swift/RemoSwift/Sources/RemoSwift/_RemoLifecycle.swift`

- [ ] **Step 1: Write the file**

```swift
// swift/RemoSwift/Sources/RemoSwift/_RemoLifecycle.swift

#if DEBUG
import UIKit
import ObjectiveC

/// Internal UIKit lifecycle manager for `#remo("name", scopedTo: self)` expansions.
///
/// Swizzles `UIViewController.viewDidDisappear(_:)` once per process lifetime.
/// Uses associated objects to track registered capability names per VC instance.
/// When a VC disappears, all its tracked capabilities are unregistered.
internal enum _RemoLifecycle {
    private static var _swizzled = false
    private static let _lock = NSLock()

    // Key for objc associated object storing [String] of registered capability names.
    private static var _namesKey: UInt8 = 0

    /// Register a capability and associate it with `owner`'s disappear lifecycle.
    ///
    /// Called by the `#remo("name", scopedTo: self)` macro expansion.
    static func registerScoped(
        owner: UIViewController,
        name: String,
        handler: @escaping ([String: Any]) -> [String: Any]
    ) {
        _swizzleOnce()
        var names = objc_getAssociatedObject(owner, &_namesKey) as? [String] ?? []
        if !names.contains(name) {
            names.append(name)
        }
        objc_setAssociatedObject(owner, &_namesKey, names, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        Remo.register(name, handler: handler)
    }

    private static func _swizzleOnce() {
        _lock.lock()
        defer { _lock.unlock() }
        guard !_swizzled else { return }
        _swizzled = true

        let cls = UIViewController.self
        let original = #selector(UIViewController.viewDidDisappear(_:))
        let swizzled = #selector(UIViewController._remo_viewDidDisappear(_:))
        guard
            let originalMethod = class_getInstanceMethod(cls, original),
            let swizzledMethod = class_getInstanceMethod(cls, swizzled)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension UIViewController {
    @objc func _remo_viewDidDisappear(_ animated: Bool) {
        // After swizzling, this calls the original viewDidDisappear.
        _remo_viewDidDisappear(animated)
        guard let names = objc_getAssociatedObject(self, &_RemoLifecycle._namesKey) as? [String],
              !names.isEmpty else { return }
        names.forEach { Remo.unregister($0) }
        objc_setAssociatedObject(self, &_RemoLifecycle._namesKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
#endif
```

- [ ] **Step 2: Commit**

```bash
git add swift/RemoSwift/Sources/RemoSwift/_RemoLifecycle.swift
git commit -m "feat: add _RemoLifecycle for UIKit viewDidDisappear auto-unregister (debug only)"
```

---

## Task 5: Declare the `#remo` macros

**Files:**
- Create: `swift/RemoSwift/Sources/RemoMacros/RemoMacros.swift`

- [ ] **Step 1: Write the macro declarations**

```swift
// swift/RemoSwift/Sources/RemoMacros/RemoMacros.swift

/// Register a Remo capability (debug only). Expands to nothing in release builds.
///
/// The handler receives a `RemoParams` wrapper instead of raw `[String: Any]`:
/// ```swift
/// #remo("counter.increment") { params in
///     let amount: Int = params["amount", default: 1]
///     store.counter += amount
///     return ["status": "ok"]
/// }
/// ```
///
/// In SwiftUI, pair with `Remo.keepAlive` inside `.task {}` for lifecycle management:
/// ```swift
/// .task {
///     #remo("counter.increment") { params in ... }
///     await Remo.keepAlive("counter.increment")
/// }
/// ```
@freestanding(expression)
public macro remo(
    _ name: String,
    _ handler: @escaping (RemoParams) -> [String: Any]
) = #externalMacro(module: "RemoMacrosPlugin", type: "RemoInlineMacro")

/// Register a UIKit-scoped capability (debug only). Auto-unregisters on `viewDidDisappear`.
///
/// ```swift
/// override func viewDidAppear(_ animated: Bool) {
///     super.viewDidAppear(animated)
///     #remo("detail.getInfo", scopedTo: self) { [weak self] params in
///         return ["item": self?.item ?? ""]
///     }
/// }
/// ```
@freestanding(expression)
public macro remo(
    _ name: String,
    scopedTo owner: AnyObject,
    _ handler: @escaping (RemoParams) -> [String: Any]
) = #externalMacro(module: "RemoMacrosPlugin", type: "RemoScopedMacro")

/// Wrap a block of Remo registrations so they are stripped in release builds.
///
/// ```swift
/// #remo {
///     Remo.register("navigate") { ... }
///     Remo.register("state.get") { ... }
/// }
/// ```
@freestanding(expression)
public macro remo(
    _ body: () -> Void
) = #externalMacro(module: "RemoMacrosPlugin", type: "RemoBlockMacro")
```

- [ ] **Step 2: Commit**

```bash
git add swift/RemoSwift/Sources/RemoMacros/RemoMacros.swift
git commit -m "feat: declare #remo macro public API (inline, scoped, block forms)"
```

---

## Task 6: Implement RemoMacrosPlugin — inline and scoped forms

**Files:**
- Create: `swift/RemoSwift/Sources/RemoMacrosPlugin/RemoMacrosPlugin.swift`

- [ ] **Step 1: Write the plugin file**

```swift
// swift/RemoSwift/Sources/RemoMacrosPlugin/RemoMacrosPlugin.swift

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - Plugin Entry Point

@main
struct RemoMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        RemoInlineMacro.self,
        RemoScopedMacro.self,
        RemoBlockMacro.self,
    ]
}

// MARK: - Shared Helpers

enum RemoMacroError: Error, CustomStringConvertible {
    case missingNameArgument
    case missingHandler
    case missingBody

    var description: String {
        switch self {
        case .missingNameArgument: return "#remo requires a string literal as its first argument"
        case .missingHandler: return "#remo requires a trailing closure handler"
        case .missingBody: return "#remo { } requires a trailing closure body"
        }
    }
}

/// Extract the string value from the first argument (must be a string literal).
func extractName(from node: some FreestandingMacroExpansionSyntax) throws -> String {
    guard let firstArg = node.arguments.first,
          let literal = firstArg.expression.as(StringLiteralExprSyntax.self),
          let segment = literal.segments.first?.as(StringSegmentSyntax.self)
    else {
        throw RemoMacroError.missingNameArgument
    }
    return segment.content.text
}

/// Extract the trailing closure or the last argument's closure expression.
func extractHandler(from node: some FreestandingMacroExpansionSyntax) throws -> ClosureExprSyntax {
    if let trailing = node.trailingClosure {
        return trailing
    }
    if let last = node.arguments.last,
       let closure = last.expression.as(ClosureExprSyntax.self) {
        return closure
    }
    throw RemoMacroError.missingHandler
}

// MARK: - RemoInlineMacro

/// Expands `#remo("name") { params in ... }` to an IIFE with `#if DEBUG` wrapping.
///
/// DEBUG expansion:
/// ```swift
/// {
///     #if DEBUG
///     Remo.register("name") { (__rawParams: [String: Any]) -> [String: Any] in
///         let <paramName> = RemoParams(__rawParams)
///         <user body>
///     }
///     #endif
/// }()
/// ```
///
/// RELEASE expansion: the `#if DEBUG` block is stripped by the compiler.
public struct RemoInlineMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let name = try extractName(from: node)
        let handler = try extractHandler(from: node)

        // Determine the param name the user chose (e.g. "params") or use "_" if none.
        let paramName: String
        if let params = handler.signature?.parameterClause?.as(ClosureParameterClauseSyntax.self),
           let first = params.parameters.first {
            paramName = first.firstName.text
        } else if let shorthand = handler.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
                  let first = shorthand.first {
            paramName = first.name.text
        } else {
            paramName = "_"
        }

        let body = handler.statements

        return """
        {
            #if DEBUG
            RemoSwift.Remo.register(\(literal: name)) { (__rawParams: [String: Any]) -> [String: Any] in
                let \(raw: paramName) = RemoSwift.RemoParams(__rawParams)
                \(body)
            }
            #endif
        }()
        """
    }
}

// MARK: - RemoScopedMacro

/// Expands `#remo("name", scopedTo: self) { params in ... }` for UIKit lifecycle.
///
/// DEBUG expansion:
/// ```swift
/// {
///     #if DEBUG
///     _RemoLifecycle.registerScoped(owner: self, name: "name") {
///         (__rawParams: [String: Any]) -> [String: Any] in
///         let <paramName> = RemoParams(__rawParams)
///         <user body>
///     }
///     #endif
/// }()
/// ```
public struct RemoScopedMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let name = try extractName(from: node)
        let handler = try extractHandler(from: node)

        // The second argument is `scopedTo: owner` — extract the owner expression.
        guard let ownerArg = node.arguments.first(where: { $0.label?.text == "scopedTo" }) else {
            throw RemoMacroError.missingNameArgument
        }
        let ownerExpr = ownerArg.expression

        let paramName: String
        if let params = handler.signature?.parameterClause?.as(ClosureParameterClauseSyntax.self),
           let first = params.parameters.first {
            paramName = first.firstName.text
        } else if let shorthand = handler.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
                  let first = shorthand.first {
            paramName = first.name.text
        } else {
            paramName = "_"
        }

        let body = handler.statements

        return """
        {
            #if DEBUG
            RemoSwift._RemoLifecycle.registerScoped(owner: \(ownerExpr), name: \(literal: name)) { (__rawParams: [String: Any]) -> [String: Any] in
                let \(raw: paramName) = RemoSwift.RemoParams(__rawParams)
                \(body)
            }
            #endif
        }()
        """
    }
}

// MARK: - RemoBlockMacro

/// Expands `#remo { ... }` to an IIFE with `#if DEBUG` wrapping.
///
/// DEBUG expansion:
/// ```swift
/// {
///     #if DEBUG
///     <user body>
///     #endif
/// }()
/// ```
public struct RemoBlockMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let body = node.trailingClosure?.statements else {
            throw RemoMacroError.missingBody
        }

        return """
        {
            #if DEBUG
            \(body)
            #endif
        }()
        """
    }
}
```

- [ ] **Step 2: Build to verify the plugin and RemoSwift compile**

```bash
cd swift/RemoSwift && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

If you see errors about `RemoParams` not found inside the macro expansion string, that is expected at compile time for the plugin itself — the plugin generates source strings, not real Swift code. The plugin compiles separately from RemoSwift.

- [ ] **Step 3: Commit**

```bash
git add swift/RemoSwift/Sources/RemoMacrosPlugin/RemoMacrosPlugin.swift
git commit -m "feat: implement RemoMacrosPlugin (inline, scoped, block forms)"
```

---

## Task 7: Write macro expansion tests

**Files:**
- Create: `swift/RemoSwift/Tests/RemoMacrosTests/RemoMacrosTests.swift`

- [ ] **Step 1: Write the test file**

```swift
// swift/RemoSwift/Tests/RemoMacrosTests/RemoMacrosTests.swift

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import RemoMacrosPlugin

let testMacros: [String: Macro.Type] = [
    "remo": RemoInlineMacro.self,
]

let testMacrosScoped: [String: Macro.Type] = [
    "remo": RemoScopedMacro.self,
]

let testMacrosBlock: [String: Macro.Type] = [
    "remo": RemoBlockMacro.self,
]

final class RemoMacrosTests: XCTestCase {

    // MARK: - Inline form

    func testInlineFormWithParams() {
        assertMacroExpansion(
            """
            #remo("counter.increment") { params in
                let amount: Int = params["amount", default: 1]
                return ["status": "ok"]
            }
            """,
            expandedSource: """
            {
                #if DEBUG
                RemoSwift.Remo.register("counter.increment") { (__rawParams: [String: Any]) -> [String: Any] in
                    let params = RemoSwift.RemoParams(__rawParams)
                    let amount: Int = params["amount", default: 1]
                    return ["status": "ok"]
                }
                #endif
            }()
            """,
            macros: testMacros
        )
    }

    func testInlineFormNoParams() {
        assertMacroExpansion(
            """
            #remo("items.clear") { _ in
                return ["status": "ok"]
            }
            """,
            expandedSource: """
            {
                #if DEBUG
                RemoSwift.Remo.register("items.clear") { (__rawParams: [String: Any]) -> [String: Any] in
                    let _ = RemoSwift.RemoParams(__rawParams)
                    return ["status": "ok"]
                }
                #endif
            }()
            """,
            macros: testMacros
        )
    }

    func testInlineFormMultipleParams() {
        assertMacroExpansion(
            """
            #remo("state.set") { params in
                let key: String = params["key", default: ""]
                let value: String = params["value", default: ""]
                return ["status": "ok"]
            }
            """,
            expandedSource: """
            {
                #if DEBUG
                RemoSwift.Remo.register("state.set") { (__rawParams: [String: Any]) -> [String: Any] in
                    let params = RemoSwift.RemoParams(__rawParams)
                    let key: String = params["key", default: ""]
                    let value: String = params["value", default: ""]
                    return ["status": "ok"]
                }
                #endif
            }()
            """,
            macros: testMacros
        )
    }

    // MARK: - Scoped form

    func testScopedForm() {
        assertMacroExpansion(
            """
            #remo("detail.getInfo", scopedTo: self) { params in
                return ["item": "test"]
            }
            """,
            expandedSource: """
            {
                #if DEBUG
                RemoSwift._RemoLifecycle.registerScoped(owner: self, name: "detail.getInfo") { (__rawParams: [String: Any]) -> [String: Any] in
                    let params = RemoSwift.RemoParams(__rawParams)
                    return ["item": "test"]
                }
                #endif
            }()
            """,
            macros: testMacrosScoped
        )
    }

    // MARK: - Block form

    func testBlockForm() {
        assertMacroExpansion(
            """
            #remo {
                Remo.register("navigate") { _ in [:] }
                Remo.register("state.get") { _ in [:] }
            }
            """,
            expandedSource: """
            {
                #if DEBUG
                Remo.register("navigate") { _ in [:] }
                Remo.register("state.get") { _ in [:] }
                #endif
            }()
            """,
            macros: testMacrosBlock
        )
    }
}
```

- [ ] **Step 2: Run the tests**

```bash
cd swift/RemoSwift && swift test --filter RemoMacrosTests 2>&1 | tail -20
```

Expected: All tests pass. If expansion strings don't match exactly, adjust whitespace/formatting in the plugin to match SwiftSyntax's output — `assertMacroExpansion` is whitespace-sensitive.

- [ ] **Step 3: Fix any expansion mismatches**

If tests fail due to whitespace differences, run with verbose output to see the actual expansion:

```bash
cd swift/RemoSwift && swift test --filter RemoMacrosTests -v 2>&1 | grep -A 30 "XCTAssertEqual"
```

Adjust the `expandedSource` strings in the test to match the actual output from the plugin.

- [ ] **Step 4: Commit**

```bash
git add swift/RemoSwift/Tests/RemoMacrosTests/RemoMacrosTests.swift
git commit -m "test: add assertMacroExpansion tests for all three #remo forms"
```

---

## Task 8: Full build verification

**Files:** None new — verify everything compiles together.

- [ ] **Step 1: Full build**

```bash
cd swift/RemoSwift && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 2: Run all tests**

```bash
cd swift/RemoSwift && swift test 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 3: Verify `@_exported import RemoMacros` works**

Create a temporary scratch file to verify `#remo` is accessible via `import RemoSwift`:

```bash
cat > /tmp/verify_remo.swift << 'EOF'
import RemoSwift

func verify() {
    #remo("test.capability") { params in
        let value: Int = params["value", default: 0]
        return ["value": value]
    }
    #remo {
        Remo.register("test.global") { _ in [:] }
    }
}
EOF
echo "Scratch file written — macro is accessible if swift build above succeeded"
```

- [ ] **Step 4: Commit**

```bash
git commit --allow-empty -m "build: verify full build and test suite passes"
```

---

## Task 9: Update example app

**Files:**
- Modify: `examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/ContentView.swift`

The goal is to replace the existing `registerHomeCapabilities`, `registerItemsCapabilities`, and `registerDetailCapabilities` free functions, plus the manual `.onAppear`/`.onDisappear` pairs, with `#remo` + `Remo.keepAlive`.

- [ ] **Step 1: Replace `registerHomeCapabilities`**

Remove the free function:
```swift
// DELETE this entire function:
func registerHomeCapabilities(store: AppStore) {
    Remo.register("counter.increment") { params in
        let amount = params["amount"] as? Int ?? 1
        DispatchQueue.main.async { store.counter += amount }
        return ["status": "ok", "amount": amount]
    }
}
```

In `HomeView.body`, replace the `.task { registerHomeCapabilities(store: store) }` + `.onDisappear { Remo.unregister(...) }` pair with:

```swift
.task {
    #remo("counter.increment") { params in
        let amount: Int = params["amount", default: 1]
        DispatchQueue.main.async { store.counter += amount }
        return ["status": "ok", "amount": amount]
    }
    await Remo.keepAlive("counter.increment")
}
```

Also remove the duplicate `.onAppear` + `.onDisappear` block at the end of `HomeView.body`.

- [ ] **Step 2: Replace `registerItemsCapabilities`**

Remove the free function `registerItemsCapabilities(store:)`.

In `ListPage.body`, replace the `.task { registerItemsCapabilities(store: store) }` + `.onDisappear` pair with:

```swift
.task {
    #remo("items.add") { params in
        let name: String = params["name", default: "New Item"]
        DispatchQueue.main.async {
            withAnimation { store.items.append(name) }
        }
        return ["status": "ok", "name": name]
    }
    #remo("items.remove") { params in
        let name: String = params["name", default: ""]
        DispatchQueue.main.async {
            withAnimation {
                if let idx = store.items.firstIndex(of: name) {
                    store.items.remove(at: idx)
                }
            }
        }
        return ["status": "ok", "name": name]
    }
    #remo("items.clear") { _ in
        DispatchQueue.main.async {
            withAnimation { store.items.removeAll() }
        }
        return ["status": "ok"]
    }
    await Remo.keepAlive("items.add", "items.remove", "items.clear")
}
```

Remove the duplicate `.onAppear` + `.onDisappear` block at the end of `ListPage.body`.

- [ ] **Step 3: Replace `registerDetailCapabilities`**

Remove the free function `registerDetailCapabilities(item:)`.

In `DetailPage.body`, replace the `.task { registerDetailCapabilities(item: item) }` + `.onDisappear` pair with:

```swift
.task {
    #remo("detail.getInfo") { [item] _ in
        return ["item": item]
    }
    await Remo.keepAlive("detail.getInfo")
}
```

- [ ] **Step 4: Build the example package to verify**

```bash
cd examples/ios/RemoExamplePackage && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add examples/ios/RemoExamplePackage/Sources/RemoExampleFeature/ContentView.swift
git commit -m "refactor: migrate example app to use #remo macro"
```

---

## Task 10: Final verification

- [ ] **Step 1: Run all tests**

```bash
cd swift/RemoSwift && swift test 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 2: Verify example package builds clean**

```bash
cd examples/ios/RemoExamplePackage && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit final state**

```bash
git add -A
git status  # verify only expected files
git commit -m "feat: complete #remo Swift macro implementation"
```
