#!/bin/bash
#
# MessageBridge Unified Release Publisher
# Builds, signs, and publishes a single date-based release with both DMGs.
#
# Usage:
#   ./Scripts/publish-release.sh             # Full release
#   ./Scripts/publish-release.sh --dry-run   # Preview without executing
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated
#   - Code signing env vars set (or .env file)
#   - Clean working tree
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; echo "Usage: $0 [--dry-run]"; exit 1 ;;
    esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────

log_step() { echo -e "\n${BLUE}▸ $1${NC}"; }
log_ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
log_warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
log_err()  { echo -e "${RED}  ✗ $1${NC}"; }
log_dry()  { echo -e "${YELLOW}  [dry-run] $1${NC}"; }

# Read a VERSION file, trimming whitespace
read_version() { tr -d '[:space:]' < "$1"; }

# Parse "X.Y.Z" into components, sets VMAJOR VMINOR VPATCH
parse_version() {
    IFS='.' read -r VMAJOR VMINOR VPATCH <<< "$1"
}

# ─── Preflight ────────────────────────────────────────────────────────────────

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  MessageBridge Unified Release         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
if $DRY_RUN; then
    echo -e "${YELLOW}         *** DRY RUN MODE ***${NC}"
fi
echo ""

cd "$PROJECT_DIR"

log_step "Preflight checks"

if ! command -v gh &>/dev/null; then
    log_err "GitHub CLI (gh) is not installed"; exit 1
fi
if ! gh auth status &>/dev/null 2>&1; then
    log_err "Not authenticated with GitHub — run: gh auth login"; exit 1
fi
log_ok "GitHub CLI authenticated"

if [[ -n "$(git status --porcelain)" ]]; then
    log_err "Working tree is not clean. Commit or stash changes first."
    git status --short
    exit 1
fi
log_ok "Working tree clean"

# Check signing env vars (allow dry-run without them)
if ! $DRY_RUN; then
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        set -a; source "$PROJECT_DIR/.env"; set +a
    fi
    for var in DEVELOPER_ID_APPLICATION APPLE_ID APPLE_ID_PASSWORD APPLE_TEAM_ID; do
        if [[ -z "${!var:-}" ]]; then
            log_err "$var is not set"; exit 1
        fi
    done
    log_ok "Signing environment configured"
fi

# ─── Version Bump Detection ──────────────────────────────────────────────────

# Determine bump type from conventional commits
# Args: $1=from_tag (may be empty), $2=directory
# Returns via stdout: "major", "minor", "patch", or "none"
detect_bump() {
    local from_tag="$1"
    local dir="$2"
    local range_arg=""

    if [[ -n "$from_tag" ]]; then
        range_arg="${from_tag}..HEAD"
    fi

    local hashes
    if [[ -n "$range_arg" ]]; then
        hashes=$(git log --pretty=format:"%H" "$range_arg" -- "$dir" 2>/dev/null || true)
    else
        hashes=$(git log --pretty=format:"%H" -- "$dir" 2>/dev/null || true)
    fi

    if [[ -z "$hashes" ]]; then
        echo "none"
        return
    fi

    local bump="none"

    while IFS= read -r hash; do
        [[ -z "$hash" ]] && continue
        local subject body
        subject=$(git log -1 --pretty=format:"%s" "$hash")
        body=$(git log -1 --pretty=format:"%b" "$hash")

        # Major: BREAKING CHANGE in body or !: in subject
        if echo "$subject" | grep -qE '^[a-z]+(\([^)]*\))?!:'; then
            bump="major"
            break
        fi
        if echo "$body" | grep -qi "^BREAKING CHANGE:"; then
            bump="major"
            break
        fi

        # Minor: feat: or feat(scope):
        if echo "$subject" | grep -qE '^feat(\([^)]*\))?:'; then
            [[ "$bump" != "major" ]] && bump="minor"
        fi

        # Patch: fix: or fix(scope): or perf: or perf(scope):
        if echo "$subject" | grep -qE '^(fix|perf)(\([^)]*\))?:'; then
            [[ "$bump" == "none" ]] && bump="patch"
        fi
    done <<< "$hashes"

    echo "$bump"
}

# Apply bump to version string
# Args: $1=current version, $2=bump type
# Returns: new version string
apply_bump() {
    local version="$1"
    local bump="$2"
    parse_version "$version"

    case "$bump" in
        major) echo "$((VMAJOR + 1)).0.0" ;;
        minor) echo "${VMAJOR}.$((VMINOR + 1)).0" ;;
        patch) echo "${VMAJOR}.${VMINOR}.$((VPATCH + 1))" ;;
        *) echo "$version" ;;
    esac
}

