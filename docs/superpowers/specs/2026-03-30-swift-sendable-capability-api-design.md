# Swift Sendable Capability API Design

## Summary

Remo's current Swift capability API accepts an unconstrained closure:

```swift
Remo.register("name") { params in
    ...
}
```

That API shape is unsound in Swift 6 strict concurrency projects because the handler is invoked from a Rust background worker thread, but the type system does not express that fact. A user can therefore register a `@MainActor`-isolated or otherwise non-`Sendable` closure that compiles, then crashes at runtime when the callback executes on a non-main executor.

This design makes the execution model explicit in the type system. `Remo.register` remains the public entry point, but its handler must be `@Sendable`. The old unconstrained overload is removed completely. This is an intentional breaking change.

## Goals

- Make background-executed capability handlers explicit in the Swift API
- Cause `@MainActor` or otherwise non-`Sendable` handler captures to fail at compile time in Swift 6 strict concurrency projects
- Remove the unsound callback shape instead of preserving a compatibility layer
- Update all first-party examples and docs to match the new contract
- Add regression coverage so CI catches future attempts to weaken the API contract

## Non-Goals

- Supporting `@MainActor` capability handlers
- Providing a compatibility overload, deprecation path, or runtime warning for the old API
- Redesigning the JSON payload model in this change
- Changing the Rust callback threading model in this change

## Problem Statement

The Swift wrapper stores the user handler and invokes it synchronously from the C trampoline used by the Rust SDK bridge. That trampoline is entered from a tokio worker thread. The current API does not encode this background execution contract:

- the closure parameter is not `@Sendable`
- the API name does not describe any executor guarantee
- the docs show examples that look like ordinary app callbacks

In Swift 6 strict concurrency mode, this creates a sharp edge:

1. a user registers a handler from a `@MainActor`-isolated context
2. the closure inherits actor isolation by capturing `self` or actor-isolated state
3. Remo invokes the closure on a background worker thread
4. Swift concurrency runtime checks detect the isolation violation
5. the app traps at runtime instead of failing at compile time

The API is therefore wrong by construction. The fix is to make the closure's concurrency contract part of its type.

## Product Decision

`Remo.register` remains the only registration API, but its signature changes to:

```swift
public static func register(
    _ name: String,
    handler: @Sendable @escaping ([String: Any]) -> [String: Any]
)
```

The previous unconstrained signature is deleted. There is no deprecated overload and no `@MainActor` variant.

## Why `@Sendable` Is the Right Constraint

`@Sendable` is the type-system tool Swift uses to express "this closure may execute concurrently or on a different executor from where it was formed." That matches Remo's real behavior.

Adding `@Sendable` gives the compiler leverage to reject unsafe captures, including:

- `@MainActor`-isolated `self`
- UIKit and SwiftUI state captured directly from actor-isolated contexts
- other reference types that are not `Sendable`

This shifts failure from runtime to compile time, which is the primary goal of the change.

## API Semantics

The new API contract is:

- capability handlers execute on a background callback path owned by the Remo SDK
- capability handlers must be valid `@Sendable` closures
- callers must not assume main-thread or `MainActor` execution
- UI work must be explicitly handed off by the caller to the main thread or an appropriate actor

The docs should describe `Remo.register` as a background callback registration API, not a generic "register any closure" convenience.

## Expected Compile-Time Behavior

The following code should fail in Swift 6 strict concurrency mode:

```swift
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Remo.register("bad.example") { _ in
            self.doUIWork()
            return [:]
        }

        return true
    }

    private func doUIWork() {}
}
```

The same handler should become valid only after the user removes non-`Sendable` captures from the callback body and explicitly hops to main-thread execution where needed.

## Implementation Design

### Swift API Changes

- Replace the existing `Remo.register` signature with an `@Sendable` handler parameter
- Update the internal `HandlerBox` storage type to store an `@Sendable` closure
- Keep the trampoline synchronous; this change is about type safety, not execution model changes

### Example App Changes

- Update all example registrations to satisfy the `@Sendable` contract
- Remove or rewrite any helper functions that accept unconstrained handler closures
- Keep examples explicit about handing UI mutations back to the main queue

### Documentation Changes

Update the following first-party docs to use the new contract and wording:

- `README.md`
- `swift/RemoSwift/Sources/RemoSwift/Remo.swift` inline usage docs
- `skills/remo/SKILL.md`
- any other first-party example snippets that currently show the old callback shape

All code and prose should be in English.

## Migration Strategy

This is a breaking change with no compatibility layer.

Migration expectations for users:

1. existing `Remo.register` call sites continue to use the same method name
2. handlers that already satisfy `@Sendable` continue to compile
3. handlers that capture actor-isolated or non-`Sendable` state fail to compile
4. users must restructure those handlers to avoid unsafe captures and explicitly dispatch UI work

This migration is intentionally strict. The project should prefer compile-time friction over preserving a runtime crash path.

## Testing Requirements

### Swift API Regression Coverage

Add a first-party regression fixture that compiles the example app in Swift 6 strict concurrency mode with the new API contract enabled. The fixture should prove two things:

- safe first-party examples still build
- the unsafe reproduction pattern is no longer accepted by the compiler

### CI Coverage

The CI pipeline should continue to run simulator E2E, but API safety should no longer rely on runtime crash reproduction. The stronger guard is compile-time validation.

The desired CI coverage is:

- build RemoSwift and the example app under Swift 6 strict concurrency
- keep the simulator E2E suite green with the migrated examples
- add a regression check that fails if the `@Sendable` requirement is removed or bypassed

## Risks

### Source Breakage

This change will break existing apps that relied on the old permissive closure shape. That is acceptable and intentional.

### Partial Safety if Examples Stay on Swift 5

If first-party example targets stay on Swift 5 language mode, they will not exercise the intended compile-time checks. Swift 6 strict concurrency coverage must therefore be part of the example and CI story, not only local manual testing.

### False Sense of Safety

`@Sendable` does not automatically make callback bodies correct. It only gives the compiler enough information to reject a large class of invalid captures. The docs must still say that UI work requires explicit main-thread handoff.

## Success Criteria

This change is complete when all of the following are true:

- the old unconstrained `Remo.register` signature is gone
- the only public registration API requires an `@Sendable` handler
- first-party examples and docs compile and read correctly with the new contract
- Swift 6 strict concurrency builds reject the known bad capture pattern at compile time
- CI enforces the contract strongly enough that the old runtime trap path cannot re-enter unnoticed through first-party code
