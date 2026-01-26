# TunnelProvider Protocol Migration Design

**Date:** 2026-01-26
**Status:** Approved
**Goal:** Unify tunnel managers (Tailscale, Cloudflare, ngrok) behind a common protocol for UI consistency, extensibility, and testability.

---

## Problem

The current codebase has three separate tunnel manager classes:

- `TailscaleManager` (296 lines) — reads status from external Tailscale app
- `CloudflaredManager` (429 lines) — manages cloudflared child process
- `NgrokManager` (504 lines) — manages ngrok child process

Each has a different interface, making UI code complex and adding new tunnel types difficult.

## Design Goals

1. **Unified UI** — One settings view that works with any tunnel
2. **Extensibility** — Add new tunnels (ZeroTier, Wireguard) by implementing one protocol
3. **Testability** — Mock tunnels for testing without network dependencies

## Approach

**Unified Protocol with Semantic Methods**

Single protocol where `connect()` means "ensure tunnel is available" — implementation details vary:
- Tailscale: verifies VPN connection, returns IP
- Cloudflare/ngrok: spawns process, returns public URL

---

## Core Protocol

```swift
// Sources/MessageBridgeCore/Protocols/TunnelProvider.swift

import Foundation

public protocol TunnelProvider: Actor, Identifiable, Sendable {
    /// Unique identifier (e.g., "tailscale", "cloudflare", "ngrok")
    var id: String { get }

    /// Human-readable name for UI
    var displayName: String { get }

    /// Short description
    var description: String { get }

    /// SF Symbol name for icon
    var iconName: String { get }

    /// Current tunnel status
    var status: TunnelStatus { get async }

    /// Whether the underlying tool is installed
    func isInstalled() -> Bool

    /// Connect/activate the tunnel. Returns public URL when successful.
    func connect(port: Int) async throws -> String

    /// Disconnect/deactivate the tunnel.
    func disconnect() async

    /// Register callback for status changes
    func onStatusChange(_ handler: @escaping (TunnelStatus) -> Void)
}
```

---

## Registry

```swift
// Sources/MessageBridgeCore/Registries/TunnelRegistry.swift

import Foundation

public final class TunnelRegistry: @unchecked Sendable {
    public static let shared = TunnelRegistry()

    private var providers: [String: any TunnelProvider] = [:]
    private let lock = NSLock()

    private init() {}

    public func register(_ provider: any TunnelProvider) {
        lock.lock()
        defer { lock.unlock() }
        providers[provider.id] = provider
    }

    public func get(_ id: String) -> (any TunnelProvider)? {
        lock.lock()
        defer { lock.unlock() }
        return providers[id]
    }

    public var all: [any TunnelProvider] {
        lock.lock()
        defer { lock.unlock() }
        return Array(providers.values)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        providers.removeAll()
    }
}
```

---

## Unified Error Type

```swift
// Sources/MessageBridgeCore/Tunnels/TunnelError.swift

import Foundation

public enum TunnelError: LocalizedError, Sendable {
    case notInstalled(provider: String)
    case installationFailed(reason: String)
    case connectionFailed(String)
    case unexpectedTermination(exitCode: Int32)
    case timeout
    case userActionRequired(String)
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

---

## Provider Adaptations

### CloudflareProvider

```swift
public actor CloudflareProvider: TunnelProvider {
    public let id = "cloudflare"
    public let displayName = "Cloudflare Tunnel"
    public let description = "Free, no account required. May be blocked by some corporate firewalls."
    public let iconName = "cloud"

    public var status: TunnelStatus { get async { _status } }

    public func connect(port: Int) async throws -> String {
        // Existing startQuickTunnel logic
    }

    public func disconnect() async {
        // Existing stopTunnel logic
    }

    // ... rest of existing implementation unchanged
}
```

### NgrokProvider

Same pattern as CloudflareProvider — rename methods, add protocol conformance.

### TailscaleProvider

```swift
public actor TailscaleProvider: TunnelProvider {
    public let id = "tailscale"
    public let displayName = "Tailscale"
    public let description = "VPN mesh network. Requires Tailscale app installed."
    public let iconName = "network"

    public func connect(port: Int) async throws -> String {
        let status = await getStatus(forceRefresh: true)
        switch status {
        case .connected(let ip, _):
            return ip
        case .notInstalled:
            throw TunnelError.notInstalled(provider: id)
        case .stopped, .connecting:
            openTailscaleApp()
            throw TunnelError.userActionRequired("Please connect in Tailscale app")
        case .error(let msg):
            throw TunnelError.connectionFailed(msg)
        }
    }

    public func disconnect() async {
        // No-op — Tailscale managed externally
    }
}
```

---

## UI Consumption

```swift
// Sources/MessageBridgeServer/Views/TunnelSettingsView.swift

struct TunnelSettingsView: View {
    @State private var providers: [any TunnelProvider] = []
    @State private var selectedProviderId: String?
    @State private var statuses: [String: TunnelStatus] = [:]

