# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Important:** When making changes that affect how users interact with the app (UI, keyboard shortcuts, configuration, installation, etc.), update the User Guide section of this document accordingly.

## Project Overview

iMessage Bridge is a self-hosted system for accessing iMessages/SMS on a work Mac (without iCloud) by relaying through a home Mac (with iCloud). Two components:

- **MessageBridgeServer** - Swift/Vapor daemon running on home Mac, reads from Messages database, exposes REST/WebSocket API
- **MessageBridgeClient** - SwiftUI macOS app running on work Mac, connects to server

**Connection Options:**
- **Tailscale** (recommended) - Zero-config VPN, encrypted tunnel, no port forwarding
- **Cloudflare Tunnel** - Works when Tailscale isn't available (e.g., corporate restrictions)

**Security:** End-to-end encryption ensures message content is protected even when using relay services like Cloudflare Tunnel.

## Build Commands

### Server (Swift Package)
```bash
cd MessageBridgeServer
swift build                           # Build debug
swift build -c release                # Build release
swift run MessageBridgeServer         # Run server
swift run MessageBridgeServer --test-db  # Test database connectivity
swift test                            # Run tests (72 tests)
```

### Client (Swift Package)
```bash
cd MessageBridgeClient
swift build                           # Build debug
swift build -c release                # Build release
swift run MessageBridgeClient         # Run client
swift test                            # Run tests (28 tests)
```

### Deployment Scripts
```bash
cd Scripts
./install-server.sh                   # Install server on home Mac
./package-client.sh [version]         # Create client DMG
```

---

## User Guide

### Installation

#### Server (Home Mac)

1. **Grant Full Disk Access** to Terminal:
   - System Settings > Privacy & Security > Full Disk Access
   - Add Terminal (or your terminal app)

2. **Run the installer:**
   ```bash
   ./Scripts/install-server.sh
   ```

3. **Save your API key** - displayed at the end of installation

4. **Install Tailscale** and note your Tailscale IP address

#### Client (Work Mac)

1. **Network Setup** (choose one):
   - **Tailscale** (recommended): Install Tailscale and sign in with the same account
   - **Cloudflare Tunnel**: Use the built-in wizard in Server Settings > Cloudflare tab, or see `Scripts/setup-cloudflare-tunnel.md` for manual setup

2. **Install the client:**
   - Open the DMG from `build/MessageBridge-Installer.dmg`
   - Drag MessageBridge to Applications

3. **Configure the client:**
   - Launch MessageBridge
   - Open Settings (Cmd+,)
   - Enter server URL:
     - Tailscale: `http://<tailscale-ip>:8080`
     - Cloudflare: `https://messagebridge.yourdomain.com`
   - Enter your API key
   - **Enable E2E Encryption** (required for Cloudflare Tunnel, recommended for all)

### Using the Client

#### Main Interface
```
┌──────────────┬─────────────────────────────────────────┐
│ Conversations│  Message Thread                         │
├──────────────┼─────────────────────────────────────────┤
│ [Search...]  │  Contact Name              ● Connected  │
├──────────────┼─────────────────────────────────────────┤
│              │                                         │
│ John Doe     │         Hey, how are you?              │
│ See you tom… │                     ┌─────────────────┐ │
│              │                     │ I'm good! You?  │ │
│ Jane Smith   │                     └─────────────────┘ │
│ Got it, th…  │                                         │
│              ├─────────────────────────────────────────┤
│              │ [Type a message...]              [Send] │
└──────────────┴─────────────────────────────────────────┘
```

#### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+F` | Focus search field |
| `Cmd+N` | New message (placeholder) |
| `Cmd+Shift+L` | View logs |
| `Enter` | Send message |
| `Option+Enter` | Insert newline in message |

#### Notifications

- Notifications appear for new messages when the app is in background
- Click a notification to open that conversation
- Notifications are cleared when you open a conversation

#### Connection Status

The status indicator in the toolbar shows:
- 🟢 **Connected** - Successfully connected to server
- 🟡 **Connecting** - Connection in progress
- 🔴 **Disconnected** - Not connected to server

#### Viewing Logs

Access application logs via the menu: **MessageBridge > View Logs** (or `Cmd+Shift+L`)

