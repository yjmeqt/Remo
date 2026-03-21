// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "RemoSwift",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "RemoSwift", targets: ["RemoSwift"]),
    ],
    targets: [
        // The Rust static library packaged as an XCFramework.
        .binaryTarget(
            name: "CRemo",
            path: "../RemoSDK.xcframework"
        ),
        // CRemo is imported only in DEBUG builds (#if DEBUG in Remo.swift).
        // SPM still requires the binary for dependency resolution,
        // but unreferenced symbols are stripped by the linker in Release.
        .target(
            name: "RemoSwift",
            dependencies: ["CRemo"],
            path: "Sources/RemoSwift",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Security"),
            ]
        ),
    ]
)
