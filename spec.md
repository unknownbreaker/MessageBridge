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

## Future Enhancements (Out of Scope)

These are not part of the initial implementation:

- [ ] Attachment support (images, files)
- [ ] Group chat management
- [ ] Reactions/tapbacks
- [ ] Read receipts
- [ ] Contact photo sync
- [ ] Multiple client support
- [ ] Message encryption at rest

---

## Technical Stack

| Component | Technology |
|-----------|------------|
| Server Runtime | Swift 5.9+ |
| Server Framework | Vapor 4 |
| Database Access | GRDB |
| Client UI | SwiftUI (macOS 13+) |
| Networking | URLSession + WebSocket |
| Security | Keychain, Tailscale |
| Testing | XCTest, Protocol Mocks |

---

## File Structure

```
MessageBridge/
├── CLAUDE.md                    # Claude Code guidance
├── spec.md                      # This file
├── milestones/                  # Detailed milestone checklists
│
├── MessageBridgeServer/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MessageBridgeCore/   # Testable library
│   │   │   ├── Models/
│   │   │   │   ├── Handle.swift
│   │   │   │   ├── Message.swift
│   │   │   │   └── Conversation.swift
│   │   │   └── Database/
│   │   │       └── ChatDatabase.swift
│   │   └── MessageBridgeServer/ # Executable
│   │       └── main.swift
│   └── Tests/
│       └── MessageBridgeCoreTests/
│           ├── HandleTests.swift
│           ├── MessageTests.swift
│           └── ConversationTests.swift
│
├── MessageBridgeClient/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MessageBridgeClientCore/  # Testable library
│   │   │   ├── Models/
│   │   │   │   └── Models.swift
│   │   │   ├── Services/
│   │   │   │   └── BridgeConnection.swift
│   │   │   ├── ViewModels/
│   │   │   │   └── MessagesViewModel.swift
│   │   │   ├── Security/
│   │   │   │   └── KeychainManager.swift
│   │   │   └── Logging/
│   │   │       └── Logger.swift
│   │   └── MessageBridgeClient/      # Executable (SwiftUI)
│   │       ├── App/
│   │       │   └── MessageBridgeApp.swift
│   │       └── Views/
│   │           ├── ContentView.swift
│   │           ├── ConversationListView.swift
│   │           ├── MessageThreadView.swift
│   │           └── LogViewerView.swift
│   └── Tests/
│       └── MessageBridgeClientCoreTests/
│           ├── MessagesViewModelTests.swift
│           └── LoggerTests.swift
│
└── Scripts/
    ├── install-server.sh
    └── setup-tailscale.md
```
