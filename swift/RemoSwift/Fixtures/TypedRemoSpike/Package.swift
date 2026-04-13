// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TypedRemoSpike",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TypedRemoStmtProbe", targets: ["TypedRemoStmtProbe"]),
        .library(name: "TypedRemoTaskProbe", targets: ["TypedRemoTaskProbe"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "TypedRemoStmtProbe",
            dependencies: [
                .product(name: "RemoSwift", package: "RemoSwift"),
            ]
        ),
        .target(
            name: "TypedRemoTaskProbe",
            dependencies: [
                .product(name: "RemoSwift", package: "RemoSwift"),
            ]
        ),
    ]
)