The log viewer shows:
- **Log levels**: Debug, Info, Warning, Error (with filtering)
- **Source location**: File, function, and line number where the log was generated
- **Search**: Filter logs by message content, filename, or function name
- **Export**: Save logs to a text file for sharing or debugging

Logs are stored at: `~/Library/Application Support/MessageBridge/Logs/`
- `messagebridge.log` - Human-readable log file
- `messagebridge-logs.json` - Structured JSON log file

**Automatic cleanup**: Logs older than 7 days are automatically deleted to save disk space.

### Server Management

```bash
# Stop server
launchctl unload ~/Library/LaunchAgents/com.messagebridge.server.plist

# Start server
launchctl load ~/Library/LaunchAgents/com.messagebridge.server.plist

# Restart server
launchctl kickstart -k gui/$(id -u)/com.messagebridge.server

# View logs
tail -f /usr/local/var/log/messagebridge/server.log
tail -f /usr/local/var/log/messagebridge/error.log
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| "Cannot read Messages database" | Grant Full Disk Access to Terminal |
| Server not accessible from client | Check Tailscale is connected on both Macs |
| Messages not sending | Grant Automation permission for Messages.app |
| No notifications | Check notification permissions in System Settings |

---

## Architecture

```
Work Mac                              Home Mac
┌───────────────┐    Tailscale VPN    ┌───────────────┐
│ SwiftUI Client│◄───────────────────►│ Vapor Server  │
└───────────────┘                     └───────┬───────┘
                                              │
                                      ┌───────▼───────┐
                                      │ Messages.app  │
                                      │ + chat.db     │
                                      └───────────────┘
