/// Register a Remo capability (debug only). Expands to nothing in release builds.
///
/// The handler receives a `RemoParams` wrapper for ergonomic typed access:
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
///     Remo.register("navigate") { _ in [:] }
///     Remo.register("state.get") { _ in [:] }
/// }
/// ```
@freestanding(expression)
public macro remo(
    _ body: () -> Void
) = #externalMacro(module: "RemoMacrosPlugin", type: "RemoBlockMacro")
