#!/bin/bash
#
# MessageBridge Release Publisher
# Creates git tag and publishes GitHub release with DMG.
#
# Usage:
#   ./publish-release.sh server    # Publish server release
#   ./publish-release.sh client    # Publish client release
#
# Prerequisites:
#   - GitHub CLI (gh) installed: brew install gh
#   - Authenticated: gh auth login
#   - DMG already built via build-signed-release.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TARGET="$1"

if [[ -z "$TARGET" ]] || [[ ! "$TARGET" =~ ^(server|client)$ ]]; then
    echo -e "${RED}Usage: $0 [server|client]${NC}"
    exit 1
fi

# Check for gh CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"
    echo "Install it with: brew install gh"
    echo "Then authenticate: gh auth login"
    exit 1
fi

# Check gh auth
if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: Not authenticated with GitHub${NC}"
    echo "Run: gh auth login"
    exit 1
fi

# Get version and paths based on target
if [[ "$TARGET" == "server" ]]; then
    VERSION=$(cat "$PROJECT_DIR/MessageBridgeServer/VERSION" | tr -d '[:space:]')
    TAG="server-v$VERSION"
    APP_NAME="MessageBridge Server"
    DMG_PATH="$BUILD_DIR/MessageBridge-Server-$VERSION.dmg"
else
    VERSION=$(cat "$PROJECT_DIR/MessageBridgeClient/VERSION" | tr -d '[:space:]')
    TAG="client-v$VERSION"
    APP_NAME="MessageBridge"
    DMG_PATH="$BUILD_DIR/MessageBridge-$VERSION.dmg"
fi

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    MessageBridge Release Publisher     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Target:  $TARGET${NC}"
echo -e "${YELLOW}Version: $VERSION${NC}"
echo -e "${YELLOW}Tag:     $TAG${NC}"
echo ""

# Check DMG exists
if [[ ! -f "$DMG_PATH" ]]; then
    echo -e "${RED}Error: DMG not found at $DMG_PATH${NC}"
    echo "Run ./Scripts/build-signed-release.sh $TARGET first"
    exit 1
fi

# Check if tag already exists
if git tag -l | grep -q "^$TAG$"; then
    echo -e "${YELLOW}Tag $TAG already exists.${NC}"
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing tag..."
        git tag -d "$TAG"
        git push origin ":refs/tags/$TAG" 2>/dev/null || true
    else
        echo "Aborting."
        exit 1
    fi
fi

# Generate release notes
echo -e "${YELLOW}Generating release notes...${NC}"
RELEASE_NOTES=$(mktemp)

# Get previous tag of same type
PREV_TAG=$(git tag -l "${TARGET}-v*" --sort=-v:refname | head -1)

if [[ -n "$PREV_TAG" ]] && [[ "$PREV_TAG" != "$TAG" ]]; then
    echo "## What's Changed" > "$RELEASE_NOTES"
    echo "" >> "$RELEASE_NOTES"

    if [[ "$TARGET" == "server" ]]; then
        git log --pretty=format:"* %s (%h)" "$PREV_TAG"..HEAD -- MessageBridgeServer/ Scripts/ >> "$RELEASE_NOTES" 2>/dev/null || true
    else
        git log --pretty=format:"* %s (%h)" "$PREV_TAG"..HEAD -- MessageBridgeClient/ Scripts/ >> "$RELEASE_NOTES" 2>/dev/null || true
    fi
else
    echo "## $APP_NAME v$VERSION" > "$RELEASE_NOTES"
    echo "" >> "$RELEASE_NOTES"
    echo "Initial release." >> "$RELEASE_NOTES"
fi

echo "" >> "$RELEASE_NOTES"
echo "---" >> "$RELEASE_NOTES"
echo "✅ **Signed and Notarized** - This release is code signed and notarized by Apple." >> "$RELEASE_NOTES"

echo -e "${GREEN}Release notes:${NC}"
cat "$RELEASE_NOTES"
echo ""

# Confirm
read -p "Create tag and publish release? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    rm "$RELEASE_NOTES"
    echo "Aborting."
    exit 1
fi

# Create and push tag
echo ""
echo -e "${YELLOW}Creating tag $TAG...${NC}"
git tag "$TAG"
git push origin "$TAG"

# Create GitHub release
echo ""
echo -e "${YELLOW}Creating GitHub release...${NC}"
gh release create "$TAG" \
    --title "$APP_NAME v$VERSION" \
    --notes-file "$RELEASE_NOTES" \
    "$DMG_PATH"

# Cleanup
rm "$RELEASE_NOTES"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Release published!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "View at: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/$TAG"
