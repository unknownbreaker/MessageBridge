#!/bin/bash
#
# MessageBridge Code Signing and Notarization Script
# Signs and notarizes macOS apps for distribution.
#
# Usage:
#   ./codesign-notarize.sh <app_path>
#
# Required environment variables:
#   DEVELOPER_ID_APPLICATION  - Name of signing certificate (e.g., "Developer ID Application: Your Name (TEAMID)")
#   APPLE_ID                  - Your Apple ID email
#   APPLE_ID_PASSWORD         - App-specific password (NOT your Apple ID password)
#   APPLE_TEAM_ID             - Your Apple Developer Team ID
#
# To create an app-specific password:
#   1. Go to https://appleid.apple.com/account/manage
#   2. Sign in and go to "App-Specific Passwords"
#   3. Generate a new password for "MessageBridge Notarization"
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

APP_PATH="$1"

if [[ -z "$APP_PATH" ]]; then
    echo -e "${RED}Usage: $0 <app_path>${NC}"
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo -e "${RED}Error: App not found at $APP_PATH${NC}"
    exit 1
fi

APP_NAME=$(basename "$APP_PATH")

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Code Signing & Notarization${NC}"
echo -e "${BLUE}================================${NC}"
echo ""
echo -e "${YELLOW}App: $APP_NAME${NC}"
echo ""

# Check required environment variables
if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
    echo -e "${RED}Error: DEVELOPER_ID_APPLICATION environment variable not set${NC}"
    echo "Set it to your signing identity, e.g.:"
    echo '  export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"'
    exit 1
fi

if [[ -z "$APPLE_ID" ]]; then
    echo -e "${RED}Error: APPLE_ID environment variable not set${NC}"
    exit 1
fi

if [[ -z "$APPLE_ID_PASSWORD" ]]; then
    echo -e "${RED}Error: APPLE_ID_PASSWORD environment variable not set${NC}"
    echo "This should be an app-specific password, not your Apple ID password."
    echo "Create one at: https://appleid.apple.com/account/manage"
    exit 1
fi

if [[ -z "$APPLE_TEAM_ID" ]]; then
    echo -e "${RED}Error: APPLE_TEAM_ID environment variable not set${NC}"
    exit 1
fi

# Step 1: Code sign the app
echo -e "${YELLOW}Step 1: Code signing...${NC}"

# Sign all nested components first (frameworks, helpers, etc.)
find "$APP_PATH" -type f \( -name "*.dylib" -o -name "*.framework" \) -print0 | while IFS= read -r -d '' file; do
    echo "  Signing: $(basename "$file")"
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$file" 2>/dev/null || true
done

# Sign the main executable
EXECUTABLE=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleExecutable)
echo "  Signing executable: $EXECUTABLE"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH/Contents/MacOS/$EXECUTABLE"

# Sign the entire app bundle
echo "  Signing app bundle..."
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"

# Verify signature
echo -e "${YELLOW}Verifying signature...${NC}"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo -e "${GREEN}✓ Code signing complete${NC}"
echo ""

# Step 2: Create ZIP for notarization
echo -e "${YELLOW}Step 2: Creating ZIP for notarization...${NC}"
ZIP_PATH="${APP_PATH%.app}.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo -e "${GREEN}✓ ZIP created: $ZIP_PATH${NC}"
echo ""

# Step 3: Submit for notarization
echo -e "${YELLOW}Step 3: Submitting for notarization...${NC}"
echo "  This may take a few minutes..."

NOTARIZE_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_ID_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait \
    2>&1)

echo "$NOTARIZE_OUTPUT"

# Check if notarization succeeded
if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
    echo -e "${GREEN}✓ Notarization successful${NC}"
else
    echo -e "${RED}✗ Notarization failed${NC}"
    # Get submission ID and fetch log
    SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    if [[ -n "$SUBMISSION_ID" ]]; then
        echo -e "${YELLOW}Fetching notarization log...${NC}"
        xcrun notarytool log "$SUBMISSION_ID" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_ID_PASSWORD" \
            --team-id "$APPLE_TEAM_ID"
    fi
    rm -f "$ZIP_PATH"
    exit 1
fi
echo ""

# Step 4: Staple the notarization ticket
echo -e "${YELLOW}Step 4: Stapling notarization ticket...${NC}"
xcrun stapler staple "$APP_PATH"
echo -e "${GREEN}✓ Stapling complete${NC}"
echo ""

# Cleanup
rm -f "$ZIP_PATH"

# Final verification
echo -e "${YELLOW}Final verification...${NC}"
spctl --assess --type exec --verbose "$APP_PATH"
echo ""

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}✓ App signed and notarized!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "The app can now be distributed and will run on any Mac."
