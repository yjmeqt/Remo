/// Marker protocol for typed Remo capabilities declared inside a `#Remo` island.
public protocol RemoCapability {
    static var name: String { get }
    associatedtype Request: Decodable = RemoEmpty
    associatedtype Response: Encodable = RemoOK
}

/// Empty request payload for capabilities that accept no params.
public struct RemoEmpty: Decodable {
    public init() {}
}

/// Default success payload for capabilities that only report "ok".
public struct RemoOK: Encodable {
    public let status: String = "ok"

    public init() {}
}
