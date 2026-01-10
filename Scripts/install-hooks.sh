#!/bin/bash
#
# Install git hooks for MessageBridge development
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$PROJECT_DIR/.git/hooks"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

echo "Installing git hooks..."

# Create pre-commit hook
cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/bin/bash
#
# Pre-commit hook for MessageBridge
# Runs all tests before allowing a commit
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Running pre-commit tests...${NC}"
echo ""

# Get the root directory of the repository
ROOT_DIR="$(git rev-parse --show-toplevel)"

# Track if any tests fail
FAILED=0

# Run Server tests
echo -e "${YELLOW}[1/2] Running Server tests...${NC}"
cd "$ROOT_DIR/MessageBridgeServer"
if swift test 2>&1; then
    echo -e "${GREEN}✓ Server tests passed${NC}"
else
    echo -e "${RED}✗ Server tests failed${NC}"
    FAILED=1
fi

echo ""

# Run Client tests
echo -e "${YELLOW}[2/2] Running Client tests...${NC}"
cd "$ROOT_DIR/MessageBridgeClient"
if swift test 2>&1; then
    echo -e "${GREEN}✓ Client tests passed${NC}"
else
    echo -e "${RED}✗ Client tests failed${NC}"
    FAILED=1
fi

echo ""

# Exit with appropriate code
if [ $FAILED -eq 1 ]; then
    echo -e "${RED}═══════════════════════════════════════════${NC}"
    echo -e "${RED}  COMMIT BLOCKED: Tests failed${NC}"
    echo -e "${RED}  Fix the failing tests and try again${NC}"
    echo -e "${RED}═══════════════════════════════════════════${NC}"
    exit 1
else
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  All tests passed! Proceeding with commit${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    exit 0
fi
HOOK

chmod +x "$HOOKS_DIR/pre-commit"

echo -e "${GREEN}✓ Pre-commit hook installed${NC}"
echo ""
echo "The pre-commit hook will run all tests before each commit."
echo "To skip the hook temporarily, use: git commit --no-verify"
