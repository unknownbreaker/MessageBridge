# Status Indicators Improvements

**Date**: 2026-02-06
**Status**: Draft
**Scope**: Client-side UI improvements for connection status, send failures, and setup prompts

---

## Problem Statement

Three related issues with user feedback in the client:

1. **Connection status inaccuracy**: Header shows "Connected" even when WebSocket has silently disconnected
2. **Silent send failures**: Messages fail to send with no user feedback - optimistic message just disappears
3. **No setup guidance**: Missing URL or API key shows empty conversation list with no help

---

## Design

### 1. Connection Status with Auto-Reconnect

#### New Connection State Machine

```swift
public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, maxAttempts: Int)
}

extension ConnectionState {
    var text: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting(let attempt, let max): return "Reconnecting (\(attempt)/\(max))..."
        }
    }

    var color: Color {
        switch self {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        case .disconnected: return .red
        }
    }
}
```

#### Reconnection Logic

- **Trigger**: WebSocket `receive()` returns `.failure`
- **Strategy**: Exponential backoff with 3 attempts (2s, 4s, 8s delays)
- **Success**: Emit `.connected`, resume normal operation
- **Failure**: After 3 attempts, emit `.disconnected`

```swift
// In BridgeConnection
private let maxReconnectAttempts = 3
private let baseReconnectDelay: TimeInterval = 2.0

private func handleWebSocketDisconnect() async {
    for attempt in 1...maxReconnectAttempts {
        connectionStateSubject.send(.reconnecting(attempt: attempt, maxAttempts: maxReconnectAttempts))

        let delay = baseReconnectDelay * pow(2.0, Double(attempt - 1))
        try? await Task.sleep(for: .seconds(delay))

        do {
            try await reconnectWebSocket()
            connectionStateSubject.send(.connected)
            return
        } catch {
            logWarning("Reconnect attempt \(attempt) failed: \(error)")
        }
    }

    connectionStateSubject.send(.disconnected)
}
```

#### Publisher Integration

```swift
// BridgeConnection exposes:
public var connectionStatePublisher: AnyPublisher<ConnectionState, Never>

// MessagesViewModel subscribes:
bridgeService.connectionStatePublisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] state in
        self?.connectionState = state
    }
    .store(in: &cancellables)
```

---

### 2. Message Send Failure Feedback

#### Error Categories

```swift
public enum SendError: LocalizedError {
    case network(underlying: Error)
    case authentication
    case serverError(statusCode: Int)
    case appleScriptFailed(reason: String?)
    case unknown(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .network:
            return "Couldn't reach server. Check your connection."
        case .authentication:
            return "Authentication failed. Check your API key."
        case .serverError(let code):
            return "Server error (\(code)). Try again later."
        case .appleScriptFailed(let reason):
            if let reason {
                return "Messages.app couldn't send: \(reason)"
            }
            return "Messages.app couldn't send. Check the server Mac."
        case .unknown:
            return "Failed to send. Tap to retry."
        }
    }
}
```

#### Message Send Status

```swift
public enum MessageSendStatus: Equatable, Sendable {
    case sending
    case sent
    case failed(SendError)
}

// Add to Message model
public struct Message {
    // ... existing fields ...
    public var sendStatus: MessageSendStatus?
}
```

#### Error Categorization Logic

```swift
private func categorizeSendError(_ error: Error, response: HTTPURLResponse?, body: Data?) -> SendError {
    // Check for network errors
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
            return .network(underlying: urlError)
        default:
            break
        }
    }

    // Check HTTP status codes
    if let response {
        switch response.statusCode {
        case 401:
            return .authentication
        case 500...599:
            // Check if body contains AppleScript failure info
            if let body, let errorInfo = try? JSONDecoder().decode(SendErrorResponse.self, from: body) {
                if errorInfo.reason?.contains("AppleScript") == true || errorInfo.reason?.contains("Messages.app") == true {
                    return .appleScriptFailed(reason: errorInfo.reason)
                }
            }
            return .serverError(statusCode: response.statusCode)
        default:
            break
        }
    }

    return .unknown(underlying: error)
}
```

#### UI Behavior

**Failed message bubble**:
- Red exclamation icon overlaid on bubble (bottom-right for sent messages)
- Subtle red border or tint on the bubble
- Message stays visible (not removed)

