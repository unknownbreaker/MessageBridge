# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Important:** When making changes that affect how users interact with the app (UI, keyboard shortcuts, configuration, installation, etc.), update the User Guide section of this document accordingly.

## Project Overview

iMessage Bridge is a self-hosted system for accessing iMessages/SMS on a work Mac (without iCloud) by relaying through a home Mac (with iCloud). Two components:

- **MessageBridgeServer** - Swift/Vapor daemon running on home Mac, reads from Messages database, exposes REST/WebSocket API
- **MessageBridgeClient** - SwiftUI macOS app running on work Mac, connects to server via Tailscale

## Build Commands

### Server (Swift Package)
```bash
cd MessageBridgeServer
swift build                           # Build debug
swift build -c release                # Build release
swift run MessageBridgeServer         # Run server
swift run MessageBridgeServer --test-db  # Test database connectivity
swift test                            # Run tests (43 tests)
```

### Client (Swift Package)
```bash
cd MessageBridgeClient
swift build                           # Build debug
swift build -c release                # Build release
swift run MessageBridgeClient         # Run client
swift test                            # Run tests (16 tests)
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

1. **Install Tailscale** and sign in with the same account

2. **Install the client:**
   - Open the DMG from `build/MessageBridge-Installer.dmg`
   - Drag MessageBridge to Applications

3. **Configure the client:**
   - Launch MessageBridge
   - Enter server URL: `http://<tailscale-ip>:8080`
   - Enter your API key

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
- API keys stored in macOS Keychain
- Server: `com.messagebridge.server` service
- Client: `com.messagebridge.client` service
- All traffic encrypted via Tailscale (WireGuard)

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

### Testing Workflow
1. **Write failing tests first** - Define what the feature should do through test cases before writing any implementation code.
2. **Tests as user stories** - Each test should describe a specific behavior or use case (e.g., `testConnect_success_setsStatusToConnected`).
3. **Cover all cases** - Write tests for success cases, edge cases, and error conditions before implementing.
4. **Implement to pass** - Write the minimum code necessary to make all tests pass.
5. **Refactor with confidence** - Once tests pass, refactor the implementation knowing tests will catch regressions.

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

### Shared Patterns
- Models are duplicated between server and client (no shared package yet)
- Use ISO8601 for JSON date encoding/decoding
- API authentication via `X-API-Key` header

## File Structure

```
MessageBridge/
├── CLAUDE.md                    # This file - dev guidance + user docs
├── spec.md                      # Project specification with milestones
├── MessageBridgeServer/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MessageBridgeCore/   # Testable library
│   │   │   ├── Models/
│   │   │   ├── Database/
│   │   │   ├── API/
│   │   │   ├── Messaging/
│   │   │   ├── FileWatcher/
│   │   │   └── Security/
│   │   └── MessageBridgeServer/ # Executable
│   └── Tests/
├── MessageBridgeClient/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MessageBridgeClientCore/  # Testable library
│   │   │   ├── Models/
│   │   │   ├── Services/
│   │   │   ├── ViewModels/
│   │   │   └── Security/
│   │   └── MessageBridgeClient/      # Executable (SwiftUI)
│   │       ├── App/
│   │       └── Views/
│   └── Tests/
└── Scripts/
    ├── install-server.sh        # Server installer
    ├── package-client.sh        # Client DMG packager
    ├── setup-tailscale.md       # Network setup guide
    └── com.messagebridge.server.plist
```

## Documentation

- `CLAUDE.md` - Development guidance and user documentation (this file)
- `spec.md` - Full project specification with milestones
- `Scripts/setup-tailscale.md` - Detailed Tailscale setup guide
