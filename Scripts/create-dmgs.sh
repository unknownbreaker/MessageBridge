#!/bin/bash
#
# MessageBridge DMG Creator
# Creates DMG installers for both server and client apps.
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

# Get version from argument or VERSION file
VERSION=${1:-$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "0.0.0")}

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}MessageBridge DMG Creator${NC}"
echo -e "${BLUE}================================${NC}"
echo ""
echo -e "${YELLOW}Creating DMGs for version: ${VERSION}${NC}"
echo ""

# Check if apps exist
if [[ ! -d "$BUILD_DIR/MessageBridge Server.app" ]]; then
    echo -e "${RED}Error: Server app not found. Run build-release.sh first.${NC}"
    exit 1
fi

if [[ ! -d "$BUILD_DIR/MessageBridge.app" ]]; then
    echo -e "${RED}Error: Client app not found. Run build-release.sh first.${NC}"
    exit 1
fi

# Create Server DMG
echo -e "${YELLOW}Creating Server DMG...${NC}"
SERVER_DMG_NAME="MessageBridge-Server-${VERSION}.dmg"
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

# Create Client DMG
echo ""
echo -e "${YELLOW}Creating Client DMG...${NC}"
CLIENT_DMG_NAME="MessageBridge-${VERSION}.dmg"
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

# Summary
echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}DMG Creation Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "DMGs created:"
ls -la "$BUILD_DIR"/*.dmg