# Update Version.swift to match version string
# Args: $1=path to Version.swift, $2=new version string
sync_version_swift() {
    local swift_file="$1"
    local version="$2"
    parse_version "$version"

    if [[ ! -f "$swift_file" ]]; then
        log_warn "Version.swift not found at $swift_file — skipping"
        return
    fi

    sed -i '' -E "s/AppVersion\(major: [0-9]+, minor: [0-9]+, patch: [0-9]+\)/AppVersion(major: ${VMAJOR}, minor: ${VMINOR}, patch: ${VPATCH})/" "$swift_file"
}

log_step "Detecting version bumps"

# Find latest component tags
find_latest_tag() {
    git tag -l "${1}-v*" --sort=-v:refname | head -1
}

SERVER_TAG=$(find_latest_tag "server")
CLIENT_TAG=$(find_latest_tag "client")

SERVER_OLD=$(read_version "$PROJECT_DIR/Server/VERSION")
CLIENT_OLD=$(read_version "$PROJECT_DIR/Client/VERSION")

SERVER_BUMP=$(detect_bump "$SERVER_TAG" "Server")
CLIENT_BUMP=$(detect_bump "$CLIENT_TAG" "Client")

SERVER_NEW="$SERVER_OLD"
CLIENT_NEW="$CLIENT_OLD"

if [[ "$SERVER_BUMP" != "none" ]]; then
    SERVER_NEW=$(apply_bump "$SERVER_OLD" "$SERVER_BUMP")
fi
if [[ "$CLIENT_BUMP" != "none" ]]; then
    CLIENT_NEW=$(apply_bump "$CLIENT_OLD" "$CLIENT_BUMP")
fi

echo -e "  Server: v${SERVER_OLD} → v${SERVER_NEW} (${SERVER_BUMP} bump)"
echo -e "  Client: v${CLIENT_OLD} → v${CLIENT_NEW} (${CLIENT_BUMP} bump)"

if [[ "$SERVER_NEW" == "$SERVER_OLD" ]] && [[ "$CLIENT_NEW" == "$CLIENT_OLD" ]]; then
    log_warn "No version changes detected. Nothing to release."
    exit 0
fi

# ─── Update VERSION files + Version.swift ─────────────────────────────────────

SERVER_VERSION_BUMPED=false
CLIENT_VERSION_BUMPED=false

if [[ "$SERVER_NEW" != "$SERVER_OLD" ]]; then
    SERVER_VERSION_BUMPED=true
    if $DRY_RUN; then
        log_dry "Would update server VERSION: $SERVER_OLD → $SERVER_NEW"
        log_dry "Would update server Version.swift"
    else
        log_step "Bumping server to v$SERVER_NEW"
        echo "$SERVER_NEW" > "$PROJECT_DIR/Server/VERSION"
        sync_version_swift "$PROJECT_DIR/Server/Sources/MessageBridgeCore/Version/Version.swift" "$SERVER_NEW"
        log_ok "Server VERSION and Version.swift updated"
    fi
fi

if [[ "$CLIENT_NEW" != "$CLIENT_OLD" ]]; then
    CLIENT_VERSION_BUMPED=true
    if $DRY_RUN; then
        log_dry "Would update client VERSION: $CLIENT_OLD → $CLIENT_NEW"
        log_dry "Would update client Version.swift"
    else
        log_step "Bumping client to v$CLIENT_NEW"
        echo "$CLIENT_NEW" > "$PROJECT_DIR/Client/VERSION"
        sync_version_swift "$PROJECT_DIR/Client/Sources/MessageBridgeClientCore/Version/Version.swift" "$CLIENT_NEW"
        log_ok "Client VERSION and Version.swift updated"
    fi
fi

# ─── Commit version bumps ─────────────────────────────────────────────────────

COMMIT_MSG="chore: bump"
parts=()
if $SERVER_VERSION_BUMPED; then parts+=("server to v$SERVER_NEW"); fi
if $CLIENT_VERSION_BUMPED; then parts+=("client to v$CLIENT_NEW"); fi
COMMIT_MSG="chore: bump $(printf '%s' "${parts[0]}"; for p in "${parts[@]:1}"; do printf ', %s' "$p"; done)"

if $DRY_RUN; then
    log_dry "Would commit: $COMMIT_MSG"
