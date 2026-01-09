# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Milestones 10-13 planning for release automation
- Conventional commits specification

## [0.1.0] - 2024-01-08

### Added

#### Server (MessageBridgeServer)
- **Database Integration**: Read from macOS Messages `chat.db` database
- **REST API**: Endpoints for conversations, messages, and search
  - `GET /health` - Server status
  - `GET /conversations` - List conversations (paginated)
  - `GET /conversations/:id/messages` - Get messages (paginated)
  - `GET /search?q=` - Search messages
  - `POST /send` - Send message via AppleScript
- **WebSocket**: Real-time message updates via `/ws` endpoint
- **File Watcher**: FSEvents monitoring for chat.db changes
- **Security**: API key authentication stored in Keychain
- **Deployment**: LaunchAgent for auto-start on login

#### Client (MessageBridgeClient)
- **SwiftUI Interface**: Native macOS app with NavigationSplitView
- **Conversation List**: Sidebar with search and filtering
- **Message Thread**: Chat bubbles with proper styling
- **Message Compose**: Send messages with Enter, newline with Option+Enter
- **Real-time Updates**: WebSocket connection for instant messages
- **Notifications**: Native macOS notifications for new messages
- **Logging System**: Comprehensive logging with source location
  - Log levels: debug, info, warning, error
  - Persistent storage with 7-day auto-cleanup
  - Log viewer UI (`Cmd+Shift+L`)
- **Security**: Server credentials stored in Keychain

#### Infrastructure
- **Tailscale Documentation**: Setup guide for secure VPN connection
- **Installer Scripts**: Server installer and client DMG packager
- **Test Coverage**: 43 server tests, 28 client tests

### Technical Details
- Swift 5.9+ with async/await
- Vapor 4 for server framework
- GRDB for SQLite database access
- SwiftUI for all user interfaces
- Protocol-based dependency injection for testability

---

*This changelog will be automatically updated by CI/CD when using conventional commits.*