```

**Data flow:**
1. Server reads from `~/Library/Messages/chat.db` (SQLite, read-only)
2. Server sends messages via AppleScript to Messages.app
3. Server pushes real-time updates via WebSocket when chat.db changes
4. Client connects over Tailscale VPN (secure, no port forwarding)

## Key Technical Details

### Messages Database
- Location: `~/Library/Messages/chat.db`
- Requires **Full Disk Access** permission
- Uses WAL mode - open read-only
- Apple timestamp format: nanoseconds since 2001-01-01
  ```swift
  Date(timeIntervalSinceReferenceDate: timestamp / 1_000_000_000)
  ```

### Important Tables
- `chat` - conversations
- `message` - messages (some have NULL text for attachments/reactions)
- `handle` - contacts (phone/email)
- `chat_message_join` - links chats to messages
- `chat_handle_join` - links chats to participants

### Sending Messages
Uses AppleScript via NSAppleScript - requires **Automation** permission for Messages.app.

### Security
- **API keys** stored in macOS Keychain
  - Server: `com.messagebridge.server` service
  - Client: `com.messagebridge.client` service
- **Transport encryption**:
  - Tailscale: WireGuard encryption
  - Cloudflare Tunnel: TLS encryption
- **End-to-End encryption** (optional, recommended):
  - Uses AES-256-GCM with HKDF key derivation
  - API key used to derive encryption key
  - Enabled via `X-E2E-Encryption: enabled` header
  - Ensures relay servers cannot read message content

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /health | Server status |
| GET | /conversations | List conversations (paginated) |
| GET | /conversations/:id/messages | Messages for conversation |
| GET | /search?q= | Search messages |
| POST | /send | Send a message |
| WS | /ws | Real-time updates |

All endpoints require `X-API-Key` header.

### WebSocket Messages

```json
// Server -> Client: New message
{
  "type": "new_message",
  "data": {
    "id": 123,
    "conversationId": "chat123",
    "text": "Hello!",
    "sender": "+15551234567",
    "date": "2024-01-15T10:30:00Z",
    "isFromMe": false
  }
}
```

## Coding Guidelines

### General Principles
- **Avoid deeply nested logic** - Extract nested conditions into early returns or separate functions. Prefer guard statements over nested if-else.
- **No global variables** - Functions should only receive data through arguments passed into them. Use dependency injection.
- **Immutability** - Avoid mutating variables passed into a function. Return new values instead of modifying inputs.
- **Modular design** - Features should be self-contained and swappable without causing cascading changes elsewhere. Use protocols to define boundaries.
- **Test-driven development** - Always write tests first, then implement code to make them pass. Tests act as user stories that define expected behavior.
- **Documentation updates required** - Whenever any user-facing or external-facing part of the app is changed (UI, settings, API, CLI, installation, etc.), all related documentation must be updated to reflect the change. This includes README.md, CLAUDE.md (User Guide section), spec.md, and any relevant guides in Scripts/.
- **Automate repetitive tasks** - Create CI/CD pipelines and scripts to automate repetitive tasks such as building, testing, releasing, and deployment. Manual processes should be automated when performed more than once.
- **Versioning and releases** - Server and Client are versioned independently. Each has its own VERSION file (`MessageBridgeServer/VERSION` and `MessageBridgeClient/VERSION`). Use prefixed git tags: `server-v1.2.3` or `client-v1.2.3`. Bump version numbers according to conventional commits (feat = minor, fix = patch, breaking change = major).

### Versioning

Server and Client apps are versioned separately since they have different release cycles:

- **Server version**: `MessageBridgeServer/VERSION`
- **Client version**: `MessageBridgeClient/VERSION`

**Git tags use prefixes:**
- Server releases: `server-v1.2.3`
- Client releases: `client-v1.2.3`

**Build script automatically syncs versions:**
```bash
./Scripts/build-release.sh              # Build both apps
./Scripts/build-release.sh server       # Build server only
./Scripts/build-release.sh client       # Build client only
```

The build script reads from each app's VERSION file and updates the corresponding Version.swift before building.

### Testing Workflow
1. **Write failing tests first** - Define what the feature should do through test cases before writing any implementation code.
2. **Tests as user stories** - Each test should describe a specific behavior or use case (e.g., `testConnect_success_setsStatusToConnected`).
3. **Cover all cases** - Write tests for success cases, edge cases, and error conditions before implementing.
4. **Implement to pass** - Write the minimum code necessary to make all tests pass.
5. **Refactor with confidence** - Once tests pass, refactor the implementation knowing tests will catch regressions.

### Conventional Commits

All commits must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification for automatic changelog generation and semantic versioning.

**Format:**
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
| Type | Description | Version Bump |
|------|-------------|--------------|
| `feat` | New feature | Minor (0.X.0) |
| `fix` | Bug fix | Patch (0.0.X) |
| `docs` | Documentation only | None |
| `chore` | Maintenance, dependencies | None |
| `refactor` | Code refactoring | None |
| `test` | Adding/updating tests | None |
| `style` | Formatting, whitespace | None |
| `perf` | Performance improvement | Patch |

**Scopes:** `server`, `client`, `docs`, `ci`, `scripts`

**Examples:**
```bash
feat(client): add Tailscale status indicator
fix(server): handle nil message text in WebSocket
docs: update installation instructions
chore(ci): add GitHub Actions workflow
refactor(client): extract message bubble into component
BREAKING CHANGE: rename API endpoint from /send to /messages
```

**Breaking Changes:** Add `BREAKING CHANGE:` in the footer to trigger a major version bump.

### Swift Conventions
- Use `actor` for thread-safe classes (e.g., `ChatDatabase`, `BridgeConnection`)
- Use `@MainActor` for ViewModels that update UI state
- Prefer `async/await` over callbacks
- Models should be `Codable`, `Identifiable`, and `Sendable` where applicable

### Server (MessageBridgeServer)
- Database queries go in `Database/ChatDatabase.swift`
- Keep models in `Models/` - they're shared with client via copy
- Use GRDB's `Row` for flexible SQLite queries
- Open chat.db in read-only mode only

### Client (MessageBridgeClient)
- Views go in `Views/`, one file per view
- Use `@EnvironmentObject` for shared state (MessagesViewModel)
- Use `NavigationSplitView` for the main layout
- Prefer `@State` for local view state, `@Published` in ViewModels

### Logging & Debugging

Use the built-in logging system instead of `print()` statements for all error handling and debugging:

```swift
// Import is automatic - logging functions are in MessageBridgeClientCore

