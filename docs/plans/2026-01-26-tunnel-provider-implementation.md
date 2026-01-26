# TunnelProvider Protocol Migration - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate three tunnel managers (Tailscale, Cloudflare, ngrok) to implement a unified `TunnelProvider` protocol with registry pattern.

**Architecture:** Protocol-driven design where each tunnel type implements `TunnelProvider`. A singleton `TunnelRegistry` holds all providers. UI components query the registry and work with any provider uniformly.

**Tech Stack:** Swift 5.9+, Swift Actors for thread safety, SwiftUI for settings views

**Design Document:** `docs/plans/2026-01-26-tunnel-provider-protocol-design.md`

---

## Task 1: Create TunnelError Type

**Files:**
- Create: `MessageBridgeServer/Sources/MessageBridgeCore/Tunnels/TunnelError.swift`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Tunnels/TunnelErrorTests.swift`

**Step 1: Create the error type**

```swift
// MessageBridgeServer/Sources/MessageBridgeCore/Tunnels/TunnelError.swift

import Foundation

/// Unified error type for all tunnel provider operations
public enum TunnelError: LocalizedError, Sendable, Equatable {
    /// The tunnel tool is not installed on the system
    case notInstalled(provider: String)

    /// Installation of the tunnel tool failed
    case installationFailed(reason: String)

    /// Failed to establish tunnel connection
    case connectionFailed(String)

    /// Tunnel process terminated unexpectedly
    case unexpectedTermination(exitCode: Int32)

    /// Timed out waiting for tunnel to establish
    case timeout

    /// User action required (e.g., connect in external app, verify email)
    case userActionRequired(String)

    /// Authentication or authorization failed
    case authenticationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let provider):
            return "\(provider) is not installed"
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .unexpectedTermination(let code):
            return "Tunnel terminated unexpectedly (exit code \(code))"
        case .timeout:
            return "Timed out waiting for tunnel connection"
        case .userActionRequired(let action):
            return action
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        }
    }
}
```

**Step 2: Write the test file**

```swift
// MessageBridgeServer/Tests/MessageBridgeCoreTests/Tunnels/TunnelErrorTests.swift

import XCTest
@testable import MessageBridgeCore

final class TunnelErrorTests: XCTestCase {

    func testNotInstalledDescription() {
        let error = TunnelError.notInstalled(provider: "cloudflare")
        XCTAssertEqual(error.errorDescription, "cloudflare is not installed")
    }

    func testConnectionFailedDescription() {
        let error = TunnelError.connectionFailed("network unreachable")
        XCTAssertEqual(error.errorDescription, "Connection failed: network unreachable")
    }

    func testTimeoutDescription() {
        let error = TunnelError.timeout
        XCTAssertEqual(error.errorDescription, "Timed out waiting for tunnel connection")
    }

    func testUserActionRequiredDescription() {
        let error = TunnelError.userActionRequired("Please connect in Tailscale app")
        XCTAssertEqual(error.errorDescription, "Please connect in Tailscale app")
    }

    func testErrorEquality() {
        XCTAssertEqual(TunnelError.timeout, TunnelError.timeout)
        XCTAssertEqual(
            TunnelError.notInstalled(provider: "ngrok"),
            TunnelError.notInstalled(provider: "ngrok")
        )
        XCTAssertNotEqual(
            TunnelError.notInstalled(provider: "ngrok"),
            TunnelError.notInstalled(provider: "cloudflare")
        )
    }
}
```

**Step 3: Run tests to verify they pass**

Run: `cd MessageBridgeServer && swift test --filter TunnelErrorTests`
Expected: All tests pass

**Step 4: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Tunnels/TunnelError.swift \
        MessageBridgeServer/Tests/MessageBridgeCoreTests/Tunnels/TunnelErrorTests.swift
git commit -m "feat: add unified TunnelError type for tunnel providers"
```

---

## Task 2: Create TunnelProvider Protocol

**Files:**
- Create: `MessageBridgeServer/Sources/MessageBridgeCore/Protocols/TunnelProvider.swift`

