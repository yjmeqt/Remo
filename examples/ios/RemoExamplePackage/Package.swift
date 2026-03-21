// swift-tools-version: 6.1

import PackageDescription

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
        .package(path: "../../../swift/RemoSwift"),
    ],
    targets: [
        .target(
            name: "RemoExampleFeature",
            dependencies: [
                .product(name: "RemoSwift", package: "RemoSwift"),
            ]
        ),
        .testTarget(
            name: "RemoExampleFeatureTests",
            dependencies: [
                "RemoExampleFeature"
            ]
        ),
    ]
)
