// swift-tools-version: 6.1

import PackageDescription
import Foundation

// Set REMO_LOCAL=1 to use the monorepo source (for development).
// Default: use the published remo-spm binary package.
let useLocal = ProcessInfo.processInfo.environment["REMO_LOCAL"] != nil

let remoDependency: Package.Dependency = useLocal
    ? .package(path: "../../../swift/RemoSwift")
    : .package(url: "https://github.com/yi-jiang-applovin/remo-spm.git", from: "0.4.0")

let remoProduct: Target.Dependency = .product(
    name: "RemoSwift",
    package: useLocal ? "RemoSwift" : "remo-spm"
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