**Step 1: Create the Protocols directory and protocol file**

```swift
// MessageBridgeServer/Sources/MessageBridgeCore/Protocols/TunnelProvider.swift

import Foundation

/// A tunnel provider that enables remote access to the MessageBridge server.
///
/// Implementations handle the details of different tunnel technologies:
/// - **Tailscale**: VPN mesh network (external app manages connection)
/// - **Cloudflare**: Quick tunnels via cloudflared process
/// - **ngrok**: Tunnels via ngrok process
///
/// ## Usage
///
/// ```swift
/// // Register providers at app startup
/// TunnelRegistry.shared.register(CloudflareProvider())
/// TunnelRegistry.shared.register(NgrokProvider())
/// TunnelRegistry.shared.register(TailscaleProvider())
///
/// // Connect via any provider
/// let provider = TunnelRegistry.shared.get("cloudflare")!
/// let url = try await provider.connect(port: 8080)
/// ```
public protocol TunnelProvider: Actor, Identifiable, Sendable {
    /// Unique identifier for this provider (e.g., "tailscale", "cloudflare", "ngrok")
    var id: String { get }

    /// Human-readable name for UI display
    var displayName: String { get }

    /// Short description of the tunnel type and its characteristics
    var description: String { get }

    /// SF Symbol name for the provider icon in UI
    var iconName: String { get }

    /// Current status of the tunnel
    var status: TunnelStatus { get async }

    /// Whether the underlying tunnel tool is installed on the system
    /// - Returns: `true` if the tool is available, `false` otherwise
    func isInstalled() -> Bool

    /// Connect or activate the tunnel.
    ///
    /// The behavior varies by provider type:
    /// - **Process-based** (Cloudflare, ngrok): Starts the tunnel process
    /// - **External** (Tailscale): Verifies connection, may prompt user
    ///
    /// - Parameter port: The local port to expose through the tunnel
    /// - Returns: The public URL or IP address for accessing the tunnel
    /// - Throws: `TunnelError` if connection fails
    func connect(port: Int) async throws -> String

    /// Disconnect or deactivate the tunnel.
    ///
    /// For process-based tunnels, this terminates the process.
    /// For external tunnels (like Tailscale), this may be a no-op.
    func disconnect() async

    /// Register a callback to be notified of status changes.
    /// - Parameter handler: Closure called when status changes
    func onStatusChange(_ handler: @escaping (TunnelStatus) -> Void)
}

// MARK: - Default Implementations

public extension TunnelProvider {
    /// Default Identifiable conformance using the id property
    var id: String { id }
}
```

**Step 2: Verify the file compiles**

Run: `cd MessageBridgeServer && swift build`
Expected: Build succeeds (protocol references existing `TunnelStatus` from `TunnelTypes.swift`)

**Step 3: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Protocols/TunnelProvider.swift
git commit -m "feat: add TunnelProvider protocol for unified tunnel interface"
```

---

## Task 3: Create TunnelRegistry

**Files:**
- Create: `MessageBridgeServer/Sources/MessageBridgeCore/Registries/TunnelRegistry.swift`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Registries/TunnelRegistryTests.swift`
- Create: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Mocks/MockTunnelProvider.swift`

**Step 1: Create MockTunnelProvider for testing**

