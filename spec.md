# iMessage Bridge - Project Specification

## Project Overview

A self-hosted system for accessing iMessages/SMS on a work Mac (without iCloud) by relaying through a home Mac (with iCloud). Native Swift/SwiftUI implementation with no third-party message services.

---

## Coding Guidelines

### General Principles
- **Avoid deeply nested logic** - Extract nested conditions into early returns or separate functions. Prefer guard statements over nested if-else.
- **No global variables** - Functions should only receive data through arguments passed into them. Use dependency injection.
- **Immutability** - Avoid mutating variables passed into a function. Return new values instead of modifying inputs.
- **Modular design** - Features should be self-contained and swappable without causing cascading changes elsewhere. Use protocols to define boundaries.
- **Thorough testing** - Create tests for each feature covering success cases, edge cases, and error conditions.

### Swift Conventions
- Use `actor` for thread-safe classes (e.g., `ChatDatabase`, `BridgeConnection`)
- Use `@MainActor` for ViewModels that update UI state
- Prefer `async/await` over callbacks
- Models should be `Codable`, `Identifiable`, and `Sendable` where applicable

### Testing Workflow (TDD)
- **Write tests first** - Always write failing tests before implementing features. Tests act as user stories that define expected behavior.
- **Tests as specifications** - Each test describes a specific behavior (e.g., `testConnect_success_setsStatusToConnected`).
- **Cover all cases** - Write tests for success cases, edge cases, and error conditions before implementing.
- **Implement to pass** - Write the minimum code necessary to make all tests pass.
- Use protocol-based dependency injection for testability
- Mock external dependencies (network, database) in tests

---

## Milestone 1: Project Setup & Database Reading ✅

**Goal:** Establish project structure and prove we can read from the Messages database.

### Deliverables
- [x] Create `MessageBridgeServer` Swift Package with Vapor
- [x] Create `MessageBridgeClient` Swift Package with SwiftUI
- [x] Define shared data models (`Message`, `Conversation`, `Handle`)
- [x] Implement `ChatDatabase.swift` to query `chat.db`
- [x] CLI tool that prints recent conversations and messages
- [x] Add test targets with unit tests (17 server tests, 4 client tests)

### Success Criteria
```bash
# Running on home Mac:
swift run MessageBridgeServer --test-db
# Output: Lists 10 most recent conversations with last message preview

# Run tests:
cd MessageBridgeServer && swift test  # 17 tests pass
cd MessageBridgeClient && swift test  # 4 tests pass
```

### Key Technical Decisions
- Use Vapor for HTTP/WebSocket server
- Use GRDB for database access
- Full Disk Access permission required
- Separate Core libraries for testability

---

## Milestone 2: REST API ✅

**Goal:** Expose message data via HTTP endpoints.

### Deliverables
- [x] `GET /health` - Server status check
- [x] `GET /conversations` - List all conversations (paginated)
- [x] `GET /conversations/:id/messages` - Messages for a conversation (paginated)
- [x] `GET /search?q=` - Search messages by content
- [x] API key authentication middleware
- [x] Unit tests for all endpoints (12 API tests)

### Success Criteria
```bash
curl -H "X-API-Key: $KEY" http://localhost:8080/conversations
# Returns JSON array of conversations

curl -H "X-API-Key: $KEY" http://localhost:8080/conversations/123/messages
# Returns JSON array of messages
```

### API Response Formats
```json
// GET /conversations
{
  "conversations": [
    {
      "id": "chat123",
      "participants": ["+15551234567"],
      "displayName": "John Doe",
      "lastMessage": "See you tomorrow!",
      "lastMessageDate": "2026-01-08T10:30:00Z",
      "unreadCount": 2
    }
  ],
  "nextCursor": "abc123"
}
```

---

## Milestone 3: Message Sending ✅

**Goal:** Send messages via AppleScript integration.