**Retry popover** (shown on tap):
```swift
struct FailedMessagePopover: View {
    let error: SendError
    let onRetry: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .font(.callout)

            HStack {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
```

---

### 3. Setup Prompts

#### Configuration State

```swift
public enum ConfigurationState: Equatable {
    case complete
    case partial(missing: [String])
    case unconfigured

    public static func check(using keychainManager: KeychainManager) -> ConfigurationState {
        guard let config = try? keychainManager.retrieveServerConfig() else {
            return .unconfigured
        }

        var missing: [String] = []
        if config.serverURL.absoluteString.isEmpty {
            missing.append("Server URL")
        }
        if config.apiKey.isEmpty {
            missing.append("API Key")
        }

        if missing.isEmpty {
            return .complete
        } else {
            return .partial(missing: missing)
        }
    }
}
```

#### Setup Banner (Partial Configuration)

Appears at top of conversation list when URL or API key is missing.

```swift
struct SetupPromptBanner: View {
    let missingItems: [String]
    let onConfigure: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text("Setup incomplete: \(missingItems.joined(separator: ", ")) missing")
                .font(.callout)

            Spacer()

            Button("Configure") {
                onConfigure()
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.orange.opacity(0.3)), alignment: .bottom)
    }
}
```

#### Welcome Empty State (Unconfigured)

Replaces the detail area placeholder when nothing is configured.

```swift
struct WelcomeEmptyState: View {
    let onSetup: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue.opacity(0.8))

            Text("Welcome to MessageBridge")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect to your home Mac to access your messages")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Set Up Connection") {
                onSetup()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

#### Opening Settings Programmatically

```swift
extension NSApplication {
    func openSettings(tab: SettingsTab = .connection) {
        // Open settings window
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }

        // Post notification to select specific tab
        NotificationCenter.default.post(name: .selectSettingsTab, object: tab)
    }
}

enum SettingsTab: String {
    case connection
    case about
}

extension Notification.Name {
    static let selectSettingsTab = Notification.Name("selectSettingsTab")
}
```

---

## File Changes

| File | Changes |
|------|---------|
| `BridgeConnection.swift` | Add `connectionStatePublisher`, reconnect logic with exponential backoff, error categorization |
| `MessagesViewModel.swift` | Subscribe to connection state, add `configurationState` computed property, update send error handling |
| `ContentView.swift` | Update subtitle to use `ConnectionState`, show `WelcomeEmptyState` when unconfigured |
| `Message.swift` | Add `sendStatus: MessageSendStatus?` property |
| `MessageBubble.swift` | Show failure indicator overlay, add tap handler for retry popover |
| `ConversationListView.swift` | Add `SetupPromptBanner` when partially configured |
| **New**: `ConnectionState.swift` | `ConnectionState` enum with text/color extensions |
| **New**: `ConfigurationState.swift` | `ConfigurationState` enum with check logic |
| **New**: `SendError.swift` | `SendError` enum and `MessageSendStatus` |
| **New**: `SetupPromptBanner.swift` | Banner view component |
| **New**: `WelcomeEmptyState.swift` | Empty state view component |
| **New**: `FailedMessagePopover.swift` | Retry popover component |
| `SettingsView.swift` | Add tab selection via notification |

---

## Testing

### Unit Tests

- `ConnectionStateTests`: State transitions, text/color mappings
- `SendErrorCategorizationTests`: Verify correct error categorization for various failure modes
- `ConfigurationStateTests`: Check detection of complete/partial/unconfigured states

### Integration Tests

- Reconnection flow: Simulate WebSocket disconnect, verify retry attempts and final state
- Send failure flow: Simulate various error responses, verify UI state updates

### Manual Testing Checklist

- [ ] Disconnect server, verify "Reconnecting (1/3)..." appears
- [ ] Keep server down, verify transitions through attempts to "Disconnected"
- [ ] Restart server during reconnect, verify returns to "Connected"
- [ ] Send message with server down, verify red indicator and error popover
- [ ] Tap retry on failed message, verify it resends
- [ ] Clear API key, verify banner appears
- [ ] Clear both settings, verify welcome empty state appears
- [ ] Click "Set Up Connection", verify Settings opens to Connection tab

---

## Out of Scope

- Server-side changes (error response format is already sufficient)
- Notification when reconnected (could add later)
- Offline queue for failed messages (could add later)
- Multiple connection profiles (future feature)
