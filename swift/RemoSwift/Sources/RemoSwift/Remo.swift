@_exported import RemoMacros

import Foundation

// MARK: - Public API

#if DEBUG

#if canImport(CRemo)

import CRemo

#endif

#endif

/// Remo: remote control bridge for iOS apps.
///
/// **Zero-config**: The server starts automatically when the library is loaded.
/// Simulator builds use a random port (to support multiple instances);
/// device builds use the well-known port 9930 (for USB tunnel access).
///
/// Remo is a debug-only tool and must never run in production — it opens an
/// unauthenticated TCP port. Macro-generated call sites are erased from Release.
///
/// Usage — register capabilities from a `#Remo` debug island; no `start()` needed:
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
///                     Navigator.shared.push(req.route ?? "/")
///                 }
///                 return RemoOK()
///             }
///         }
///     }
/// }
/// ```
public final class Remo {
    private init() {}

    /// Default port the Remo server listens on (device builds).
    public static let defaultPort: UInt16 = 9930

    /// Lazy auto-start: the server starts on first access to any Remo API.
    /// Simulator → random port (avoids collisions); device → 9930 (USB tunnel).
    private static let _ensureStarted: Bool = {
        #if canImport(CRemo)
        #if targetEnvironment(simulator)
        remo_start(0)
        #else
        remo_start(defaultPort)
        #endif
        return true
        #else
        return false
        #endif
    }()

    /// The actual port the server is listening on.
    public static var port: UInt16 {
        _ = _ensureStarted
        #if canImport(CRemo)
        return remo_get_port()
        #else
        return 0
        #endif
    }

    /// Manually start the server on a specific port.
    ///
    /// Normally unnecessary — the server auto-starts on first API access.
    /// The Rust side ignores subsequent calls; the server only starts once.
    /// This method remains public for tests and advanced embedding scenarios.
    public static func start(port: UInt16 = defaultPort) {
        #if canImport(CRemo)
        remo_start(port)
        #endif
    }

    /// Stop the server.
    public static func stop() {
        #if canImport(CRemo)
        remo_stop()
        #endif
    }

    /// Register a capability that can be invoked from macOS.
    ///
    /// Macro expansions call this API from app modules, so it must remain public.
    /// Hand-written app code should prefer `#remoCap(Type.self)` inside `#Remo`.
    ///
    /// The handler receives a JSON dictionary and must return a JSON-serializable
    /// dictionary representing a top-level JSON object.
    public static func register(
        _ name: String,
        handler: @Sendable @escaping ([String: Any]) -> [String: Any]
    ) {
        #if canImport(CRemo)
        _ = _ensureStarted
        let handlerBox = HandlerBox(handler: handler)
        let context = Unmanaged.passRetained(handlerBox).toOpaque()

        name.withCString { namePtr in
            remo_register_capability(namePtr, context, swiftCapabilityTrampoline)
        }
        #else
        // Host-side package builds only need the macro-facing API surface to exist.
        _ = name
        _ = handler
        #endif
    }

    /// Unregister a capability by name.
    ///
    /// Returns `true` if the capability was found and removed.
    @discardableResult
    public static func unregister(_ name: String) -> Bool {
        #if canImport(CRemo)
        name.withCString { namePtr in
            remo_unregister_capability(namePtr)
        }
        #else
        _ = name
        return false
        #endif
    }

    /// List capabilities registered on this device.
    public static func listCapabilities() -> [String] {
        #if canImport(CRemo)
        _ = _ensureStarted
        guard let ptr = remo_list_capabilities() else { return [] }
        defer { remo_free_string(ptr) }

        let str = String(cString: ptr)
        guard let data = str.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return arr
        #else
        return []
        #endif
    }

    /// Sleep until the current Swift Task is cancelled, then unregister named capabilities.
    ///
    /// When using `#remoScope`, `keepAlive` is called automatically — you do
    /// not need to call it yourself:
    /// ```swift
    /// .task {
    ///     await #Remo {
    ///         enum MyCap: RemoCapability {
    ///             static let name = "my.cap"
    ///         }
    ///
    ///         await #remoScope {
    ///             #remoCap(MyCap.self) { _ in
    ///                 return RemoOK()
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    /// When the view disappears, SwiftUI cancels the task, this function returns,
    /// and all named capabilities are unregistered.
    public static func keepAlive(_ names: String...) async {
        try? await Task.sleep(nanoseconds: .max) // CancellationError intentionally swallowed — execution continues to unregister
        names.forEach { unregister($0) }
    }
}

/// Macro-plumbing runtime helpers used by generated code in consuming modules.
///
/// This surface intentionally avoids the public `Remo` type name because it
/// collides with the `#Remo` freestanding macro in downstream modules.
public enum _RemoRuntime {
    public static func register(
        _ name: String,
        handler: @Sendable @escaping ([String: Any]) -> [String: Any]
    ) {
        Remo.register(name, handler: handler)
    }

    @discardableResult
    public static func unregister(_ name: String) -> Bool {
        Remo.unregister(name)
    }

    public static func keepAlive(_ names: String...) async {
        try? await Task.sleep(nanoseconds: .max)
        names.forEach { _ = Remo.unregister($0) }
    }
}

// MARK: - Internals

#if canImport(CRemo)

/// Box to prevent the Swift closure from being deallocated.
private final class HandlerBox {
    let handler: @Sendable ([String: Any]) -> [String: Any]
    init(handler: @Sendable @escaping ([String: Any]) -> [String: Any]) {
        self.handler = handler
    }
}

/// C-compatible trampoline that bridges Rust -> Swift handler calls.
private let swiftCapabilityTrampoline: remo_capability_callback = { context, paramsPtr in
    guard let context = context, let paramsPtr = paramsPtr else {
        return strdup("{\"error\": \"null context or params\"}")
    }

    let handlerBox = Unmanaged<HandlerBox>.fromOpaque(context).takeUnretainedValue()

    let paramsString = String(cString: paramsPtr)
    let params: [String: Any]
    if let data = paramsString.data(using: .utf8),
       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        params = dict
    } else {
        params = [:]
    }

    let result = handlerBox.handler(params)

    guard let resultData = try? JSONSerialization.data(withJSONObject: result),
          let resultString = String(data: resultData, encoding: .utf8) else {
        return strdup("{\"error\": \"serialization failed\"}")
    }

    return strdup(resultString)
}

#endif
