// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MessageBridgeClient",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MessageBridgeClient", targets: ["MessageBridgeClient"])
    ],
    targets: [
        .target(
            name: "MessageBridgeClientCore",
            path: "Sources/MessageBridgeClientCore"
        ),
        .executableTarget(
            name: "MessageBridgeClient",
            dependencies: ["MessageBridgeClientCore"],
            path: "Sources/MessageBridgeClient",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "MessageBridgeClientCoreTests",
            dependencies: ["MessageBridgeClientCore"]
        )
    ]
)
