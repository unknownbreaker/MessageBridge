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

- **Home Mac**: macOS 14+, signed into iCloud with Messages enabled
- **Work Mac**: macOS 14+
- **Tailscale**: Free account for secure VPN connection

## Installation

### Option 1: Download Release (Recommended)

Download the latest release from [GitHub Releases](https://github.com/unknownbreaker/MessageBridge/releases):

- `MessageBridge-Server-x.x.x.dmg` - For your home Mac
- `MessageBridge-x.x.x.dmg` - For your work Mac

### Option 2: Build from Source

See [Building from Source](#building-from-source) below.

## Quick Start

### Step 1: Set Up Tailscale (Both Macs)

1. Download and install [Tailscale](https://tailscale.com/download) on both Macs
2. Launch Tailscale and sign in with the same account on both
3. Note your home Mac's Tailscale IP (click the menu bar icon)

### Step 2: Set Up the Server (Home Mac)

1. **Download** `MessageBridge-Server-x.x.x.dmg` from [Releases](https://github.com/unknownbreaker/MessageBridge/releases)
2. **Install** - Open the DMG and drag MessageBridge Server to Applications
3. **Grant Permissions**:
   - Launch MessageBridge Server from Applications
   - Grant **Full Disk Access** when prompted (required to read Messages database)
   - System Settings > Privacy & Security > Full Disk Access > Enable MessageBridge Server
4. **Start the Server** - Click "Start Server" in the menu bar dropdown
5. **Copy your API Key** - Click the copy button next to the API key (you'll need this for the client)

The server runs in your menu bar with a status indicator:
- Gray: Stopped
- Yellow: Starting
- Green: Running
- Red: Error

### Step 3: Set Up the Client (Work Mac)

1. **Download** `MessageBridge-x.x.x.dmg` from [Releases](https://github.com/unknownbreaker/MessageBridge/releases)
2. **Install** - Open the DMG and drag MessageBridge to Applications
3. **Configure Connection**:
   - Launch MessageBridge
   - Open Settings (`Cmd+,`)
   - Go to the **Connection** tab
   - Enter Server URL: `http://<tailscale-ip>:8080` (use your home Mac's Tailscale IP)
   - Enter the API Key from Step 2
   - Click Save
4. **Verify Connection** - The status indicator in the toolbar should turn green

### Step 4: Start Messaging

- Your conversations will load automatically
- Click a conversation to view messages
- Type a message and press Enter to send
- New messages appear in real-time via WebSocket

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

The server runs as a menu bar app. Click the menu bar icon to:
- View server status and Tailscale connection
- Start/Stop/Restart the server
- View and copy your API key
- Access settings and logs

**Settings** (`Cmd+,`):
- Change server port
- Enable/disable auto-start on login
- Generate a new API key

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
├── .github/workflows/
│   ├── ci.yml               # Build & test on PRs
│   └── release.yml          # Automated releases
├── MessageBridgeServer/     # Menu bar server app (Swift Package)
├── MessageBridgeClient/     # SwiftUI client app (Swift Package)
├── Scripts/
│   ├── build-release.sh     # Build both apps
│   ├── create-dmgs.sh       # Create DMG installers
│   ├── generate-changelog.sh # Generate release notes
│   └── setup-tailscale.md   # Network setup guide
├── CLAUDE.md                # Development docs
├── CONTRIBUTING.md          # Contribution guidelines
├── CHANGELOG.md             # Version history
└── spec.md                  # Project specification
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
