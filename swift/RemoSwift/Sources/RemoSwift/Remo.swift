import Foundation

// MARK: - Public API

#if DEBUG

import CRemo

/// Remo: remote control bridge for iOS apps.
///
/// **Zero-config**: The server starts automatically when the library is loaded.
/// Simulator builds use a random port (to support multiple instances);
/// device builds use the well-known port 9930 (for USB tunnel access).
///
/// In Release builds, all methods are no-ops. Remo is a debug-only tool and
/// must never run in production — it opens an unauthenticated TCP port.
///
/// Usage — just register capabilities; no `start()` needed:
/// ```swift
/// Remo.register("navigate") { params in
///     let route = params["route"] as? String ?? "/"
///     Navigator.shared.push(route)
///     return ["status": "ok"]
/// }
/// ```
public final class Remo {
    private init() {}

    /// Default port the Remo server listens on (device builds).
    public static let defaultPort: UInt16 = 9930

    /// Lazy auto-start: the server starts on first access to any Remo API.
    /// Simulator → random port (avoids collisions); device → 9930 (USB tunnel).
    private static let _ensureStarted: Bool = {
        #if targetEnvironment(simulator)
        remo_start(0)
        #else
        remo_start(defaultPort)
        #endif
        return true
    }()

    /// The actual port the server is listening on.
    public static var port: UInt16 {
        _ = _ensureStarted
        return remo_get_port()
    }

    /// Manually start the server on a specific port.
    ///
    /// Normally unnecessary — the server auto-starts on first API access.
    /// The Rust side ignores subsequent calls; the server only starts once.
    public static func start(port: UInt16 = defaultPort) {
        remo_start(port)
    }

    /// Stop the server.
    public static func stop() {
        remo_stop()
    }

    /// Register a capability that can be invoked from macOS.
    ///
    /// The handler receives a JSON dictionary and must return a JSON-serializable dictionary.
    public static func register(_ name: String, handler: @escaping ([String: Any]) -> [String: Any]) {
        _ = _ensureStarted
        let handlerBox = HandlerBox(handler: handler)
        let context = Unmanaged.passRetained(handlerBox).toOpaque()

        name.withCString { namePtr in
            remo_register_capability(namePtr, context, swiftCapabilityTrampoline)
        }
    }

    /// List capabilities registered on this device.
    public static func listCapabilities() -> [String] {
        _ = _ensureStarted
        guard let ptr = remo_list_capabilities() else { return [] }
        defer { remo_free_string(ptr) }

        let str = String(cString: ptr)
        guard let data = str.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return arr
    }
}

// MARK: - Internals

/// Box to prevent the Swift closure from being deallocated.
private final class HandlerBox {
    let handler: ([String: Any]) -> [String: Any]
    init(handler: @escaping ([String: Any]) -> [String: Any]) {
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

#else

// Release build: empty stubs so call sites compile but do nothing.
public final class Remo {
    private init() {}

    public static let defaultPort: UInt16 = 9930
    public static var port: UInt16 { 0 }
    public static func start(port: UInt16 = defaultPort) {}
    public static func stop() {}
    public static func register(_ name: String, handler: @escaping ([String: Any]) -> [String: Any]) {}
    public static func listCapabilities() -> [String] { [] }
}

#endif
