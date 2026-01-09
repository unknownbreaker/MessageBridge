# MessageBridge

A self-hosted iMessage bridge that lets you access your iMessages and SMS on any Mac by relaying through your home Mac.

```
Work Mac                              Home Mac
┌───────────────┐    Tailscale VPN    ┌───────────────┐
│ SwiftUI Client│◄───────────────────►│ Vapor Server  │
└───────────────┘                     └───────┬───────┘
                                              │
                                      ┌───────▼───────┐
                                      │ Messages.app  │
                                      │   + iCloud    │
                                      └───────────────┘
```

## Why MessageBridge?

- **Work Mac without iCloud?** Access your personal iMessages from your work computer
- **Privacy first** - All data stays on your hardware, no third-party services
- **Native experience** - Built with Swift and SwiftUI for a true macOS feel
- **Real-time sync** - Messages appear instantly via WebSocket
- **Secure** - End-to-end encrypted via Tailscale VPN

## Features

- View all conversations and messages
- Send iMessages and SMS
- Real-time message notifications
- Search conversations
- Native macOS notifications
- Secure API key authentication
- Auto-start server on login

## Requirements

- **Home Mac**: macOS 13+, signed into iCloud with Messages enabled
- **Work Mac**: macOS 13+
- **Tailscale**: Free account for secure VPN connection
- **Xcode**: 15+ (for building from source)

## Quick Start

### 1. Set Up the Server (Home Mac)

```bash
# Clone the repository
git clone https://github.com/unknownbreaker/MessageBridge.git
cd MessageBridge

# Grant Full Disk Access to Terminal
# System Settings > Privacy & Security > Full Disk Access > Add Terminal

# Run the installer
./Scripts/install-server.sh
```

Save the API key displayed at the end - you'll need it for the client.

### 2. Set Up Tailscale (Both Macs)

1. Install [Tailscale](https://tailscale.com/download) on both Macs
2. Sign in with the same account
3. Note your home Mac's Tailscale IP (click menu bar icon)

### 3. Set Up the Client (Work Mac)

```bash
# Build and package the client
cd MessageBridge
./Scripts/package-client.sh

# Install from the DMG
open build/MessageBridge-Installer.dmg
# Drag to Applications
```

Launch MessageBridge and enter:
- Server URL: `http://<tailscale-ip>:8080`
- API Key: (from step 1)

## Usage

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+F` | Search conversations |
| `Cmd+N` | New message |
| `Cmd+Shift+L` | View logs |
| `Enter` | Send message |
| `Option+Enter` | New line in message |

### Server Management

```bash
# View server logs
tail -f /usr/local/var/log/messagebridge/server.log

# Restart server
launchctl kickstart -k gui/$(id -u)/com.messagebridge.server

# Stop server
launchctl unload ~/Library/LaunchAgents/com.messagebridge.server.plist
```

### Client Logs

View client logs via the menu: **MessageBridge > View Logs** (or `Cmd+Shift+L`)

Logs include source code location (file, function, line) and are automatically cleaned up after 7 days.

## Building from Source

### Server

```bash
cd MessageBridgeServer
swift build -c release
swift test  # 43 tests
```

### Client

```bash
cd MessageBridgeClient
swift build -c release
swift test  # 28 tests
```

## Architecture

| Component | Technology |
|-----------|------------|
| Server | Swift, Vapor 4, GRDB |
| Client | Swift, SwiftUI |
| Database | SQLite (Messages chat.db) |
| Real-time | WebSocket |
| Security | Keychain, Tailscale |
| Message Sending | AppleScript |

## API

All endpoints require `X-API-Key` header.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Server status |
| GET | `/conversations` | List conversations |
| GET | `/conversations/:id/messages` | Get messages |
| GET | `/search?q=` | Search messages |
| POST | `/send` | Send message |
| WS | `/ws` | Real-time updates |

## Security

- API keys stored in macOS Keychain
- All traffic encrypted via Tailscale (WireGuard protocol)
- Server only accessible via VPN (no port forwarding)
- Messages database accessed read-only

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Cannot read Messages database" | Grant Full Disk Access to Terminal |
| Server not accessible | Verify Tailscale connected on both Macs |
| Messages not sending | Grant Automation permission for Messages.app |
| No notifications | Check System Settings > Notifications |

## Project Structure

```
MessageBridge/
├── MessageBridgeServer/     # Vapor server (Swift Package)
├── MessageBridgeClient/     # SwiftUI client (Swift Package)
├── Scripts/
│   ├── install-server.sh    # Server installer
│   ├── package-client.sh    # DMG builder
│   └── setup-tailscale.md   # Network guide
├── CLAUDE.md               # Development docs
└── spec.md                 # Project specification
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests first (TDD)
4. Make your changes
5. Ensure all tests pass
6. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Vapor](https://vapor.codes) - Swift web framework
- [GRDB](https://github.com/groue/GRDB.swift) - SQLite toolkit
- [Tailscale](https://tailscale.com) - Secure networking
