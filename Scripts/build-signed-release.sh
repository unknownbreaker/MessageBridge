#!/bin/bash
#
# MessageBridge Signed Release Builder
# Builds, signs, notarizes, and creates DMG for distribution.
#
# Usage:
#   ./build-signed-release.sh server    # Build signed server
#   ./build-signed-release.sh client    # Build signed client
#   ./build-signed-release.sh all       # Build both
#
# Required environment variables (set these first or create .env file):
#   DEVELOPER_ID_APPLICATION  - e.g., "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID                  - Your Apple ID email
#   APPLE_ID_PASSWORD         - App-specific password
#   APPLE_TEAM_ID             - Your 10-character Team ID
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load .env file if it exists
if [[ -f "$PROJECT_DIR/.env" ]]; then
    echo -e "${YELLOW}Loading environment from .env file...${NC}"
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# Check required environment variables
check_env() {
    local missing=0
    for var in DEVELOPER_ID_APPLICATION APPLE_ID APPLE_ID_PASSWORD APPLE_TEAM_ID; do
        if [[ -z "${!var}" ]]; then
            echo -e "${RED}Error: $var is not set${NC}"
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then
        echo ""
        echo "Set these environment variables or create a .env file in the project root:"
        echo ""
        echo '  DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"'
        echo '  APPLE_ID="your@email.com"'
        echo '  APPLE_ID_PASSWORD="xxxx-xxxx-xxxx-xxxx"'
        echo '  APPLE_TEAM_ID="XXXXXXXXXX"'
        echo ""
        exit 1
    fi
}

build_and_sign() {
    local target="$1"
    local app_path=""
    local version=""

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Building $target${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # Build
    "$SCRIPT_DIR/build-release.sh" "$target"

    # Determine app path and version
    if [[ "$target" == "server" ]]; then
        app_path="$PROJECT_DIR/build/MessageBridge Server.app"
        version=$(cat "$PROJECT_DIR/MessageBridgeServer/VERSION" | tr -d '[:space:]')
    else
        app_path="$PROJECT_DIR/build/MessageBridge.app"
        version=$(cat "$PROJECT_DIR/MessageBridgeClient/VERSION" | tr -d '[:space:]')
    fi

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Signing and Notarizing $target v$version${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # Sign and notarize
    "$SCRIPT_DIR/codesign-notarize.sh" "$app_path"

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Creating DMG${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # Create DMG
    "$SCRIPT_DIR/create-dmgs.sh" "$target" "$version"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ $target v$version complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Parse arguments
TARGET="${1:-all}"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  MessageBridge Signed Release Builder  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

check_env

case "$TARGET" in
    server)
        build_and_sign server
        ;;
    client)
        build_and_sign client
        ;;
    all)
        build_and_sign server
        echo ""
        build_and_sign client
        ;;
    *)
        echo -e "${RED}Unknown target: $TARGET${NC}"
        echo "Usage: $0 [server|client|all]"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}All done! DMGs are in: $PROJECT_DIR/build/${NC}"
ls -la "$PROJECT_DIR/build/"*.dmg