```swift
// MessageBridgeServer/Tests/MessageBridgeCoreTests/Mocks/MockTunnelProvider.swift

import Foundation
@testable import MessageBridgeCore

/// Mock tunnel provider for testing
public actor MockTunnelProvider: TunnelProvider {
    public let id: String
    public let displayName: String
    public let description: String
    public let iconName: String

    private var _status: TunnelStatus = .stopped
    private var _isInstalled: Bool
    private var statusHandler: ((TunnelStatus) -> Void)?

    /// Set this to make connect() throw an error
    public var shouldFailConnect: TunnelError?

    /// Set this to control the returned URL
    public var mockURL: String = "https://mock-tunnel.example.com"

    /// Delay before connect completes (for testing async behavior)
    public var connectDelay: Duration = .zero

    public init(
        id: String = "mock",
        displayName: String = "Mock Tunnel",
        description: String = "Mock tunnel for testing",
        iconName: String = "testtube.2",
        isInstalled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.iconName = iconName
        self._isInstalled = isInstalled
    }

    public var status: TunnelStatus {
        get async { _status }
    }

    public nonisolated func isInstalled() -> Bool {
        // For testing, we use a simple flag
        // In real implementation this checks file system
        true
    }

    // Internal method to check installed state (actor-isolated)
    public func checkInstalled() -> Bool {
        _isInstalled
    }

    public func connect(port: Int) async throws -> String {
        if let error = shouldFailConnect {
            throw error
        }

        updateStatus(.starting)

        if connectDelay > .zero {
            try await Task.sleep(for: connectDelay)
        }

        updateStatus(.running(url: mockURL, isQuickTunnel: true))
        return mockURL
    }

    public func disconnect() async {
        updateStatus(.stopped)
    }

    public func onStatusChange(_ handler: @escaping (TunnelStatus) -> Void) {
        statusHandler = handler
    }

    // MARK: - Test Helpers

    public func setInstalled(_ installed: Bool) {
        _isInstalled = installed
    }

    public func simulateStatus(_ status: TunnelStatus) {
        updateStatus(status)
    }

    private func updateStatus(_ newStatus: TunnelStatus) {
        _status = newStatus
        statusHandler?(newStatus)
    }
}
```

**Step 2: Create TunnelRegistry**

```swift
// MessageBridgeServer/Sources/MessageBridgeCore/Registries/TunnelRegistry.swift

import Foundation

/// Central registry for all tunnel providers.
///
/// The registry is a singleton that holds references to all available tunnel providers.
/// Providers register themselves at app startup, and UI components query the registry
/// to discover and interact with providers.
///
/// ## Usage
///
/// ```swift
/// // At app startup
/// TunnelRegistry.shared.register(CloudflareProvider())
/// TunnelRegistry.shared.register(NgrokProvider())
///
/// // Query providers
/// let allProviders = TunnelRegistry.shared.all
/// let cloudflare = TunnelRegistry.shared.get("cloudflare")
/// ```
///
/// ## Thread Safety
///
/// All methods are thread-safe and can be called from any thread.
public final class TunnelRegistry: @unchecked Sendable {
    /// Shared singleton instance
    public static let shared = TunnelRegistry()

    private var providers: [String: any TunnelProvider] = [:]
    private let lock = NSLock()

    private init() {}

    /// Register a tunnel provider.
    ///
    /// If a provider with the same ID is already registered, it will be replaced.
    ///
    /// - Parameter provider: The provider to register
    public func register(_ provider: any TunnelProvider) {
        lock.lock()
        defer { lock.unlock() }
        providers[provider.id] = provider
    }

    /// Get a provider by its ID.
    ///
    /// - Parameter id: The provider's unique identifier
    /// - Returns: The provider if found, `nil` otherwise
    public func get(_ id: String) -> (any TunnelProvider)? {
        lock.lock()
        defer { lock.unlock() }
        return providers[id]
    }

    /// All registered providers.
    ///
    /// The order of providers is not guaranteed.
    public var all: [any TunnelProvider] {
        lock.lock()
        defer { lock.unlock() }
        return Array(providers.values)
    }

    /// The number of registered providers.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return providers.count
    }

    /// Check if a provider with the given ID is registered.
    ///
    /// - Parameter id: The provider's unique identifier
    /// - Returns: `true` if registered, `false` otherwise
    public func contains(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return providers[id] != nil
    }

    /// Remove a provider by its ID.
    ///
    /// - Parameter id: The provider's unique identifier
    /// - Returns: The removed provider if found, `nil` otherwise
    @discardableResult
    public func remove(_ id: String) -> (any TunnelProvider)? {
        lock.lock()
        defer { lock.unlock() }
        return providers.removeValue(forKey: id)
    }

    /// Remove all registered providers.
    ///
    /// Primarily useful for testing.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        providers.removeAll()
    }
}
```

**Step 3: Write registry tests**

```swift
// MessageBridgeServer/Tests/MessageBridgeCoreTests/Registries/TunnelRegistryTests.swift

