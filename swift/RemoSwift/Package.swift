// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "RemoSwift",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "RemoSwift", targets: ["RemoSwift"]),
        .library(name: "RemoObjC", targets: ["RemoObjC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "CRemo",
            path: "../RemoSDK.xcframework"
        ),
        .macro(
            name: "RemoMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "RemoMacros",
            dependencies: ["RemoMacrosPlugin"]
        ),
        .target(
            name: "RemoSwift",
            dependencies: ["CRemo", "RemoMacros"],
            path: "Sources/RemoSwift",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Security"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .target(
            name: "RemoObjC",
            dependencies: ["CRemo"],
            path: "Sources/RemoObjC",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Security"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .testTarget(
            name: "RemoMacrosTests",
            dependencies: [
                "RemoMacros",
                "RemoMacrosPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
