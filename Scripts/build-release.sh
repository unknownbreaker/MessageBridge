#!/bin/bash
#
# MessageBridge Release Builder
# Builds server and/or client apps for release distribution.
#
# Usage:
#   ./build-release.sh              # Build both apps
#   ./build-release.sh server       # Build server only
#   ./build-release.sh client       # Build client only
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

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}MessageBridge Release Builder${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Function to parse version into components
parse_version() {
    local version="$1"
    IFS='.' read -r MAJOR MINOR PATCH <<< "$version"
    MAJOR=${MAJOR:-0}
    MINOR=${MINOR:-0}
    PATCH=${PATCH:-0}
}

# Function to sync Version.swift with VERSION file
sync_version() {
    local version_file="$1"
    local swift_file="$2"
    local app_name="$3"

    if [[ ! -f "$version_file" ]]; then
        echo -e "${RED}✗ VERSION file not found: $version_file${NC}" >&2
        return 1
    fi

    local version=$(cat "$version_file" | tr -d '[:space:]')
    parse_version "$version"

    if [[ -f "$swift_file" ]]; then
        sed -i '' "s/AppVersion(major: [0-9]*, minor: [0-9]*, patch: [0-9]*)/AppVersion(major: $MAJOR, minor: $MINOR, patch: $PATCH)/" "$swift_file"
        echo -e "${GREEN}✓ $app_name Version.swift synced to $version${NC}" >&2
    fi

    echo "$version"
}

# Create build directory
mkdir -p "$BUILD_DIR"

# Build Server
build_server() {
    echo ""
    echo -e "${YELLOW}Building MessageBridge Server...${NC}"

    # Get server version
    SERVER_VERSION=$(sync_version \
        "$PROJECT_DIR/MessageBridgeServer/VERSION" \
        "$PROJECT_DIR/MessageBridgeServer/Sources/MessageBridgeCore/Version/Version.swift" \
        "Server")

    echo -e "${YELLOW}Server version: ${SERVER_VERSION}${NC}"

    cd "$PROJECT_DIR/MessageBridgeServer"

    # Build release binary
    swift build -c release

    # Create app bundle structure
    APP_NAME="MessageBridge Server"
    SERVER_APP="$BUILD_DIR/$APP_NAME.app"
    rm -rf "$SERVER_APP"
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
    <string>${SERVER_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${SERVER_VERSION}</string>
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

    # Code sign the app with hardened runtime (required for notarization)
    SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
    if security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
        echo -e "${YELLOW}Signing server app...${NC}"
        codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$SERVER_APP"
        echo -e "${GREEN}✓ Server app signed${NC}"
    else
        echo -e "${YELLOW}Warning: No signing identity found. App will not be notarizable.${NC}"
    fi

    echo -e "${GREEN}✓ Server app built: $SERVER_APP${NC}"
}

# Build Client
build_client() {
    echo ""
    echo -e "${YELLOW}Building MessageBridge Client...${NC}"

    # Get client version
    CLIENT_VERSION=$(sync_version \
        "$PROJECT_DIR/MessageBridgeClient/VERSION" \
        "$PROJECT_DIR/MessageBridgeClient/Sources/MessageBridgeClientCore/Version/Version.swift" \
        "Client")

    echo -e "${YELLOW}Client version: ${CLIENT_VERSION}${NC}"

    cd "$PROJECT_DIR/MessageBridgeClient"

    # Build release binary
    swift build -c release

    # Create app bundle structure
    APP_NAME="MessageBridge"
    CLIENT_APP="$BUILD_DIR/$APP_NAME.app"
    rm -rf "$CLIENT_APP"
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
    <string>${CLIENT_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${CLIENT_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
    <key>NSQuitAlwaysKeepsWindows</key>
    <false/>
</dict>
</plist>
EOF

    # Code sign the app with hardened runtime (required for notarization)
    SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
    if security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
        echo -e "${YELLOW}Signing client app...${NC}"
        codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$CLIENT_APP"
        echo -e "${GREEN}✓ Client app signed${NC}"
    else
        echo -e "${YELLOW}Warning: No signing identity found. App will not be notarizable.${NC}"
    fi

    echo -e "${GREEN}✓ Client app built: $CLIENT_APP${NC}"
}

# Execute based on target
case "$BUILD_TARGET" in
    server)
        build_server
        ;;
    client)
        build_client
        ;;
    all|"")
        build_server
        build_client
        ;;
    *)
        echo -e "${RED}Unknown target: $BUILD_TARGET${NC}"
        echo "Usage: $0 [server|client|all]"
        exit 1
        ;;
esac

# Summary
echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Apps built in: $BUILD_DIR"
ls -la "$BUILD_DIR"
