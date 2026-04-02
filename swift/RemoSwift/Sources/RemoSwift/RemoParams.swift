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
