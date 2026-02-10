#!/bin/bash
#
# MessageBridge Server Installer
# This script installs and configures the MessageBridge server on macOS.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/usr/local/bin"
LOG_DIR="/usr/local/var/log/messagebridge"
DATA_DIR="/usr/local/var/messagebridge"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.messagebridge.server.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}MessageBridge Server Installer${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}Error: This script only runs on macOS${NC}"
    exit 1
fi

# Check for Full Disk Access
echo -e "${YELLOW}Checking permissions...${NC}"
CHAT_DB="$HOME/Library/Messages/chat.db"
if [[ ! -r "$CHAT_DB" ]]; then
    echo -e "${RED}Error: Cannot read Messages database${NC}"
    echo ""
    echo "Please grant Full Disk Access to Terminal:"
    echo "1. Open System Settings > Privacy & Security > Full Disk Access"
    echo "2. Click '+' and add Terminal (or your terminal app)"
    echo "3. Restart Terminal and run this script again"
    exit 1
fi
echo -e "${GREEN}✓ Full Disk Access verified${NC}"

# Build the server
echo ""
echo -e "${YELLOW}Building MessageBridge Server...${NC}"
cd "$PROJECT_DIR/Server"

if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift is not installed${NC}"
    echo "Please install Xcode or Xcode Command Line Tools"
    exit 1
fi

swift build -c release
echo -e "${GREEN}✓ Build complete${NC}"

# Create directories
echo ""
echo -e "${YELLOW}Creating directories...${NC}"
sudo mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$LAUNCH_AGENT_DIR"
echo -e "${GREEN}✓ Directories created${NC}"

# Install the binary
echo ""
echo -e "${YELLOW}Installing server binary...${NC}"
sudo cp ".build/release/MessageBridgeServer" "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/MessageBridgeServer"
echo -e "${GREEN}✓ Server installed to $INSTALL_DIR/MessageBridgeServer${NC}"

# Generate or retrieve API key
echo ""
echo -e "${YELLOW}Setting up API key...${NC}"
API_KEY=$("$INSTALL_DIR/MessageBridgeServer" --generate-key 2>/dev/null || true)

if [[ -z "$API_KEY" ]]; then
    # Generate a random key if the command doesn't support --generate-key
    API_KEY=$(openssl rand -hex 32)
fi

# Save API key to a file (will be migrated to Keychain on first run)
echo "$API_KEY" > "$DATA_DIR/api-key"
chmod 600 "$DATA_DIR/api-key"
echo -e "${GREEN}✓ API key generated${NC}"
echo ""
echo -e "${YELLOW}Your API key is:${NC}"
echo -e "${GREEN}$API_KEY${NC}"
echo ""
echo -e "${YELLOW}Save this key - you'll need it to configure the client!${NC}"

# Install LaunchAgent
echo ""
echo -e "${YELLOW}Installing LaunchAgent...${NC}"
cp "$SCRIPT_DIR/$PLIST_NAME" "$LAUNCH_AGENT_DIR/"

# Update plist with correct paths if needed
sed -i '' "s|/usr/local/bin/MessageBridgeServer|$INSTALL_DIR/MessageBridgeServer|g" "$LAUNCH_AGENT_DIR/$PLIST_NAME"
sed -i '' "s|/usr/local/var/log/messagebridge|$LOG_DIR|g" "$LAUNCH_AGENT_DIR/$PLIST_NAME"
sed -i '' "s|/usr/local/var/messagebridge|$DATA_DIR|g" "$LAUNCH_AGENT_DIR/$PLIST_NAME"

echo -e "${GREEN}✓ LaunchAgent installed${NC}"

# Load the LaunchAgent
echo ""
echo -e "${YELLOW}Starting server...${NC}"
launchctl unload "$LAUNCH_AGENT_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT_DIR/$PLIST_NAME"
echo -e "${GREEN}✓ Server started${NC}"

# Wait for server to start
sleep 2

# Verify server is running
echo ""
echo -e "${YELLOW}Verifying server...${NC}"
if curl -s "http://localhost:8080/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Server is running!${NC}"
else
    echo -e "${RED}Warning: Server may not be running. Check logs at:${NC}"
    echo "  $LOG_DIR/server.log"
    echo "  $LOG_DIR/error.log"
fi

# Print summary
echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Server URL: http://localhost:8080"
echo "API Key: $API_KEY"
echo ""
echo "Log files:"
echo "  $LOG_DIR/server.log"
echo "  $LOG_DIR/error.log"
echo ""
echo "To manage the server:"
echo "  Stop:    launchctl unload $LAUNCH_AGENT_DIR/$PLIST_NAME"
echo "  Start:   launchctl load $LAUNCH_AGENT_DIR/$PLIST_NAME"
echo "  Restart: launchctl kickstart -k gui/\$(id -u)/$PLIST_NAME"
echo ""
echo "Next steps:"
echo "1. Install Tailscale on this Mac (see setup-tailscale.md)"
echo "2. Note your Tailscale IP address"
echo "3. Configure the client with your Tailscale IP and API key"