### Deliverables
- [x] `MessageSender.swift` - AppleScript bridge (use protocol for testability)
- [x] `POST /send` endpoint
- [x] Handle iMessage vs SMS routing (via `service` parameter)
- [x] Return delivery status
- [x] Unit tests with mock AppleScript executor (7 tests)

### Success Criteria
```bash
curl -X POST -H "X-API-Key: $KEY" \
  -d '{"to": "+15551234567", "text": "Hello from API"}' \
  http://localhost:8080/send
# Message appears in Messages.app and is sent to recipient
```

### AppleScript Integration
```swift
protocol MessageSending {
    func sendMessage(to recipient: String, text: String) async throws
}

actor AppleScriptMessageSender: MessageSending {
    func sendMessage(to recipient: String, text: String) async throws {
        let script = """
        tell application "Messages"
            set targetService to 1st account whose service type = iMessage
            set targetBuddy to participant "\(recipient)" of targetService
            send "\(text)" to targetBuddy
        end tell
        """
        // Execute via NSAppleScript
    }
}
```

---

## Milestone 4: Real-Time Updates ✅

**Goal:** Push new messages to connected clients via WebSocket.

### Deliverables
- [x] `FileWatcher.swift` - FSEvents monitor for chat.db changes (use protocol)
- [x] WebSocket endpoint at `/ws`
- [x] Push new messages to all connected clients
- [x] Handle reconnection gracefully
- [x] Unit tests with mock file watcher (7 tests)

### Success Criteria
1. Client connects to WebSocket
2. New message arrives on iPhone
3. Syncs to home Mac Messages
4. Server detects change in chat.db
5. Pushes new message to client within 2 seconds

### WebSocket Message Format
```json
// Server -> Client
{
  "type": "new_message",
  "data": {
    "id": "msg456",
    "conversationId": "chat123",
    "text": "Hey there!",
    "sender": "+15551234567",
    "date": "2026-01-08T10:35:00Z",
    "isFromMe": false
  }
}
```

---

## Milestone 5: macOS Client - Core UI

**Goal:** Build the native SwiftUI client with conversation list and message display.

### Deliverables
- [x] `ContentView.swift` - NavigationSplitView layout
- [x] `ConversationListView.swift` - Sidebar with conversations
- [x] `MessageThreadView.swift` - Message bubbles display
- [x] `BridgeConnection.swift` - REST + WebSocket client (with protocol)
- [x] Connection status indicator in toolbar
- [x] `MessagesViewModel` with dependency injection
- [x] Unit tests for ViewModel

### Success Criteria
- App launches and connects to server
- Displays conversation list in sidebar
- Selecting a conversation shows messages
- Messages styled like native Messages.app (blue/gray bubbles)

### UI Components
```
┌────────────────────────────────────────────────────────┐
│ ● ● ●                  Message Bridge                  │
├──────────────┬─────────────────────────────────────────┤
│ Search...    │  John Doe                    ● Connected│
├──────────────┼─────────────────────────────────────────┤
│              │                                         │
│ John Doe     │         Hey, how are you?              │
│ See you tom… │                     ┌─────────────────┐ │
│              │                     │ I'm good! You?  │ │
│ Jane Smith   │                     └─────────────────┘ │
│ Got it, th…  │                                         │
│              │         See you tomorrow!               │
│ Work Chat    │                                         │
│ Meeting at…  │                                         │
│              ├─────────────────────────────────────────┤
│              │ ┌─────────────────────────────────┐ ▲  │
│              │ │ Type a message...               │    │
│              │ └─────────────────────────────────┘    │
└──────────────┴─────────────────────────────────────────┘
```

---

## Milestone 6: macOS Client - Compose & Send ✅

**Goal:** Add message composition and sending capability.

### Deliverables
- [x] `ComposeView.swift` - Message input with send button
- [x] Send message via REST API
- [x] Optimistic UI update (show message immediately)
- [x] Handle send failures gracefully
- [x] Keyboard shortcut: Enter to send, Option+Enter for newline

