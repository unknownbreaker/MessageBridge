// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "MessageBridgeServer",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "MessageBridgeCore", targets: ["MessageBridgeCore"]),
    .executable(name: "MessageBridgeServer", targets: ["MessageBridgeServer"]),
  ],
  dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
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
        "MessageBridgeCore"
      ],
      path: "Sources/MessageBridgeServer"
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
