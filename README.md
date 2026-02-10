# MessageBridge

A self-hosted iMessage bridge that lets you access your iMessages and SMS on any Mac by relaying through your home Mac.

```
Work Mac                              Home Mac
┌───────────────┐  Tailscale/Tunnel   ┌───────────────┐
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
- **Secure** - End-to-end encryption ensures only you can read your messages
- **Flexible networking** - Works with Tailscale VPN or Cloudflare Tunnel

## Features

- View all conversations and messages
- Send iMessages and SMS
- Real-time message notifications
- Search conversations
- Native macOS notifications
- Secure API key authentication
- End-to-end encryption (AES-256-GCM)
- Auto-start server on login

## Requirements

- **Home Mac**: macOS 14+, signed into iCloud with Messages enabled
- **Work Mac**: macOS 14+
- **Network**: One of the following:
  - [Tailscale](https://tailscale.com) (recommended) - Free VPN, easiest setup
  - [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) - Free, works when Tailscale is blocked

## Installation

### Option 1: Download Release (Recommended)

Download the latest release from [GitHub Releases](https://github.com/unknownbreaker/MessageBridge/releases):

- `MessageBridgeServer-x.x.x.dmg` - For your home Mac
- `MessageBridgeClient-x.x.x.dmg` - For your work Mac

### Option 2: Build from Source

See [Building from Source](#building-from-source) below.

## Quick Start

### Step 1: Choose Your Network Setup

#### Option A: Tailscale (Recommended)

Best for: Personal devices where you can install Tailscale on both Macs.

1. Download and install [Tailscale](https://tailscale.com/download) on both Macs
2. Launch Tailscale and sign in with the same account on both
3. Note your home Mac's Tailscale IP (click the menu bar icon)

#### Option B: Cloudflare Tunnel

Best for: Work Macs where Tailscale is blocked by IT policies. Setup is done on your **Home Mac** using the server app's built-in wizard (see Step 2.6 below).

### Step 2: Set Up the Server (Home Mac)

1. **Download** `MessageBridgeServer-x.x.x.dmg` from [Releases](https://github.com/unknownbreaker/MessageBridge/releases)
2. **Install** - Open the DMG and drag MessageBridgeServer to Applications
3. **Grant Permissions**:
   - Launch MessageBridgeServer from Applications
   - Grant **Full Disk Access** when prompted (required to read Messages database)
   - System Settings > Privacy & Security > Full Disk Access > Enable MessageBridgeServer
4. **Start the Server** - Click "Start Server" in the menu bar dropdown
5. **Copy your API Key** - Click the copy button next to the API key (you'll need this for the client)
6. **Set Up Cloudflare Tunnel** (if using Option B):
   - Open Settings (`Cmd+,`) and go to the **Cloudflare** tab
   - Click **Install cloudflared** (one-time, no sudo required)
   - Click **Start Quick Tunnel** - a temporary URL is generated automatically
   - Copy the tunnel URL (you'll need this for the client)
   - For permanent tunnels with custom domains, see [Scripts/setup-cloudflare-tunnel.md](Scripts/setup-cloudflare-tunnel.md)

The server runs in your menu bar with a status indicator:
- Gray: Stopped
- Yellow: Starting
- Green: Running
- Red: Error

### Step 3: Set Up the Client (Work Mac)

1. **Download** `MessageBridgeClient-x.x.x.dmg` from [Releases](https://github.com/unknownbreaker/MessageBridge/releases)
2. **Install** - Open the DMG and drag MessageBridgeClient to Applications
3. **Configure Connection**:
   - Launch MessageBridgeClient
   - Open Settings (`Cmd+,`)
   - Go to the **Connection** tab
   - Enter Server URL:
     - Tailscale: `http://<tailscale-ip>:8080`
     - Cloudflare: `https://<your-tunnel-url>`
   - Enter the API Key from Step 2
   - **Enable "End-to-End Encryption"** (required for Cloudflare, recommended for all)
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
- Start/Stop Cloudflare Tunnel and copy tunnel URL
- Access settings and logs

**Settings** (`Cmd+,`):
- **General**: Change server port, enable auto-start on login
- **Security**: View/regenerate API key
- **Cloudflare**: Install cloudflared, manage Quick Tunnel

### Client Logs

View client logs via the menu: **MessageBridge > View Logs** (or `Cmd+Shift+L`)

Logs include source code location (file, function, line) and are automatically cleaned up after 7 days.

## Building from Source

### Server

```bash
cd Server
swift build -c release
swift test  # 72 tests
```

### Client

```bash
cd Client
swift build -c release
swift test  # 37 tests
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

- **API keys** stored in macOS Keychain
- **End-to-end encryption** (AES-256-GCM) - Message content encrypted before leaving your device
- **Transport security**:
  - Tailscale: WireGuard protocol
  - Cloudflare Tunnel: TLS encryption (enable E2E for full privacy)
- **No port forwarding** required - Server not exposed to internet
- **Read-only database access** - Messages.app handles all writes

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
├── Server/                  # Menu bar server app (Swift Package)
├── Client/                  # SwiftUI client app (Swift Package)
├── Scripts/
│   ├── build-release.sh     # Build both apps
│   ├── create-dmgs.sh       # Create DMG installers
│   ├── generate-changelog.sh # Generate release notes
│   ├── setup-tailscale.md   # Tailscale setup guide
│   └── setup-cloudflare-tunnel.md # Cloudflare Tunnel guide
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