### Success Criteria
- Type message in compose field
- Press Enter or click Send
- Message appears in thread immediately (pending state)
- Message sends successfully
- Recipient receives the message

---

## Milestone 7: Notifications & Polish ✅

**Goal:** Native notifications and UX polish.

### Deliverables
- [x] `NotificationManager.swift` - UserNotifications integration (with protocol)
- [x] Show notification for new messages (when app not focused)
- [x] Click notification to open conversation
- [x] Keyboard shortcuts (Cmd+N new message, Cmd+F search)
- [x] Dark mode support (inherent in SwiftUI with system colors)
- [x] App icon (placeholder - requires design assets)

### Success Criteria
- New message arrives while app in background
- Native macOS notification appears
- Clicking notification opens the conversation
- All keyboard shortcuts functional

---

## Milestone 8: Deployment & Security ✅

**Goal:** Production-ready deployment with proper security.

### Deliverables
- [x] LaunchAgent plist for server auto-start
- [x] Keychain storage for API key
- [x] Tailscale setup documentation
- [x] Server installer script
- [x] Client DMG packaging

### Success Criteria
- Server starts automatically on home Mac login
- API key securely stored in Keychain
- Both Macs connected via Tailscale
- Client connects reliably to server
- Full end-to-end message flow works

### LaunchAgent
```xml
<!-- ~/Library/LaunchAgents/com.messagebridge.server.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.messagebridge.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/MessageBridgeServer</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

---

## Milestone 9: Logging & Debugging ✅

**Goal:** Comprehensive logging system for easier debugging and troubleshooting.

### Deliverables
- [x] `Logger.swift` - Core logging infrastructure with log levels
- [x] `LogEntry` struct with source location (file, function, line)
- [x] `LogManager` actor for persistent log storage
- [x] `LogViewerView` - UI for viewing and filtering logs
- [x] Automatic log cleanup (7 day retention)
- [x] Update all error handling to use logger
- [x] Unit tests for logging (12 tests)

### Success Criteria
- All errors logged with source location for easy debugging
- Logs accessible via `Cmd+Shift+L` or app menu
- Logs persist across app restarts
- Old logs automatically cleaned up

### Log Levels
```swift
logDebug("...")    // Development details
logInfo("...")     // Notable events
logWarning("...")  // Non-critical issues
logError("...", error: error)  // Failures
```

### Log Storage
- Location: `~/Library/Application Support/MessageBridge/Logs/`
- `messagebridge.log` - Human-readable format
- `messagebridge-logs.json` - Structured JSON format

---

## Milestone 10: Conventional Commits & Versioning ✅

**Goal:** Establish versioning infrastructure and commit standards.

### Deliverables
- [x] Define conventional commit standard (feat, fix, chore, docs, refactor)
- [x] Add `Version.swift` for programmatic version access
- [x] Create `CHANGELOG.md` with initial release notes
- [x] Create `CONTRIBUTING.md` with commit conventions
- [ ] Add commit message validation (optional: commitlint)

### Conventional Commit Format
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat:` - New feature (bumps minor version)
- `fix:` - Bug fix (bumps patch version)
- `docs:` - Documentation only
- `chore:` - Maintenance tasks
- `refactor:` - Code refactoring
- `test:` - Adding tests
- `BREAKING CHANGE:` - In footer, bumps major version

### Success Criteria
- All commits follow conventional format
- Version can be read programmatically in both apps
- CHANGELOG documents all releases

---

## Milestone 11: Server App Conversion ✅

**Goal:** Transform server from CLI daemon to macOS menu bar application.

### Deliverables
- [x] Create SwiftUI menu bar application structure
- [x] Server status indicator in menu bar (running/stopped/error)
- [x] Start/stop server controls
- [x] API key display with copy button
- [x] API key regeneration
- [x] Server log viewer
- [x] Login Items support (auto-start on login)
- [x] Package as `.app` bundle for /Applications
- [ ] Update installer script for app bundle

