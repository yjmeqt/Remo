// swift-tools-version: 6.1

import PackageDescription
import Foundation

// Default: use the monorepo source package.
// Set REMO_USE_REMOTE=1 to opt into the published remo-spm package.
let useRemote = ProcessInfo.processInfo.environment["REMO_USE_REMOTE"] != nil

let remoDependency: Package.Dependency = useRemote
    ? .package(url: "https://github.com/yjmeqt/remo-spm.git", from: "0.4.0")
    : .package(path: "../../../swift/RemoSwift")

let remoProduct: Target.Dependency = .product(
    name: "RemoSwift",
    package: useRemote ? "remo-spm" : "RemoSwift"
)

let package = Package(
    name: "RemoExampleFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "RemoExampleFeature",
            targets: ["RemoExampleFeature"]
        ),
    ],
    dependencies: [
        remoDependency,
    ],
    targets: [
        .target(
            name: "RemoExampleFeature",
            dependencies: [remoProduct]
        ),
        .testTarget(
            name: "RemoExampleFeatureTests",
            dependencies: ["RemoExampleFeature"]
        ),
    ]
)
