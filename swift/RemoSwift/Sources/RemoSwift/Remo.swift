import Foundation
import CRemo

// MARK: - Public API

/// Remo: remote control bridge for iOS apps.
///
/// Usage:
/// ```swift
/// Remo.register("navigate") { params in
///     let route = params["route"] as? String ?? "/"
///     Navigator.shared.push(route)
///     return ["status": "ok"]
/// }
/// Remo.start()
/// ```
public final class Remo {

    /// Default port the Remo server listens on.
    public static let defaultPort: UInt16 = 9930

    /// Start the embedded TCP server.
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
        let handlerBox = HandlerBox(handler: handler)
        let context = Unmanaged.passRetained(handlerBox).toOpaque()

        name.withCString { namePtr in
            remo_register_capability(namePtr, context, swiftCapabilityTrampoline)
        }
    }

    /// List capabilities registered on this device.
    public static func listCapabilities() -> [String] {
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