### UI Design
```
┌─────────────────────────────┐
│ 🟢 MessageBridge Server     │
├─────────────────────────────┤
│ Status: Running             │
│ Port: 8080                  │
│ Tailscale IP: 100.x.x.x     │
├─────────────────────────────┤
│ ○ Start Server              │
│ ● Stop Server               │
├─────────────────────────────┤
│ API Key: ●●●●●●●● [Copy]    │
│ Regenerate API Key...       │
├─────────────────────────────┤
│ View Logs...                │
│ Tailscale Settings...       │
├─────────────────────────────┤
│ Start at Login  ☑           │
│ Quit                        │
└─────────────────────────────┘
```

### Success Criteria
- Server runs as menu bar app from /Applications
- Can start/stop server from menu
- API key easily accessible
- Auto-starts on login when enabled

---

## Milestone 12: Tailscale Integration ✅

**Goal:** Built-in Tailscale management in both apps.

### Deliverables
- [x] `TailscaleManager.swift` - Interface with `tailscale` CLI
- [x] Detect if Tailscale is installed
- [x] Get connection status (connected/disconnected/not installed)
- [x] Get device's Tailscale IP address
- [x] Server app: Tailscale status in menu bar dropdown
- [x] Client app: Tailscale status in connection settings
- [x] Setup guidance for first-time users
- [x] Deep link to Tailscale download if not installed

### TailscaleManager Interface
```swift
public actor TailscaleManager {
    /// Check if Tailscale CLI is available
    func isInstalled() async -> Bool

    /// Get current connection status
    func getStatus() async -> TailscaleStatus

    /// Get this device's Tailscale IP
    func getIPAddress() async -> String?

    /// Get list of devices on tailnet
    func getDevices() async throws -> [TailscaleDevice]
}

public enum TailscaleStatus {
    case notInstalled
    case stopped
    case connecting
    case connected(ip: String)
    case error(String)
}
```

### Success Criteria
- Both apps show Tailscale connection status
- Users guided through Tailscale setup
- Clear indication when Tailscale is not configured

---

## Milestone 13: GitHub Actions & Release Automation ✅

**Goal:** Automated builds, testing, and releases.

### Deliverables
- [x] `.github/workflows/ci.yml` - Build and test on every PR
- [x] `.github/workflows/release.yml` - Build and release on version tags
- [x] Auto-generate changelog from conventional commits
- [x] Build both apps as `.app` bundles
- [x] Create DMG installers for both apps
- [x] Upload DMGs to GitHub Releases
- [x] Version extraction from git tags
- [ ] (Optional) Code signing with Developer ID
- [ ] (Optional) Notarization for Gatekeeper

### CI Workflow (ci.yml)
```yaml
name: CI
on: [push, pull_request]
jobs:
  build-and-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build Server
        run: cd MessageBridgeServer && swift build
      - name: Test Server
        run: cd MessageBridgeServer && swift test
      - name: Build Client
        run: cd MessageBridgeClient && swift build
      - name: Test Client
        run: cd MessageBridgeClient && swift test
```

### Release Workflow (release.yml)
```yaml
name: Release
on:
  push:
    tags: ['v*']
jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Build Apps
        run: ./Scripts/build-release.sh
      - name: Create DMGs
        run: ./Scripts/create-dmgs.sh
      - name: Generate Changelog
        run: ./Scripts/generate-changelog.sh
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            build/*.dmg
          body_path: RELEASE_NOTES.md
```

### Success Criteria
- PRs automatically built and tested
- Pushing `v*` tag creates GitHub Release
- Release includes both DMGs and changelog
- Version number embedded in apps matches tag

---

## Milestone 14: E2E Encryption & Cloudflare Tunnel ✅

