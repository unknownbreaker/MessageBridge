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
        .executableTarget(
            name: "MessageBridgeClient",
            path: "Sources/MessageBridgeClient",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
