#!/bin/bash
#
# MessageBridge Changelog Generator
# Generates release notes from conventional commits since the last tag.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Get the current tag (or HEAD if not on a tag)
CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "HEAD")

# Get the previous tag
PREVIOUS_TAG=$(git describe --tags --abbrev=0 "$CURRENT_TAG^" 2>/dev/null || echo "")

# Get version from VERSION file
VERSION=$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "0.0.0")

# Header
echo "# MessageBridge v${VERSION}"
echo ""
echo "Released on $(date +%Y-%m-%d)"
echo ""

# If there's a previous tag, get commits since then
if [[ -n "$PREVIOUS_TAG" ]]; then
    RANGE="${PREVIOUS_TAG}..${CURRENT_TAG}"
else
    # First release, get all commits
    RANGE="$CURRENT_TAG"
fi

# Function to extract commits by type
extract_commits() {
    local type=$1
    local header=$2

    local commits=$(git log --pretty=format:"%s" "$RANGE" 2>/dev/null | grep "^${type}" || true)

    if [[ -n "$commits" ]]; then
        echo "## $header"
        echo ""
        echo "$commits" | while read -r line; do
            # Remove the type prefix and format as list item
            local message=$(echo "$line" | sed "s/^${type}[^:]*: //")
            echo "- $message"
        done
        echo ""
    fi
}

# Extract different types of changes
extract_commits "feat" "New Features"
extract_commits "fix" "Bug Fixes"
extract_commits "perf" "Performance Improvements"
extract_commits "refactor" "Refactoring"
extract_commits "docs" "Documentation"
extract_commits "chore" "Maintenance"

# Check for breaking changes (look for "BREAKING CHANGE:" followed by content)
BREAKING=$(git log --pretty=format:"%b" "$RANGE" 2>/dev/null | grep -i "^BREAKING CHANGE:" | sed 's/^BREAKING CHANGE: *//i' || true)
if [[ -n "$BREAKING" ]]; then
    echo "## Breaking Changes"
    echo ""
    echo "$BREAKING" | while read -r line; do
        if [[ -n "$line" && "$line" != *"BREAKING"* ]]; then
            echo "- $line"
        fi
    done
    echo ""
fi

# Installation instructions
echo "## Installation"
echo ""
echo "### Server (Home Mac)"
echo "1. Download \`MessageBridge-Server-${VERSION}.dmg\`"
echo "2. Open the DMG and drag the app to Applications"
echo "3. Launch MessageBridge Server from Applications"
echo "4. Grant Full Disk Access when prompted"
echo ""
echo "### Client (Work Mac)"
echo "1. Download \`MessageBridge-${VERSION}.dmg\`"
echo "2. Open the DMG and drag the app to Applications"
echo "3. Launch MessageBridge and configure your server connection"
echo ""
echo "For detailed setup instructions, see the [README](https://github.com/unknownbreaker/MessageBridge)."