**Goal:** Add end-to-end encryption and alternative network connectivity via Cloudflare Tunnel.

### Deliverables
- [x] `E2EEncryption.swift` - AES-256-GCM encryption with HKDF key derivation
- [x] `E2EMiddleware.swift` - Vapor middleware for automatic response encryption
- [x] `EncryptedEnvelope` - JSON wrapper for encrypted payloads
- [x] Server: Encrypt responses when `X-E2E-Encryption: enabled` header present
- [x] Server: Decrypt incoming request bodies for `/send` endpoint
- [x] Server: WebSocket encryption support per connection
- [x] Client: E2E toggle in Settings UI
- [x] Client: Encrypt/decrypt all API traffic when enabled
- [x] Client: Handle encrypted WebSocket messages
- [x] Cloudflare Tunnel setup guide (`Scripts/setup-cloudflare-tunnel.md`)
- [x] Unit tests for encryption (11 server tests, 9 client tests)

### E2E Encryption Design
```swift
public struct E2EEncryption {
    private let key: SymmetricKey  // Derived from API key via HKDF

    public func encrypt(_ data: Data) throws -> String  // Base64 ciphertext
    public func decrypt(_ base64: String) throws -> Data
}

public struct EncryptedEnvelope: Codable {
    let version: Int      // Protocol version (currently 1)
    let payload: String   // Base64-encoded AES-GCM ciphertext
}
```

### Key Derivation
- Input: API key (shared secret)
- Salt: `"MessageBridge-E2E-Salt-v1"`
- Info: `"MessageBridge-E2E-Encryption"`
- Output: 256-bit AES key via HKDF-SHA256

### Success Criteria
- Messages encrypted before leaving device
- Relay servers (Cloudflare) cannot read content
- Same API key decrypts on both ends
- Works with both Tailscale and Cloudflare Tunnel

---

## Milestone 15: Cloudflare Tunnel Setup Wizard ✅

**Goal:** Simplify Cloudflare Tunnel setup with a guided wizard in the server app, eliminating manual terminal commands.

### Problem Statement
Current Cloudflare Tunnel setup requires:
1. Installing `cloudflared` via Homebrew (terminal)
2. Running `cloudflared tunnel login` (opens browser)
3. Creating a tunnel via CLI
4. Creating a config file manually
5. Setting up a LaunchAgent manually
6. Running the tunnel

This is too complex for non-technical users and error-prone.

### Deliverables (Quick Tunnel - Phase 1)
- [x] Detect if `cloudflared` is installed
- [x] One-click `cloudflared` installation (download binary directly, no Homebrew required)
- [x] Start/stop tunnel from server UI
- [x] Tunnel status indicator in menu bar
- [x] Quick tunnel mode (temporary URL, no account needed)
- [x] Cloudflare settings tab in server preferences
- [x] CloudflaredManager actor with process management
- [x] Unit tests for CloudflaredManager (18 tests)

### Future Enhancements (Named Tunnel - Phase 2)
- [ ] OAuth flow integration for Cloudflare login
- [ ] Automatic tunnel creation and configuration
- [ ] Generate and manage config.yml automatically
- [ ] LaunchAgent creation for auto-start
- [ ] Named tunnel mode (permanent URL, requires Cloudflare account)

