# iMessage Bridge - Project Specification

## Project Overview

A self-hosted system for accessing iMessages/SMS on a work Mac (without iCloud) by relaying through a home Mac (with iCloud). Native Swift/SwiftUI implementation with no third-party message services.

---

## Milestone 1: Project Setup & Database Reading

**Goal:** Establish project structure and prove we can read from the Messages database.

### Deliverables
- [ ] Create `MessageBridgeServer` Swift Package with Vapor
- [ ] Create `MessageBridgeClient` Xcode project with SwiftUI
- [ ] Define shared data models (`Message`, `Conversation`, `Handle`)
- [ ] Implement `ChatDatabase.swift` to query `chat.db`
- [ ] CLI tool that prints recent conversations and messages

### Success Criteria
```bash
# Running on home Mac:
swift run MessageBridgeServer --test-db
# Output: Lists 10 most recent conversations with last message preview
```

### Key Technical Decisions
- Use Vapor for HTTP/WebSocket server
- Use SQLite.swift or GRDB for database access
- Full Disk Access permission required

---

## Milestone 2: REST API

**Goal:** Expose message data via HTTP endpoints.

### Deliverables
- [ ] `GET /health` - Server status check
- [ ] `GET /conversations` - List all conversations (paginated)
- [ ] `GET /conversations/:id/messages` - Messages for a conversation (paginated)
- [ ] `GET /search?q=` - Search messages by content
- [ ] API key authentication middleware

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

## Milestone 3: Message Sending

**Goal:** Send messages via AppleScript integration.

### Deliverables
- [ ] `MessageSender.swift` - AppleScript bridge
- [ ] `POST /send` endpoint
- [ ] Handle iMessage vs SMS routing
- [ ] Return delivery status

### Success Criteria
```bash
curl -X POST -H "X-API-Key: $KEY" \
  -d '{"to": "+15551234567", "text": "Hello from API"}' \
  http://localhost:8080/send
# Message appears in Messages.app and is sent to recipient
```

### AppleScript Integration
```swift
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
```

---

## Milestone 4: Real-Time Updates

**Goal:** Push new messages to connected clients via WebSocket.

### Deliverables
- [ ] `FileWatcher.swift` - FSEvents monitor for chat.db changes
- [ ] WebSocket endpoint at `/ws`
- [ ] Push new messages to all connected clients
- [ ] Handle reconnection gracefully

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
- [ ] `ContentView.swift` - NavigationSplitView layout
- [ ] `ConversationListView.swift` - Sidebar with conversations
- [ ] `MessageThreadView.swift` - Message bubbles display
- [ ] `BridgeConnection.swift` - REST + WebSocket client
- [ ] Connection status indicator in toolbar

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

## Milestone 6: macOS Client - Compose & Send

**Goal:** Add message composition and sending capability.

### Deliverables
- [ ] `ComposeView.swift` - Message input with send button
- [ ] Send message via REST API
- [ ] Optimistic UI update (show message immediately)
- [ ] Handle send failures gracefully
- [ ] Keyboard shortcut: Enter to send, Shift+Enter for newline

### Success Criteria
- Type message in compose field
- Press Enter or click Send
- Message appears in thread immediately (pending state)
- Message sends successfully
- Recipient receives the message

---

## Milestone 7: Notifications & Polish

**Goal:** Native notifications and UX polish.

### Deliverables
- [ ] `NotificationManager.swift` - UserNotifications integration
- [ ] Show notification for new messages (when app not focused)
- [ ] Click notification to open conversation
- [ ] Keyboard shortcuts (Cmd+N new message, Cmd+F search)
- [ ] Dark mode support
- [ ] App icon

### Success Criteria
- New message arrives while app in background
- Native macOS notification appears
- Clicking notification opens the conversation
- All keyboard shortcuts functional

---

## Milestone 8: Deployment & Security

**Goal:** Production-ready deployment with proper security.

### Deliverables
- [ ] LaunchAgent plist for server auto-start
- [ ] Keychain storage for API key
- [ ] Tailscale setup documentation
- [ ] Server installer script
- [ ] Client DMG packaging

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
| Database Access | GRDB or SQLite.swift |
| Client UI | SwiftUI (macOS 13+) |
| Networking | URLSession + WebSocket |
| Security | Keychain, Tailscale |

---

## File Structure

```
MessageBridge/
├── spec.md                      # This file
├── MessageBridgeServer/
│   ├── Package.swift
│   └── Sources/
│       └── MessageBridgeServer/
│           ├── main.swift
│           ├── Models/
│           ├── Database/
│           ├── Messaging/
│           ├── Server/
│           └── Auth/
├── MessageBridgeClient/
│   ├── MessageBridgeClient.xcodeproj
│   └── MessageBridgeClient/
│       ├── App/
│       ├── Views/
│       ├── ViewModels/
│       ├── Services/
│       └── Models/
└── Scripts/
    ├── install-server.sh
    └── setup-tailscale.md
```
