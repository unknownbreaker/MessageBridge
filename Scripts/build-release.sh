#!/bin/bash
#
# MessageBridge Release Builder
# Builds both server and client apps for release distribution.
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

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}MessageBridge Release Builder${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Get version from VERSION file or git tag
VERSION=$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "0.0.0")
echo -e "${YELLOW}Building version: ${VERSION}${NC}"
echo ""

# Create build directory
mkdir -p "$BUILD_DIR"
rm -rf "$BUILD_DIR"/*

# Build Server
echo -e "${YELLOW}Building MessageBridge Server...${NC}"
cd "$PROJECT_DIR/MessageBridgeServer"

# Build release binary
swift build -c release

# Create app bundle structure
APP_NAME="MessageBridge Server"
SERVER_APP="$BUILD_DIR/$APP_NAME.app"
mkdir -p "$SERVER_APP/Contents/MacOS"
mkdir -p "$SERVER_APP/Contents/Resources"

# Copy binary
cp ".build/release/MessageBridgeServer" "$SERVER_APP/Contents/MacOS/MessageBridge Server"

# Copy icon
if [[ -f "$PROJECT_DIR/Assets/AppIcon-Server.icns" ]]; then
    cp "$PROJECT_DIR/Assets/AppIcon-Server.icns" "$SERVER_APP/Contents/Resources/AppIcon.icns"
    echo -e "${GREEN}✓ Server icon copied${NC}"
fi

# Create Info.plist
cat > "$SERVER_APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MessageBridge Server</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.messagebridge.server</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MessageBridge Server</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>MessageBridge needs to send messages via Messages.app</string>
</dict>
</plist>
EOF

echo -e "${GREEN}✓ Server app built: $SERVER_APP${NC}"

# Build Client
echo ""
echo -e "${YELLOW}Building MessageBridge Client...${NC}"
cd "$PROJECT_DIR/MessageBridgeClient"

# Build release binary
swift build -c release

# Create app bundle structure
APP_NAME="MessageBridge"
CLIENT_APP="$BUILD_DIR/$APP_NAME.app"
mkdir -p "$CLIENT_APP/Contents/MacOS"
mkdir -p "$CLIENT_APP/Contents/Resources"

# Copy binary
cp ".build/release/MessageBridgeClient" "$CLIENT_APP/Contents/MacOS/MessageBridge"

# Copy icon
if [[ -f "$PROJECT_DIR/Assets/AppIcon-Client.icns" ]]; then
    cp "$PROJECT_DIR/Assets/AppIcon-Client.icns" "$CLIENT_APP/Contents/Resources/AppIcon.icns"
    echo -e "${GREEN}✓ Client icon copied${NC}"
fi

# Create Info.plist
cat > "$CLIENT_APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MessageBridge</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.messagebridge.client</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MessageBridge</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
EOF

echo -e "${GREEN}✓ Client app built: $CLIENT_APP${NC}"

# Summary
echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Apps built in: $BUILD_DIR"
ls -la "$BUILD_DIR"
