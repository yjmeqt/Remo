/// Debug-only container for sync statement contexts.
///
/// Use `#Remo` as the outer debug island for local capability declarations and
/// registration code that must disappear in Release:
///
/// ```swift
/// #Remo {
///     enum Navigate: RemoCapability {
///         static let name = "navigate"
///         struct Request: Decodable { let route: String? }
///         typealias Response = RemoOK
///     }
///
///     #remoScope(scopedTo: self) {
///         #remoCap(Navigate.self) { req in
///             return RemoOK()
///         }
///     }
/// }
/// ```
@freestanding(expression)
public macro Remo(
    _ body: () -> Void
) = #externalMacro(module: "RemoMacrosPlugin", type: "RemoContainerStmtMacro")

/// Debug-only container for async statement contexts.
///
/// In SwiftUI, declare capability types and register them inside the same
/// `.task { await #Remo { ... } }` island so they disappear together in Release:
///
/// ```swift
/// .task {
///     await #Remo {
///         enum Navigate: RemoCapability {
///             static let name = "navigate"
///             struct Request: Decodable { let route: String? }
///             typealias Response = RemoOK
///         }
///
///         await #remoScope {
///             #remoCap(Navigate.self) { req in
///                 Task { @MainActor in
///                     store.currentRoute = req.route ?? "home"
///                 }
///                 return RemoOK()
///             }
///         }
///     }
/// }
/// ```
@freestanding(expression)
public macro Remo(
    _ body: () async -> Void
) = #externalMacro(module: "RemoMacrosPlugin", type: "RemoContainerAsyncStmtMacro")

/// Register a typed Remo capability inside a `#Remo` debug island.
///
/// The capability type must be declared inside the same `#Remo` block that
/// calls `#remoCap(Type.self)`. The macro decodes the incoming JSON object into
/// `T.Request`, executes the handler, then encodes `T.Response` back to a JSON
/// object dictionary for the runtime bridge.
@freestanding(expression)
public macro remoCap<T: RemoCapability>(
    _ type: T.Type,
    _ handler: @escaping (T.Request) -> T.Response
) = #externalMacro(module: "RemoMacrosPlugin", type: "RemoCapTypedMacro")

/// Async lifecycle scope for SwiftUI-style registration islands.
///
/// Extracts capability names from nested `#remoCap(Type.self)` calls and
/// automatically keeps them registered until the enclosing task is cancelled.
@freestanding(expression)
public macro remoScope(
    _ body: () async -> Void
) = #externalMacro(module: "RemoMacrosPlugin", type: "RemoScopeAsyncMacro")

/// UIKit lifecycle scope for view-controller-scoped registrations.
///
/// Extracts capability names from nested `#remoCap(Type.self)` calls and
/// automatically tracks them for unregister-on-disappear behavior.
@freestanding(expression)
public macro remoScope(
    scopedTo owner: AnyObject,
    _ body: () -> Void
) = #externalMacro(module: "RemoMacrosPlugin", type: "RemoScopeSyncMacro")
