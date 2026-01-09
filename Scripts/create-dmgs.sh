#!/bin/bash
#
# MessageBridge DMG Creator
# Creates DMG installers for server and/or client apps.
#
# Usage:
#   ./create-dmgs.sh                    # Create both DMGs (reads from VERSION files)
#   ./create-dmgs.sh server [version]   # Create server DMG only
#   ./create-dmgs.sh client [version]   # Create client DMG only
#   ./create-dmgs.sh all [version]      # Create both DMGs with specified version
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

# Parse arguments
BUILD_TARGET="${1:-all}"
VERSION_ARG="${2:-}"

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}MessageBridge DMG Creator${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Function to create server DMG
create_server_dmg() {
    local version="${1:-$(cat "$PROJECT_DIR/MessageBridgeServer/VERSION" 2>/dev/null | tr -d '[:space:]')}"
    version="${version:-0.0.0}"

    echo -e "${YELLOW}Creating Server DMG (v${version})...${NC}"

    if [[ ! -d "$BUILD_DIR/MessageBridge Server.app" ]]; then
        echo -e "${RED}Error: Server app not found. Run build-release.sh server first.${NC}"
        return 1
    fi

    SERVER_DMG_NAME="MessageBridge-Server-${version}.dmg"
    SERVER_DMG_PATH="$BUILD_DIR/$SERVER_DMG_NAME"

    # Create temporary directory for DMG contents
    SERVER_DMG_TEMP="$BUILD_DIR/dmg-server-temp"
    rm -rf "$SERVER_DMG_TEMP"
    mkdir -p "$SERVER_DMG_TEMP"

    # Copy app to temp directory
    cp -R "$BUILD_DIR/MessageBridge Server.app" "$SERVER_DMG_TEMP/"

    # Create symlink to Applications
    ln -s /Applications "$SERVER_DMG_TEMP/Applications"

    # Create DMG
    hdiutil create -volname "MessageBridge Server" \
        -srcfolder "$SERVER_DMG_TEMP" \
        -ov -format UDZO \
        "$SERVER_DMG_PATH"

    # Cleanup
    rm -rf "$SERVER_DMG_TEMP"

    echo -e "${GREEN}✓ Server DMG created: $SERVER_DMG_PATH${NC}"
}

# Function to create client DMG
create_client_dmg() {
    local version="${1:-$(cat "$PROJECT_DIR/MessageBridgeClient/VERSION" 2>/dev/null | tr -d '[:space:]')}"
    version="${version:-0.0.0}"

    echo -e "${YELLOW}Creating Client DMG (v${version})...${NC}"

    if [[ ! -d "$BUILD_DIR/MessageBridge.app" ]]; then
        echo -e "${RED}Error: Client app not found. Run build-release.sh client first.${NC}"
        return 1
    fi

    CLIENT_DMG_NAME="MessageBridge-${version}.dmg"
    CLIENT_DMG_PATH="$BUILD_DIR/$CLIENT_DMG_NAME"

    # Create temporary directory for DMG contents
    CLIENT_DMG_TEMP="$BUILD_DIR/dmg-client-temp"
    rm -rf "$CLIENT_DMG_TEMP"
    mkdir -p "$CLIENT_DMG_TEMP"

    # Copy app to temp directory
    cp -R "$BUILD_DIR/MessageBridge.app" "$CLIENT_DMG_TEMP/"

    # Create symlink to Applications
    ln -s /Applications "$CLIENT_DMG_TEMP/Applications"

    # Create DMG
    hdiutil create -volname "MessageBridge" \
        -srcfolder "$CLIENT_DMG_TEMP" \
        -ov -format UDZO \
        "$CLIENT_DMG_PATH"

    # Cleanup
    rm -rf "$CLIENT_DMG_TEMP"

    echo -e "${GREEN}✓ Client DMG created: $CLIENT_DMG_PATH${NC}"
}

# Execute based on target
case "$BUILD_TARGET" in
    server)
        create_server_dmg "$VERSION_ARG"
        ;;
    client)
        create_client_dmg "$VERSION_ARG"
        ;;
    all|"")
        create_server_dmg "$VERSION_ARG"
        echo ""
        create_client_dmg "$VERSION_ARG"
        ;;
    *)
        echo -e "${RED}Unknown target: $BUILD_TARGET${NC}"
        echo "Usage: $0 [server|client|all] [version]"
        exit 1
        ;;
esac

# Summary
echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}DMG Creation Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "DMGs created:"
ls -la "$BUILD_DIR"/*.dmg 2>/dev/null || echo "No DMG files found"
