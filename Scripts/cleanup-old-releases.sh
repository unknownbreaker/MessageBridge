#!/bin/bash
#
# MessageBridge Old Release Cleanup
# One-time script to delete all existing GitHub releases and git tags.
#
# This prepares the repo for the new unified date-based release strategy.
#
# Usage:
#   ./Scripts/cleanup-old-releases.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$PROJECT_DIR"

# Preflight
if ! command -v gh &>/dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"
    exit 1
fi

if ! gh auth status &>/dev/null 2>&1; then
    echo -e "${RED}Error: Not authenticated with GitHub${NC}"
    echo "Run: gh auth login"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  MessageBridge Release Cleanup         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Count what we're about to delete
RELEASES=$(gh release list --limit 100 --json tagName -q '.[].tagName')
RELEASE_COUNT=$(echo "$RELEASES" | grep -c . || true)

TAGS=$(git tag -l)
TAG_COUNT=$(echo "$TAGS" | grep -c . || true)

if [[ "$RELEASE_COUNT" -eq 0 ]] && [[ "$TAG_COUNT" -eq 0 ]]; then
    echo -e "${GREEN}Nothing to clean up. No releases or tags found.${NC}"
    exit 0
fi

echo -e "${YELLOW}This will delete:${NC}"
echo -e "  ${RED}$RELEASE_COUNT GitHub releases${NC}"
echo -e "  ${RED}$TAG_COUNT git tags (local + remote)${NC}"
echo ""
echo -e "${RED}This action is irreversible.${NC}"
echo ""
read -p "Type 'delete all' to confirm: " CONFIRM
echo

if [[ "$CONFIRM" != "delete all" ]]; then
    echo "Aborting."
    exit 1
fi

# Delete GitHub releases first (they reference tags)
if [[ "$RELEASE_COUNT" -gt 0 ]]; then
    echo -e "${YELLOW}Deleting $RELEASE_COUNT GitHub releases...${NC}"
    echo "$RELEASES" | while read -r tag; do
        echo "  Deleting release: $tag"
        gh release delete "$tag" --yes --cleanup-tag 2>/dev/null || true
    done
    echo -e "${GREEN}Releases deleted.${NC}"
    echo ""
fi

# Delete remaining remote tags (some may not have had releases)
if [[ "$TAG_COUNT" -gt 0 ]]; then
    echo -e "${YELLOW}Deleting remote tags...${NC}"
    echo "$TAGS" | while read -r tag; do
        echo "  Deleting remote tag: $tag"
        git push origin ":refs/tags/$tag" 2>/dev/null || true
    done
    echo -e "${GREEN}Remote tags deleted.${NC}"
    echo ""

    echo -e "${YELLOW}Deleting local tags...${NC}"
    git tag -l | xargs git tag -d
    echo -e "${GREEN}Local tags deleted.${NC}"
    echo ""
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Verify:"
echo "  gh release list        # should be empty"
echo "  git tag -l             # should be empty"
