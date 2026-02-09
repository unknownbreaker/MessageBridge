#!/bin/bash
#
# MessageBridge Changelog Generator
# Generates two-section (Server/Client) release notes from conventional commits.
#
# Usage:
#   ./Scripts/generate-changelog.sh
#   ./Scripts/generate-changelog.sh --server-from server-v0.7.1 --client-from client-v0.7.1
#
# Output: Markdown to stdout with ## Server and ## Client sections.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Defaults: find latest component tags automatically
SERVER_FROM=""
CLIENT_FROM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --server-from) SERVER_FROM="$2"; shift 2 ;;
        --client-from) CLIENT_FROM="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Find latest component tag if not specified
find_latest_tag() {
    local prefix="$1"
    git tag -l "${prefix}-v*" --sort=-v:refname | head -1
}

if [[ -z "$SERVER_FROM" ]]; then
    SERVER_FROM=$(find_latest_tag "server")
fi

if [[ -z "$CLIENT_FROM" ]]; then
    CLIENT_FROM=$(find_latest_tag "client")
fi

# Extract version from tag (e.g., "server-v0.7.1" -> "0.7.1")
version_from_tag() {
    echo "$1" | sed 's/^[a-z]*-v//'
}

# Get commits for a component since a tag, scoped to its directory
# Each line: subject|short_hash
get_commits() {
    local tag="$1"
    local dir="$2"

    if [[ -n "$tag" ]]; then
        git log --pretty=format:"%s|%h" "${tag}..HEAD" -- "$dir" 2>/dev/null || true
    else
        git log --pretty=format:"%s|%h" -- "$dir" 2>/dev/null || true
    fi
}

# Find breaking changes from commit bodies and !: subjects
get_breaking_entries() {
    local tag="$1"
    local dir="$2"
    local range_arg=""

    if [[ -n "$tag" ]]; then
        range_arg="${tag}..HEAD"
    fi

    local hashes
    if [[ -n "$range_arg" ]]; then
        hashes=$(git log --pretty=format:"%H" "$range_arg" -- "$dir" 2>/dev/null || true)
    else
        hashes=$(git log --pretty=format:"%H" -- "$dir" 2>/dev/null || true)
    fi

    if [[ -z "$hashes" ]]; then
        return
    fi

    while IFS= read -r hash; do
        [[ -z "$hash" ]] && continue
        local subject short_hash
        subject=$(git log -1 --pretty=format:"%s" "$hash")
        short_hash=$(git log -1 --pretty=format:"%h" "$hash")

        # Check for feat!: or fix!: etc. in subject
        if echo "$subject" | grep -qE '^[a-z]+(\([^)]*\))?!:'; then
            local msg
            msg=$(echo "$subject" | sed -E 's/^[a-z]+(\([^)]*\))?!: *//')
            msg="$(echo "${msg:0:1}" | tr '[:lower:]' '[:upper:]')${msg:1}"
            echo "- $msg ($short_hash)"
        fi

        # Check for BREAKING CHANGE: in body
        local body
        body=$(git log -1 --pretty=format:"%b" "$hash")
        if echo "$body" | grep -qi "^BREAKING CHANGE:"; then
            local detail
            detail=$(echo "$body" | grep -i "^BREAKING CHANGE:" | sed 's/^BREAKING CHANGE: *//i' | head -1)
            if [[ -n "$detail" ]]; then
                echo "- $detail ($short_hash)"
            fi
        fi
    done <<< "$hashes"
}

# Extract commits matching a prefix, format as markdown list items
# Args: $1=commits (subject|hash lines), $2=regex prefix (e.g., "feat|fix")
format_commits() {
    local commits="$1"
    local prefix_regex="$2"

    echo "$commits" | grep -E "^${prefix_regex}(\([^)]*\))?: " | while IFS='|' read -r subject hash; do
        [[ -z "$subject" ]] && continue
        local msg
        msg=$(echo "$subject" | sed -E "s/^(${prefix_regex})(\([^)]*\))?: *//")
        # Capitalize first letter
        msg="$(echo "${msg:0:1}" | tr '[:lower:]' '[:upper:]')${msg:1}"
        echo "- $msg ($hash)"
    done || true
}

# Generate one component section
# Args: $1=display name, $2=from tag, $3=directory name
generate_section() {
    local component="$1"
    local from_tag="$2"
    local dir="$3"

    local old_version new_version
    local version_file="$PROJECT_DIR/$dir/VERSION"

    if [[ -n "$from_tag" ]]; then
        old_version=$(version_from_tag "$from_tag")
    else
        old_version=""
    fi
    new_version=$(tr -d '[:space:]' < "$version_file" 2>/dev/null || echo "0.0.0")

    # Get all commits
    local commits
    commits=$(get_commits "$from_tag" "$dir")

    if [[ -z "$commits" ]]; then
        if [[ -n "$old_version" ]]; then
            echo "## $component (v$old_version)"
        else
            echo "## $component (v$new_version)"
        fi
        echo ""
        echo "No changes since v${old_version:-$new_version}."
        echo ""
        return
    fi

    # Header: show arrow if version changed
    if [[ -n "$old_version" ]] && [[ "$old_version" != "$new_version" ]]; then
        echo "## $component (v$old_version -> v$new_version)"
    elif [[ -n "$old_version" ]]; then
        echo "## $component (v$old_version)"
    else
        echo "## $component (v$new_version)"
    fi
    echo ""

    local has_content=false

    # Breaking changes
    local breaking
    breaking=$(get_breaking_entries "$from_tag" "$dir")
    if [[ -n "$breaking" ]]; then
        echo "### Breaking"
        echo "$breaking"
        echo ""
        has_content=true
    fi

    # Features
    local features
    features=$(format_commits "$commits" "feat")
    if [[ -n "$features" ]]; then
        echo "### Features"
        echo "$features"
        echo ""
        has_content=true
    fi

    # Fixes (fix + perf)
    local fixes
    fixes=$(format_commits "$commits" "fix|perf")
    if [[ -n "$fixes" ]]; then
        echo "### Fixes"
        echo "$fixes"
        echo ""
        has_content=true
    fi

    if [[ "$has_content" != true ]]; then
        echo "Maintenance changes only."
        echo ""
    fi
}

# Generate both sections
generate_section "Server" "$SERVER_FROM" "MessageBridgeServer"
generate_section "Client" "$CLIENT_FROM" "MessageBridgeClient"

echo "---"
echo "Signed and notarized by Apple."