else
    log_step "Committing version bumps"
    git add \
        "$PROJECT_DIR/Server/VERSION" \
        "$PROJECT_DIR/Client/VERSION" \
        "$PROJECT_DIR/Server/Sources/MessageBridgeCore/Version/Version.swift" \
        "$PROJECT_DIR/Client/Sources/MessageBridgeClientCore/Version/Version.swift" \
        2>/dev/null || true
    git commit -m "$COMMIT_MSG"
    log_ok "Committed: $COMMIT_MSG"
fi

# ─── Build ────────────────────────────────────────────────────────────────────

if $DRY_RUN; then
    log_dry "Would run: build-signed-release.sh all"
else
    log_step "Building, signing, and creating DMGs"
    "$SCRIPT_DIR/build-signed-release.sh" all
    log_ok "Build complete"
fi

# ─── Generate changelog ──────────────────────────────────────────────────────

log_step "Generating changelog"

# Pass the old tags so the changelog covers the right commit range
CHANGELOG_ARGS=()
if [[ -n "$SERVER_TAG" ]]; then
    CHANGELOG_ARGS+=(--server-from "$SERVER_TAG")
fi
if [[ -n "$CLIENT_TAG" ]]; then
    CHANGELOG_ARGS+=(--client-from "$CLIENT_TAG")
fi

CHANGELOG=$("$SCRIPT_DIR/generate-changelog.sh" "${CHANGELOG_ARGS[@]}")
echo "$CHANGELOG"

# ─── Determine release tag ───────────────────────────────────────────────────

log_step "Determining release tag"

TODAY=$(date +%Y-%m-%d)
RELEASE_TAG="release/${TODAY}"

# Check for same-day re-releases
SUFFIX=1
while git tag -l | grep -q "^${RELEASE_TAG}$"; do
    SUFFIX=$((SUFFIX + 1))
    RELEASE_TAG="release/${TODAY}.${SUFFIX}"
done

RELEASE_TITLE="$TODAY"
if [[ "$SUFFIX" -gt 1 ]]; then
    RELEASE_TITLE="${TODAY}.${SUFFIX}"
fi

echo -e "  Release tag: ${BOLD}${RELEASE_TAG}${NC}"
echo -e "  Release title: ${BOLD}${RELEASE_TITLE}${NC}"

# ─── Create tags ──────────────────────────────────────────────────────────────

log_step "Creating tags"

COMPONENT_TAGS=()
if $SERVER_VERSION_BUMPED; then
    COMPONENT_TAGS+=("server-v$SERVER_NEW")
fi
if $CLIENT_VERSION_BUMPED; then
    COMPONENT_TAGS+=("client-v$CLIENT_NEW")
fi

if $DRY_RUN; then
    for tag in "${COMPONENT_TAGS[@]}"; do
        log_dry "Would create component tag: $tag"
    done
    log_dry "Would create release tag: $RELEASE_TAG"
    log_dry "Would push commit + tags"
else
    for tag in "${COMPONENT_TAGS[@]}"; do
        git tag "$tag"
        log_ok "Created tag: $tag"
    done
    git tag "$RELEASE_TAG"
    log_ok "Created tag: $RELEASE_TAG"

    # Push commit + all tags in one go
    git push origin HEAD --tags
    log_ok "Pushed commit and tags"
fi

# ─── Create GitHub release ────────────────────────────────────────────────────

log_step "Creating GitHub release"

SERVER_VERSION=$(read_version "$PROJECT_DIR/Server/VERSION")
CLIENT_VERSION=$(read_version "$PROJECT_DIR/Client/VERSION")

SERVER_DMG="$BUILD_DIR/MessageBridgeServer-${SERVER_VERSION}.dmg"
CLIENT_DMG="$BUILD_DIR/MessageBridgeClient-${CLIENT_VERSION}.dmg"

if $DRY_RUN; then
    log_dry "Would create GitHub release '$RELEASE_TITLE' with tag $RELEASE_TAG"
    log_dry "Would attach: $(basename "$SERVER_DMG")"
    log_dry "Would attach: $(basename "$CLIENT_DMG")"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Dry run complete — no changes made.${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
fi

# Verify DMGs exist
for dmg in "$SERVER_DMG" "$CLIENT_DMG"; do
    if [[ ! -f "$dmg" ]]; then
        log_err "DMG not found: $dmg"
        exit 1
    fi
done

NOTES_FILE=$(mktemp)
echo "$CHANGELOG" > "$NOTES_FILE"

gh release create "$RELEASE_TAG" \
    --title "$RELEASE_TITLE" \
    --notes-file "$NOTES_FILE" \
    "$SERVER_DMG" \
    "$CLIENT_DMG"

rm "$NOTES_FILE"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Release published!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "View at: https://github.com/${REPO}/releases/tag/${RELEASE_TAG}"
