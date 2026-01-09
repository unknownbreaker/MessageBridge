#!/bin/bash
#
# MessageBridge Client Packager
# This script builds and packages the MessageBridge client as a DMG.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENT_DIR="$PROJECT_DIR/MessageBridgeClient"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="MessageBridge"
DMG_NAME="MessageBridge-Installer"
VERSION="${1:-1.0.0}"

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}MessageBridge Client Packager${NC}"
echo -e "${GREEN}Version: $VERSION${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}Error: This script only runs on macOS${NC}"
    exit 1
fi

# Clean previous builds
echo -e "${YELLOW}Cleaning previous builds...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
echo -e "${GREEN}✓ Clean complete${NC}"

# Build the client
echo ""
echo -e "${YELLOW}Building MessageBridge Client...${NC}"
cd "$CLIENT_DIR"

# Build release binary
swift build -c release

echo -e "${GREEN}✓ Build complete${NC}"

# Create app bundle structure
echo ""
echo -e "${YELLOW}Creating app bundle...${NC}"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp ".build/release/MessageBridgeClient" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.messagebridge.client</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.social-networking</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo -e "${GREEN}✓ App bundle created${NC}"

# Code sign (ad-hoc for development)
echo ""
echo -e "${YELLOW}Code signing app bundle...${NC}"
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
echo -e "${GREEN}✓ Code signed (ad-hoc)${NC}"

# Create DMG
echo ""
echo -e "${YELLOW}Creating DMG installer...${NC}"

DMG_TEMP="$BUILD_DIR/dmg_temp"
DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"

mkdir -p "$DMG_TEMP"
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create Applications symlink
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

# Clean up temp
rm -rf "$DMG_TEMP"

echo -e "${GREEN}✓ DMG created${NC}"

# Print summary
echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Packaging Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Output files:"
echo "  App Bundle: $APP_BUNDLE"
echo "  DMG: $DMG_PATH"
echo ""
echo "To install:"
echo "1. Open the DMG file"
echo "2. Drag MessageBridge to Applications"
echo "3. Launch MessageBridge from Applications"
echo "4. Enter your server URL and API key"
echo ""
echo "Note: For distribution, you should:"
echo "1. Sign with a Developer ID certificate"
echo "2. Notarize the app with Apple"
echo ""

# Print DMG size
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "DMG Size: $DMG_SIZE"