### UI Design
```
┌─────────────────────────────────────────┐
│ Cloudflare Tunnel Setup                 │
├─────────────────────────────────────────┤
│                                         │
│  ○ Quick Tunnel (Temporary URL)         │
│    No account needed. URL changes on    │
│    each restart.                        │
│                                         │
│  ○ Named Tunnel (Permanent URL)         │
│    Requires free Cloudflare account.    │
│    URL stays the same forever.          │
│                                         │
├─────────────────────────────────────────┤
│              [Continue →]               │
└─────────────────────────────────────────┘

// Quick Tunnel flow:
┌─────────────────────────────────────────┐
│ Quick Tunnel Active                     │
├─────────────────────────────────────────┤
│                                         │
│  Your tunnel URL:                       │
│  ┌─────────────────────────────────┐    │
│  │ https://abc-xyz.trycloudflare.com │  │
│  └─────────────────────────────────┘    │
│                        [Copy URL]       │
│                                         │
│  Status: ● Connected                    │
│                                         │
│  ⚠️ This URL will change when you       │
│     restart the tunnel.                 │
│                                         │
├─────────────────────────────────────────┤
│  [Stop Tunnel]    [Switch to Named →]   │
└─────────────────────────────────────────┘

// Named Tunnel flow:
┌─────────────────────────────────────────┐
│ Connect Cloudflare Account              │
├─────────────────────────────────────────┤
│                                         │
│  Click below to authorize MessageBridge │
│  to create tunnels on your account.     │
│                                         │
│         [Connect Cloudflare →]          │
│                                         │
│  This will open your browser.           │
│                                         │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Named Tunnel Active                     │
├─────────────────────────────────────────┤
│                                         │
│  Your permanent tunnel URL:             │
│  ┌─────────────────────────────────┐    │
│  │ https://messagebridge.domain.com │   │
│  └─────────────────────────────────┘    │
│                        [Copy URL]       │
│                                         │
│  Status: ● Connected                    │
│  Tunnel: messagebridge-xxxxx            │
│                                         │
│  ☑ Start tunnel automatically           │
│                                         │
├─────────────────────────────────────────┤
│  [Stop Tunnel]         [Disconnect]     │
└─────────────────────────────────────────┘
```

### CloudflaredManager Interface
```swift
public actor CloudflaredManager {
    /// Check if cloudflared binary exists
    func isInstalled() async -> Bool

    /// Download and install cloudflared binary
    func install() async throws

    /// Start a quick tunnel (temporary URL)
    func startQuickTunnel(port: Int) async throws -> String  // Returns URL

    /// Stop the running tunnel
    func stopTunnel() async throws

    /// Get current tunnel status
    func getStatus() async -> TunnelStatus

    /// Login to Cloudflare (opens browser)
    func login() async throws

    /// Create a named tunnel
    func createNamedTunnel(name: String) async throws -> TunnelInfo

    /// Configure DNS for named tunnel
    func configureDNS(tunnelId: String, hostname: String) async throws

    /// Start named tunnel
    func startNamedTunnel(name: String, port: Int) async throws

    /// Create LaunchAgent for auto-start
    func enableAutoStart() async throws

    /// Remove LaunchAgent
    func disableAutoStart() async throws
}

public enum TunnelStatus {
    case notInstalled
    case stopped
    case starting
    case running(url: String, isQuickTunnel: Bool)
    case error(String)
}
```

### Implementation Notes
1. **Binary Installation**: Download `cloudflared` directly from GitHub releases, no Homebrew dependency
2. **Quick Tunnel**: Uses `cloudflared tunnel --url` which requires no authentication
3. **Named Tunnel**: Requires OAuth flow via `cloudflared tunnel login`
4. **Process Management**: Use `Process` to spawn and manage `cloudflared` subprocess
5. **URL Detection**: Parse stdout from cloudflared to extract the assigned URL
6. **Config Storage**: Store tunnel config in `~/Library/Application Support/MessageBridge/`

### Success Criteria
- User can set up Cloudflare Tunnel without using Terminal
- Quick tunnel works with single click
- Named tunnel setup takes < 2 minutes
- Tunnel auto-starts with server when enabled
- Clear status indication in menu bar

---

## Future Enhancements (Out of Scope)

These are not part of the current implementation:

- [ ] Attachment support (images, files)
- [ ] Group chat management
- [ ] Reactions/tapbacks
- [ ] Read receipts
- [ ] Contact photo sync
- [ ] Multiple client support
- [ ] Message encryption at rest
- [ ] Code signing and notarization (requires Apple Developer account)