import XCTest
@testable import MessageBridgeCore

final class TunnelRegistryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TunnelRegistry.shared.reset()
    }

    override func tearDown() {
        TunnelRegistry.shared.reset()
        super.tearDown()
    }

    func testRegisterAndGet() async {
        let mock = MockTunnelProvider(id: "test-provider")
        TunnelRegistry.shared.register(mock)

        let retrieved = TunnelRegistry.shared.get("test-provider")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "test-provider")
    }

    func testGetNonExistent() {
        let retrieved = TunnelRegistry.shared.get("does-not-exist")
        XCTAssertNil(retrieved)
    }

    func testAll() async {
        let mock1 = MockTunnelProvider(id: "provider-1")
        let mock2 = MockTunnelProvider(id: "provider-2")

        TunnelRegistry.shared.register(mock1)
        TunnelRegistry.shared.register(mock2)

        let all = TunnelRegistry.shared.all
        XCTAssertEqual(all.count, 2)

        let ids = Set(all.map { $0.id })
        XCTAssertTrue(ids.contains("provider-1"))
        XCTAssertTrue(ids.contains("provider-2"))
    }

    func testCount() async {
        XCTAssertEqual(TunnelRegistry.shared.count, 0)

        TunnelRegistry.shared.register(MockTunnelProvider(id: "p1"))
        XCTAssertEqual(TunnelRegistry.shared.count, 1)

        TunnelRegistry.shared.register(MockTunnelProvider(id: "p2"))
        XCTAssertEqual(TunnelRegistry.shared.count, 2)
    }

    func testContains() async {
        XCTAssertFalse(TunnelRegistry.shared.contains("test"))

        TunnelRegistry.shared.register(MockTunnelProvider(id: "test"))
        XCTAssertTrue(TunnelRegistry.shared.contains("test"))
    }

    func testRemove() async {
        let mock = MockTunnelProvider(id: "to-remove")
        TunnelRegistry.shared.register(mock)
        XCTAssertTrue(TunnelRegistry.shared.contains("to-remove"))

        let removed = TunnelRegistry.shared.remove("to-remove")
        XCTAssertNotNil(removed)
        XCTAssertFalse(TunnelRegistry.shared.contains("to-remove"))
    }

    func testReset() async {
        TunnelRegistry.shared.register(MockTunnelProvider(id: "p1"))
        TunnelRegistry.shared.register(MockTunnelProvider(id: "p2"))
        XCTAssertEqual(TunnelRegistry.shared.count, 2)

        TunnelRegistry.shared.reset()
        XCTAssertEqual(TunnelRegistry.shared.count, 0)
    }

    func testRegisterReplaces() async {
        let mock1 = MockTunnelProvider(id: "same-id", displayName: "First")
        let mock2 = MockTunnelProvider(id: "same-id", displayName: "Second")

        TunnelRegistry.shared.register(mock1)
        TunnelRegistry.shared.register(mock2)

        XCTAssertEqual(TunnelRegistry.shared.count, 1)

        let retrieved = TunnelRegistry.shared.get("same-id")
        XCTAssertEqual(retrieved?.displayName, "Second")
    }
}
```

**Step 4: Run tests**

Run: `cd MessageBridgeServer && swift test --filter TunnelRegistryTests`
Expected: All tests pass

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Registries/TunnelRegistry.swift \
        MessageBridgeServer/Tests/MessageBridgeCoreTests/Registries/TunnelRegistryTests.swift \
        MessageBridgeServer/Tests/MessageBridgeCoreTests/Mocks/MockTunnelProvider.swift
git commit -m "feat: add TunnelRegistry for provider discovery"
```

---

