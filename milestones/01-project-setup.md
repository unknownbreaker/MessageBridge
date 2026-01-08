# Milestone 1: Project Setup & Database Reading

## Checklist

### 1. Server Project Setup
- [ ] Create `MessageBridgeServer/` directory
- [ ] Initialize Swift Package (`swift package init --type executable`)
- [ ] Add Vapor dependency to `Package.swift`
- [ ] Add GRDB (or SQLite.swift) dependency for database access
- [ ] Verify project builds with `swift build`

### 2. Shared Data Models
- [ ] Create `Models/` directory
- [ ] Define `Handle.swift` - represents a contact/phone number
  ```swift
  struct Handle: Codable, Identifiable {
      let id: Int
      let address: String  // phone number or email
      let service: String  // iMessage, SMS
  }
  ```
- [ ] Define `Message.swift` - a single message
  ```swift
  struct Message: Codable, Identifiable {
      let id: Int
      let guid: String
      let text: String?
      let date: Date
      let isFromMe: Bool
      let handleId: Int
      let conversationId: String
  }
  ```
- [ ] Define `Conversation.swift` - a chat thread
  ```swift
  struct Conversation: Codable, Identifiable {
      let id: String
      let chatIdentifier: String
      let displayName: String?
      let participants: [Handle]
      let lastMessage: Message?
  }
  ```

### 3. Database Access Layer
- [ ] Create `Database/ChatDatabase.swift`
- [ ] Implement database connection to `~/Library/Messages/chat.db`
- [ ] Handle database being locked (read-only mode)
- [ ] Implement `fetchConversations(limit:offset:)` query
- [ ] Implement `fetchMessages(conversationId:limit:offset:)` query
- [ ] Implement `fetchHandles()` query
- [ ] Add date conversion (Apple's Core Data timestamp to Date)
  ```swift
  // Apple stores dates as seconds since 2001-01-01
  // Need to convert: Date(timeIntervalSinceReferenceDate: timestamp / 1_000_000_000)
  ```

### 4. Database Schema Understanding
- [ ] Document the `chat` table structure
- [ ] Document the `message` table structure
- [ ] Document the `handle` table structure
- [ ] Document the `chat_message_join` junction table
- [ ] Document the `chat_handle_join` junction table
- [ ] Write reference SQL queries:
  ```sql
  -- Get recent conversations with last message
  SELECT c.ROWID, c.chat_identifier, c.display_name,
         m.text, m.date, m.is_from_me
  FROM chat c
  LEFT JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
  LEFT JOIN message m ON cmj.message_id = m.ROWID
  WHERE m.ROWID = (
      SELECT MAX(m2.ROWID) FROM message m2
      JOIN chat_message_join cmj2 ON m2.ROWID = cmj2.message_id
      WHERE cmj2.chat_id = c.ROWID
  )
  ORDER BY m.date DESC
  LIMIT 50;
  ```

### 5. CLI Test Command
- [ ] Add `--test-db` flag to main.swift
- [ ] Print connection status
- [ ] Print count of conversations, messages, handles
- [ ] Print 10 most recent conversations with preview
- [ ] Format output nicely for terminal

### 6. Client Project Setup
- [ ] Create `MessageBridgeClient/` directory
- [ ] Create new Xcode project (macOS App, SwiftUI)
- [ ] Set minimum deployment target to macOS 13.0
- [ ] Create folder structure: `App/`, `Views/`, `ViewModels/`, `Services/`, `Models/`
- [ ] Copy shared models to client `Models/` folder
- [ ] Verify project builds and runs

### 7. Permissions & Security
- [ ] Document Full Disk Access requirement
- [ ] Test database access without Full Disk Access (should fail)
- [ ] Test database access with Full Disk Access (should succeed)
- [ ] Add error handling for permission denied

---

## Verification Steps

After completing all tasks, verify:

```bash
# 1. Build the server
cd MessageBridgeServer
swift build

# 2. Run database test (requires Full Disk Access for Terminal)
swift run MessageBridgeServer --test-db

# Expected output:
# ✓ Connected to Messages database
# ✓ Found 142 conversations
# ✓ Found 8,451 messages
# ✓ Found 89 contacts
#
# Recent Conversations:
# ┌────────────────────┬─────────────────────┬──────────────────┐
# │ Contact            │ Last Message        │ Date             │
# ├────────────────────┼─────────────────────┼──────────────────┤
# │ John Doe           │ See you tomorrow!   │ Today 10:30 AM   │
# │ Jane Smith         │ Got it, thanks!     │ Today 9:15 AM    │
# │ ...                │ ...                 │ ...              │
# └────────────────────┴─────────────────────┴──────────────────┘

# 3. Build the client
cd ../MessageBridgeClient
xcodebuild -scheme MessageBridgeClient build

# 4. Open in Xcode and run
open MessageBridgeClient.xcodeproj
```

---

## Files to Create

```
MessageBridgeServer/
├── Package.swift
└── Sources/
    └── MessageBridgeServer/
        ├── main.swift
        ├── Models/
        │   ├── Handle.swift
        │   ├── Message.swift
        │   └── Conversation.swift
        └── Database/
            └── ChatDatabase.swift

MessageBridgeClient/
└── MessageBridgeClient/
    ├── MessageBridgeClientApp.swift
    ├── Models/
    │   ├── Handle.swift
    │   ├── Message.swift
    │   └── Conversation.swift
    └── Views/
        └── ContentView.swift (placeholder)
```

---

## Notes

- The `chat.db` file is SQLite but uses Write-Ahead Logging (WAL). Open in read-only mode.
- Apple's timestamp format: nanoseconds since 2001-01-01. Divide by 1,000,000,000 for seconds.
- Some messages have `NULL` text (attachments, reactions). Handle gracefully.
- Group chats have multiple handles; 1:1 chats have one handle.
