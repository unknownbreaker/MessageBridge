// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MessageBridgeServer",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "MessageBridgeCore",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/MessageBridgeCore"
        ),
        .executableTarget(
            name: "MessageBridgeServer",
            dependencies: [
                "MessageBridgeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "MessageBridgeCoreTests",
            dependencies: [
                "MessageBridgeCore",
                .product(name: "XCTVapor", package: "vapor"),
            ]
        ),
    ]
)