## Task 4: Migrate CloudflaredManager to CloudflareProvider

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Cloudflare/CloudflaredManager.swift`

**Step 1: Add TunnelProvider conformance to CloudflaredManager**

Add the protocol conformance and required properties. The existing methods map cleanly:
- `startQuickTunnel(port:)` → `connect(port:)`
- `stopTunnel()` → `disconnect()`
- `status` property already exists
- `onStatusChange(_:)` already exists
- `isInstalled()` already exists

Edit `CloudflaredManager.swift`:

```swift
// At the top, change:
public actor CloudflaredManager {

// To:
public actor CloudflaredManager: TunnelProvider {

    // MARK: - TunnelProvider Conformance

    public let id = "cloudflare"
    public let displayName = "Cloudflare Tunnel"
    public let description = "Free, no account required. May be blocked by some corporate firewalls."
    public let iconName = "cloud"

    public func connect(port: Int) async throws -> String {
        try await startQuickTunnel(port: port)
    }

    public func disconnect() async {
        await stopTunnel()
    }

    // ... rest of existing implementation unchanged
```

Also update the error throwing to use `TunnelError`:

```swift
// In startQuickTunnel, change:
throw CloudflaredError.notInstalled
// To:
throw TunnelError.notInstalled(provider: id)

// Change:
throw CloudflaredError.failedToStart(error.localizedDescription)
// To:
throw TunnelError.connectionFailed(error.localizedDescription)

// Change:
throw CloudflaredError.tunnelFailed(message)
// To:
throw TunnelError.connectionFailed(message)

// Change:
throw CloudflaredError.timeout
// To:
throw TunnelError.timeout
```

**Step 2: Verify build succeeds**

Run: `cd MessageBridgeServer && swift build`
Expected: Build succeeds

**Step 3: Run existing tests**

Run: `cd MessageBridgeServer && swift test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Cloudflare/CloudflaredManager.swift
git commit -m "feat: add TunnelProvider conformance to CloudflaredManager"
```

---

## Task 5: Migrate NgrokManager to NgrokProvider

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Ngrok/NgrokManager.swift`

**Step 1: Add TunnelProvider conformance to NgrokManager**

Same pattern as CloudflaredManager:

```swift
// At the top, change:
public actor NgrokManager {

// To:
public actor NgrokManager: TunnelProvider {

    // MARK: - TunnelProvider Conformance

    public let id = "ngrok"
    public let displayName = "ngrok"
    public let description = "Widely used, often whitelisted by corporate networks. Free tier available."
    public let iconName = "network"

    public func connect(port: Int) async throws -> String {
        try await startTunnel(port: port)
    }

    public func disconnect() async {
        await stopTunnel()
    }

    // ... rest of existing implementation unchanged
```

Update error throwing to use `TunnelError`:

```swift
// In startTunnel, change:
throw NgrokError.notInstalled
// To:
throw TunnelError.notInstalled(provider: id)

// Change:
throw NgrokError.failedToStart(error.localizedDescription)
// To:
throw TunnelError.connectionFailed(error.localizedDescription)

// Change:
throw NgrokError.tunnelFailed(message)
// To:
throw TunnelError.connectionFailed(message)

// Change:
throw NgrokError.timeout
// To:
throw TunnelError.timeout
```

**Step 2: Verify build succeeds**

Run: `cd MessageBridgeServer && swift build`
Expected: Build succeeds

**Step 3: Run existing tests**

Run: `cd MessageBridgeServer && swift test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Ngrok/NgrokManager.swift
git commit -m "feat: add TunnelProvider conformance to NgrokManager"
```

---

## Task 6: Migrate TailscaleManager to TailscaleProvider

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Tailscale/TailscaleManager.swift`

Tailscale is different — it doesn't manage a process, it reads status from the external Tailscale app. The `connect()` method will either return the IP if already connected, or prompt the user to connect manually.

**Step 1: Add TunnelProvider conformance to TailscaleManager**

```swift
// At the top, change:
public actor TailscaleManager {

// To:
public actor TailscaleManager: TunnelProvider {

    // MARK: - TunnelProvider Conformance

    public let id = "tailscale"
    public let displayName = "Tailscale"
    public let description = "VPN mesh network. Requires Tailscale app installed separately."
    public let iconName = "point.3.connected.trianglepath.dotted"

    /// Callback for status changes (required by protocol)
    private var statusChangeHandler: ((TunnelStatus) -> Void)?

    /// Bridge from TailscaleStatus to TunnelStatus
    public var status: TunnelStatus {
        get async {
            let tsStatus = await getStatus()
            return tsStatus.toTunnelStatus()
        }
    }

    public func connect(port: Int) async throws -> String {
        let tsStatus = await getStatus(forceRefresh: true)

        switch tsStatus {
        case .connected(let ip, _):
            return ip
        case .notInstalled:
            throw TunnelError.notInstalled(provider: id)
        case .stopped:
            openTailscaleApp()
            throw TunnelError.userActionRequired("Please connect in the Tailscale app")
        case .connecting:
            throw TunnelError.userActionRequired("Tailscale is connecting. Please wait or check the Tailscale app.")
        case .error(let message):
            throw TunnelError.connectionFailed(message)
        }
    }

    public func disconnect() async {
        // No-op: Tailscale is managed by the external app
        // We don't disconnect the user's VPN automatically
    }

    public func onStatusChange(_ handler: @escaping (TunnelStatus) -> Void) {
        statusChangeHandler = handler
    }

    // ... rest of existing implementation unchanged
```

**Step 2: Add TailscaleStatus to TunnelStatus conversion**

Add this extension at the bottom of `TailscaleManager.swift`:

```swift
// MARK: - Status Conversion

extension TailscaleStatus {
    /// Convert TailscaleStatus to the unified TunnelStatus
    func toTunnelStatus() -> TunnelStatus {
        switch self {
        case .notInstalled:
            return .notInstalled
        case .stopped:
            return .stopped
        case .connecting:
            return .starting
        case .connected(let ip, _):
            // For Tailscale, the URL is the IP address
            return .running(url: ip, isQuickTunnel: false)
        case .error(let message):
            return .error(message)
        }
    }
}
```

**Step 3: Verify build succeeds**

Run: `cd MessageBridgeServer && swift build`
Expected: Build succeeds

**Step 4: Run existing tests**

Run: `cd MessageBridgeServer && swift test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Tailscale/TailscaleManager.swift
git commit -m "feat: add TunnelProvider conformance to TailscaleManager"
```

---

## Task 7: Update TunnelTypes.swift

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Tunnel/TunnelTypes.swift`

The current file has a `TunnelProvider` enum that conflicts with our new protocol. Remove it and add a `notInstalled` case to `TunnelStatus`.

**Step 1: Update TunnelTypes.swift**

```swift
// MessageBridgeServer/Sources/MessageBridgeCore/Tunnel/TunnelTypes.swift

import Foundation

// NOTE: TunnelProvider enum has been removed.
// Use the TunnelProvider protocol from Protocols/TunnelProvider.swift instead.
// Available providers can be discovered via TunnelRegistry.shared.all

/// Status of a tunnel (shared between all provider types)
public enum TunnelStatus: Sendable, Equatable {
    /// The tunnel tool is not installed on the system
    case notInstalled
    /// Tunnel is stopped/not running
    case stopped
    /// Tunnel is starting/connecting
    case starting
    /// Tunnel is running and accessible
    case running(url: String, isQuickTunnel: Bool)
    /// An error occurred
    case error(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .notInstalled:
            return "Not Installed"
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting..."
        case .running(_, let isQuick):
            return isQuick ? "Quick Tunnel Active" : "Tunnel Active"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    public var url: String? {
        if case .running(let url, _) = self {
            return url
        }
        return nil
    }
}
```

**Step 2: Find and update any code using the old TunnelProvider enum**

Run: `cd MessageBridgeServer && grep -r "TunnelProvider\." --include="*.swift" Sources/`

For each usage found, update to use the registry or remove if unused.

**Step 3: Verify build succeeds**

Run: `cd MessageBridgeServer && swift build`
Expected: Build succeeds (may require fixing references to old enum)

**Step 4: Run tests**

Run: `cd MessageBridgeServer && swift test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Tunnel/TunnelTypes.swift
git commit -m "refactor: remove TunnelProvider enum, add notInstalled to TunnelStatus"
```

---

## Task 8: Register Providers at App Startup

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeServer/App/ServerApp.swift`

**Step 1: Add registry setup**

Find the app initialization code and add provider registration:

```swift
// In ServerApp.swift, add import at top:
import MessageBridgeCore

// In the app initialization (likely in init() or a setup method):
private func setupTunnelProviders() {
    TunnelRegistry.shared.register(TailscaleManager())
    TunnelRegistry.shared.register(CloudflaredManager())
    TunnelRegistry.shared.register(NgrokManager())
}

// Call setupTunnelProviders() during app initialization
```

**Step 2: Verify build succeeds**

Run: `cd MessageBridgeServer && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeServer/App/ServerApp.swift
git commit -m "feat: register tunnel providers at app startup"
```

---

## Task 9: Add MockTunnelProvider Tests

**Files:**
- Create: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Mocks/MockTunnelProviderTests.swift`

**Step 1: Write tests for the mock provider**

```swift
// MessageBridgeServer/Tests/MessageBridgeCoreTests/Mocks/MockTunnelProviderTests.swift

import XCTest
@testable import MessageBridgeCore

final class MockTunnelProviderTests: XCTestCase {

    func testConnectSuccess() async throws {
        let mock = MockTunnelProvider()
        mock.mockURL = "https://test.example.com"

        let url = try await mock.connect(port: 8080)

        XCTAssertEqual(url, "https://test.example.com")
        let status = await mock.status
        XCTAssertTrue(status.isRunning)
    }

    func testConnectFailure() async {
        let mock = MockTunnelProvider()
        await mock.shouldFailConnect = .timeout

        do {
            _ = try await mock.connect(port: 8080)
            XCTFail("Expected error to be thrown")
        } catch let error as TunnelError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testDisconnect() async throws {
        let mock = MockTunnelProvider()
        _ = try await mock.connect(port: 8080)

        var status = await mock.status
        XCTAssertTrue(status.isRunning)

        await mock.disconnect()

        status = await mock.status
        XCTAssertEqual(status, .stopped)
    }

    func testStatusChangeCallback() async throws {
        let mock = MockTunnelProvider()

        let expectation = XCTestExpectation(description: "Status change callback")
        var receivedStatuses: [TunnelStatus] = []

        await mock.onStatusChange { status in
            receivedStatuses.append(status)
            if case .running = status {
                expectation.fulfill()
            }
        }

        _ = try await mock.connect(port: 8080)

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertTrue(receivedStatuses.contains(.starting))
        XCTAssertTrue(receivedStatuses.contains { $0.isRunning })
    }

    func testProtocolConformance() async {
        let mock = MockTunnelProvider(
            id: "test-id",
            displayName: "Test Provider",
            description: "A test provider",
            iconName: "test.icon"
        )

        // Verify all protocol properties
        XCTAssertEqual(mock.id, "test-id")
        XCTAssertEqual(mock.displayName, "Test Provider")
        XCTAssertEqual(mock.description, "A test provider")
        XCTAssertEqual(mock.iconName, "test.icon")
        XCTAssertTrue(mock.isInstalled())

        let status = await mock.status
        XCTAssertEqual(status, .stopped)
    }
}
```

**Step 2: Run tests**

Run: `cd MessageBridgeServer && swift test --filter MockTunnelProviderTests`
Expected: All tests pass

**Step 3: Commit**

```bash
git add MessageBridgeServer/Tests/MessageBridgeCoreTests/Mocks/MockTunnelProviderTests.swift
git commit -m "test: add MockTunnelProvider tests"
```

---

## Task 10: Integration Test with Registry

**Files:**
- Create: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Integration/TunnelProviderIntegrationTests.swift`

**Step 1: Write integration tests**

```swift
// MessageBridgeServer/Tests/MessageBridgeCoreTests/Integration/TunnelProviderIntegrationTests.swift

import XCTest
@testable import MessageBridgeCore

final class TunnelProviderIntegrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TunnelRegistry.shared.reset()
    }

    override func tearDown() {
        TunnelRegistry.shared.reset()
        super.tearDown()
    }

    func testMultipleProvidersInRegistry() async throws {
        // Register multiple mock providers
        let cloudflare = MockTunnelProvider(id: "cloudflare", displayName: "Cloudflare")
        let ngrok = MockTunnelProvider(id: "ngrok", displayName: "ngrok")
        let tailscale = MockTunnelProvider(id: "tailscale", displayName: "Tailscale")

        TunnelRegistry.shared.register(cloudflare)
        TunnelRegistry.shared.register(ngrok)
        TunnelRegistry.shared.register(tailscale)

        // Verify all are registered
        XCTAssertEqual(TunnelRegistry.shared.count, 3)

        // Connect via one provider
        let cf = TunnelRegistry.shared.get("cloudflare")!
        let url = try await cf.connect(port: 8080)
        XCTAssertFalse(url.isEmpty)

        // Verify status
        let status = await cf.status
        XCTAssertTrue(status.isRunning)

        // Other providers should still be stopped
        let ngrokStatus = await TunnelRegistry.shared.get("ngrok")!.status
        XCTAssertEqual(ngrokStatus, .stopped)
    }

    func testConnectDisconnectCycle() async throws {
        let mock = MockTunnelProvider(id: "test")
        mock.mockURL = "https://tunnel.example.com"
        TunnelRegistry.shared.register(mock)

        let provider = TunnelRegistry.shared.get("test")!

        // Initial state
        var status = await provider.status
        XCTAssertEqual(status, .stopped)

        // Connect
        let url = try await provider.connect(port: 8080)
        XCTAssertEqual(url, "https://tunnel.example.com")

        status = await provider.status
        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.url, "https://tunnel.example.com")

        // Disconnect
        await provider.disconnect()

        status = await provider.status
        XCTAssertEqual(status, .stopped)
    }

    func testProviderErrorHandling() async {
        let mock = MockTunnelProvider(id: "failing")
        await mock.shouldFailConnect = .notInstalled(provider: "failing")
        TunnelRegistry.shared.register(mock)

        let provider = TunnelRegistry.shared.get("failing")!

        do {
            _ = try await provider.connect(port: 8080)
            XCTFail("Expected error")
        } catch let error as TunnelError {
            XCTAssertEqual(error, .notInstalled(provider: "failing"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

**Step 2: Run tests**

Run: `cd MessageBridgeServer && swift test --filter TunnelProviderIntegrationTests`
Expected: All tests pass

**Step 3: Commit**

```bash
git add MessageBridgeServer/Tests/MessageBridgeCoreTests/Integration/TunnelProviderIntegrationTests.swift
git commit -m "test: add tunnel provider integration tests"
```

---

## Task 11: Final Verification

**Step 1: Run full test suite**

Run: `cd MessageBridgeServer && swift test`
Expected: All tests pass

**Step 2: Build release**

Run: `cd MessageBridgeServer && swift build -c release`
Expected: Build succeeds

**Step 3: Update CLAUDE.md migration table**

Update the "Architecture Migration Status" table in CLAUDE.md:

```markdown
| **Server Tunnels**      | Separate manager classes, no common interface | `TunnelProvider` protocol + `TunnelRegistry`  | ✅ Migrated |
```

**Step 4: Final commit**

```bash
git add CLAUDE.md
git commit -m "docs: mark server tunnels as migrated in architecture table"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Create TunnelError type | 2 new |
| 2 | Create TunnelProvider protocol | 1 new |
| 3 | Create TunnelRegistry | 3 new |
| 4 | Migrate CloudflaredManager | 1 modified |
| 5 | Migrate NgrokManager | 1 modified |
| 6 | Migrate TailscaleManager | 1 modified |
| 7 | Update TunnelTypes.swift | 1 modified |
| 8 | Register providers at startup | 1 modified |
| 9 | Add MockTunnelProvider tests | 1 new |
| 10 | Add integration tests | 1 new |
| 11 | Final verification | 1 modified |

**Total: 9 new files, 5 modified files, 11 commits**