// Log levels (from least to most severe)
logDebug("Loaded \(count) conversations")      // Development info
logInfo("WebSocket connection started")         // Notable events
logWarning("Notification permission denied")    // Non-critical issues
logError("Connection failed", error: error)     // Errors with Error object
logError("Failed to decode message")            // Errors without Error object
```

**Key features:**
- **Source location**: Every log automatically captures file, function, and line number
- **Persistence**: Logs are saved to `~/Library/Application Support/MessageBridge/Logs/`
- **Auto-cleanup**: Logs older than 7 days are automatically deleted
- **Viewing**: Users can view logs via `Cmd+Shift+L` or the app menu

**When to use each level:**
- `logDebug` - Detailed info useful during development (counts, state changes)
- `logInfo` - Important events worth knowing about (connections, major operations)
- `logWarning` - Issues that don't prevent operation (permission denied, retry succeeded)
- `logError` - Failures that affect functionality (connection failed, send failed)

### Shared Patterns
- Models are duplicated between server and client (no shared package yet)
- Use ISO8601 for JSON date encoding/decoding
- API authentication via `X-API-Key` header

## File Structure

```
MessageBridge/
├── CLAUDE.md                    # This file - dev guidance + user docs
├── spec.md                      # Project specification with milestones
├── CHANGELOG.md                 # Release history (auto-generated)
├── CONTRIBUTING.md              # Contribution guidelines
│
├── .github/
│   └── workflows/
│       ├── ci.yml               # Build & test on PR
│       └── release.yml          # Build & release on tag
│
├── MessageBridgeServer/
│   ├── VERSION                  # Server version (semver)
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MessageBridgeCore/   # Testable library
│   │   │   ├── Models/
│   │   │   ├── Database/
│   │   │   ├── API/
│   │   │   ├── Messaging/
│   │   │   ├── FileWatcher/
│   │   │   ├── Security/
│   │   │   ├── Tailscale/       # TailscaleManager
│   │   │   ├── Cloudflare/      # CloudflaredManager
│   │   │   └── Version/
│   │   └── MessageBridgeServer/ # Menu Bar App (SwiftUI)
│   │       ├── App/
│   │       │   └── ServerApp.swift
│   │       └── Views/
│   │           ├── MenuBarView.swift
│   │           ├── StatusMenuView.swift
│   │           ├── TailscaleSettingsView.swift
│   │           ├── CloudflareSettingsView.swift
│   │           └── LogViewerView.swift
│   └── Tests/
│
├── MessageBridgeClient/
│   ├── VERSION                  # Client version (semver)
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MessageBridgeClientCore/  # Testable library
│   │   │   ├── Models/
│   │   │   ├── Services/
│   │   │   │   ├── BridgeConnection.swift
│   │   │   │   └── TailscaleManager.swift
│   │   │   ├── ViewModels/
│   │   │   ├── Security/
│   │   │   ├── Logging/
│   │   │   └── Version/
│   │   └── MessageBridgeClient/      # Executable (SwiftUI)
│   │       ├── App/
│   │       └── Views/
│   │           ├── ContentView.swift
│   │           ├── ConversationListView.swift
│   │           ├── MessageThreadView.swift
│   │           ├── LogViewerView.swift
│   │           └── TailscaleStatusView.swift
│   └── Tests/
│
└── Scripts/
    ├── build-release.sh         # Build both apps for release
    ├── create-dmgs.sh           # Package apps into DMGs
    ├── generate-changelog.sh    # Generate changelog from commits
    ├── install-server.sh        # Server installer (legacy)
    ├── package-client.sh        # Client DMG packager (legacy)
    ├── setup-tailscale.md       # Tailscale network setup guide
    └── setup-cloudflare-tunnel.md  # Cloudflare Tunnel setup guide
```

## Documentation

- `CLAUDE.md` - Development guidance and user documentation (this file)
- `spec.md` - Full project specification with milestones
- `CONTRIBUTING.md` - Commit conventions and contribution guidelines
- `CHANGELOG.md` - Version history and release notes
- `Scripts/setup-tailscale.md` - Detailed Tailscale setup guide
- `Scripts/setup-cloudflare-tunnel.md` - Cloudflare Tunnel setup guide (alternative to Tailscale)