---

## Technical Stack

| Component | Technology |
|-----------|------------|
| Server Runtime | Swift 5.9+ |
| Server Framework | Vapor 4 |
| Server UI | SwiftUI Menu Bar App |
| Database Access | GRDB |
| Client UI | SwiftUI (macOS 13+) |
| Networking | URLSession + WebSocket |
| Security | Keychain, AES-256-GCM, HKDF |
| Network Options | Tailscale VPN, Cloudflare Tunnel |
| Testing | XCTest, Protocol Mocks |
| CI/CD | GitHub Actions |
| Versioning | Semantic Versioning |
| Commits | Conventional Commits |

---

## File Structure

```
MessageBridge/
├── CLAUDE.md                    # Claude Code guidance
├── spec.md                      # This file
├── CHANGELOG.md                 # Release history
├── CONTRIBUTING.md              # Contribution guidelines
├── VERSION                      # Current version (semver)
│
├── .github/
│   └── workflows/
│       ├── ci.yml               # Build & test on PR
│       └── release.yml          # Build & release on tag
│
├── MessageBridgeServer/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MessageBridgeCore/   # Testable library
│   │   │   ├── Models/
│   │   │   │   ├── Handle.swift
│   │   │   │   ├── Message.swift
│   │   │   │   └── Conversation.swift
│   │   │   ├── Database/
│   │   │   │   └── ChatDatabase.swift
│   │   │   ├── API/
│   │   │   │   ├── Routes.swift
│   │   │   │   ├── E2EMiddleware.swift
│   │   │   │   └── WebSocketManager.swift
│   │   │   ├── Security/
│   │   │   │   └── E2EEncryption.swift
│   │   │   ├── Tailscale/
│   │   │   │   └── TailscaleManager.swift
│   │   │   └── Version/
│   │   │       └── Version.swift
│   │   └── MessageBridgeServer/ # Menu Bar App (SwiftUI)
│   │       ├── App/
│   │       │   └── ServerApp.swift
│   │       └── Views/
│   │           ├── MenuBarView.swift
│   │           ├── StatusMenuView.swift
│   │           ├── TailscaleSettingsView.swift
│   │           └── LogViewerView.swift
│   └── Tests/
│       └── MessageBridgeCoreTests/
│
├── MessageBridgeClient/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MessageBridgeClientCore/  # Testable library
│   │   │   ├── Models/
│   │   │   │   └── Models.swift
│   │   │   ├── Services/
│   │   │   │   ├── BridgeConnection.swift
│   │   │   │   └── TailscaleManager.swift
│   │   │   ├── ViewModels/
│   │   │   │   └── MessagesViewModel.swift
│   │   │   ├── Security/
│   │   │   │   ├── KeychainManager.swift
│   │   │   │   └── E2EEncryption.swift
│   │   │   ├── Logging/
│   │   │   │   └── Logger.swift
│   │   │   └── Version/
│   │   │       └── Version.swift
│   │   └── MessageBridgeClient/      # Executable (SwiftUI)
│   │       ├── App/
│   │       │   └── MessageBridgeApp.swift
│   │       └── Views/
│   │           ├── ContentView.swift
│   │           ├── ConversationListView.swift
│   │           ├── MessageThreadView.swift
│   │           ├── LogViewerView.swift
│   │           └── TailscaleStatusView.swift
│   └── Tests/
│       └── MessageBridgeClientCoreTests/
│
└── Scripts/
    ├── build-release.sh         # Build both apps for release
    ├── create-dmgs.sh           # Package apps into DMGs
    ├── generate-changelog.sh    # Generate changelog from commits
    ├── install-server.sh        # Server installer (legacy)
    ├── package-client.sh        # Client packager (legacy)
    ├── setup-tailscale.md       # Tailscale network setup guide
    └── setup-cloudflare-tunnel.md  # Cloudflare Tunnel setup guide
```
