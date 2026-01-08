# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iMessage Bridge is a self-hosted system for accessing iMessages/SMS on a work Mac (without iCloud) by relaying through a home Mac (with iCloud). Two components:

- **MessageBridgeServer** - Swift/Vapor daemon running on home Mac, reads from Messages database, exposes REST/WebSocket API
- **MessageBridgeClient** - SwiftUI macOS app running on work Mac, connects to server via Tailscale

## Build Commands

### Server (Swift Package)
```bash
cd MessageBridgeServer
swift build                           # Build
swift run MessageBridgeServer         # Run server
swift run MessageBridgeServer --test-db  # Test database connectivity
swift test                            # Run tests
```

### Client (Xcode)
```bash
cd MessageBridgeClient
xcodebuild -scheme MessageBridgeClient build
open MessageBridgeClient.xcodeproj    # Open in Xcode
```

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

## API Endpoints (Planned)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /health | Server status |
| GET | /conversations | List conversations (paginated) |
| GET | /conversations/:id/messages | Messages for conversation |
| GET | /search?q= | Search messages |
| POST | /send | Send a message |
| WS | /ws | Real-time updates |

All endpoints require `X-API-Key` header.

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

## Documentation

- `spec.md` - Full project specification with milestones
- `milestones/` - Detailed checklists for each milestone