    var body: some View {
        Form {
            Section("Tunnel Provider") {
                Picker("Provider", selection: $selectedProviderId) {
                    ForEach(providers, id: \.id) { provider in
                        Label(provider.displayName, systemImage: provider.iconName)
                            .tag(provider.id as String?)
                    }
                }
            }

            if let id = selectedProviderId,
               let provider = TunnelRegistry.shared.get(id) {
                TunnelControlSection(provider: provider, status: statuses[id] ?? .stopped)
            }
        }
        .task {
            providers = TunnelRegistry.shared.all
            await refreshStatuses()
        }
    }
}

struct TunnelControlSection: View {
    let provider: any TunnelProvider
    let status: TunnelStatus

    var body: some View {
        Section {
            LabeledContent("Status", value: status.displayText)

            if let url = status.url {
                LabeledContent("URL") {
                    Text(url).textSelection(.enabled)
                }
            }

            HStack {
                if status.isRunning {
                    Button("Disconnect") {
                        Task { await provider.disconnect() }
                    }
                } else if case .starting = status {
                    ProgressView().controlSize(.small)
                    Text("Connecting...")
                } else {
                    Button("Connect") {
                        Task { try? await provider.connect(port: 8080) }
                    }
                    .disabled(!provider.isInstalled())
                }
            }
        } header: {
            Text(provider.displayName)
        } footer: {
            Text(provider.description)
        }
    }
}
```

---

## Mock for Testing

```swift
// Tests/MessageBridgeCoreTests/Mocks/MockTunnelProvider.swift

public actor MockTunnelProvider: TunnelProvider {
    public let id: String
    public let displayName: String
    public let description = "Mock tunnel for testing"
    public let iconName = "testtube.2"

    private var _status: TunnelStatus = .stopped
    private var _isInstalled: Bool
    private var statusHandler: ((TunnelStatus) -> Void)?

    public var connectDelay: Duration = .zero
    public var shouldFailConnect: TunnelError?
    public var mockURL: String = "https://mock-tunnel.example.com"

    public init(id: String = "mock", displayName: String = "Mock", isInstalled: Bool = true) {
        self.id = id
        self.displayName = displayName
        self._isInstalled = isInstalled
    }

    public var status: TunnelStatus { get async { _status } }

    public func isInstalled() -> Bool { _isInstalled }

    public func connect(port: Int) async throws -> String {
        if let error = shouldFailConnect { throw error }
        updateStatus(.starting)
        if connectDelay > .zero { try await Task.sleep(for: connectDelay) }
        updateStatus(.running(url: mockURL, isQuickTunnel: true))
        return mockURL
    }

    public func disconnect() async { updateStatus(.stopped) }

    public func onStatusChange(_ handler: @escaping (TunnelStatus) -> Void) {
        statusHandler = handler
    }

    private func updateStatus(_ newStatus: TunnelStatus) {
        _status = newStatus
        statusHandler?(newStatus)
    }

    public func setInstalled(_ installed: Bool) { _isInstalled = installed }
    public func simulateError(_ message: String) { updateStatus(.error(message)) }
}
```

---

## File Structure

**New files:**

```
MessageBridgeServer/Sources/MessageBridgeCore/
├── Protocols/
│   └── TunnelProvider.swift
├── Registries/
│   └── TunnelRegistry.swift
└── Tunnels/
    └── TunnelError.swift
```

**Files to modify:**

| File | Change |
|------|--------|
| `Tailscale/TailscaleManager.swift` | Rename to `TailscaleProvider.swift`, add protocol conformance |
| `Cloudflare/CloudflaredManager.swift` | Rename to `CloudflareProvider.swift`, add protocol conformance |
| `Ngrok/NgrokManager.swift` | Rename to `NgrokProvider.swift`, add protocol conformance |
| `Tunnel/TunnelTypes.swift` | Remove `TunnelProvider` enum, keep `TunnelStatus` |
| `App/ServerApp.swift` | Add registry setup at startup |
| `Views/TunnelSettingsView.swift` | Update to use registry |

---

## Migration Steps

1. Create `Protocols/` directory and `TunnelProvider.swift`
2. Create `Registries/` directory and `TunnelRegistry.swift`
3. Create `TunnelError.swift`
4. Update `TailscaleManager` → `TailscaleProvider` with protocol conformance
5. Update `CloudflaredManager` → `CloudflareProvider` with protocol conformance
6. Update `NgrokManager` → `NgrokProvider` with protocol conformance
7. Update `TunnelTypes.swift` — remove enum, keep `TunnelStatus`
8. Add registry setup in `ServerApp.swift`
9. Update settings views to use registry
10. Add `MockTunnelProvider` and tests

---

## Future Extensions

Adding a new tunnel provider (e.g., ZeroTier):

1. Create `Tunnels/ZeroTier/ZeroTierProvider.swift` implementing `TunnelProvider`
2. Register in `ServerApp.swift`: `TunnelRegistry.shared.register(ZeroTierProvider())`
3. Done — UI automatically picks it up
