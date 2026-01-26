#!/bin/bash
# Debrief Script - Run at end of every Claude Code session
# Ensures nothing is left behind (uncommitted, unstaged, stashed, unpushed)

set -e
cd "$(dirname "$0")/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  DEBRIEF PROTOCOL"
echo "═══════════════════════════════════════════════════════════════"
echo ""

ERRORS=0

# 1. Check for uncommitted changes
echo "▓▓▓ UNCOMMITTED CHANGES ▓▓▓"
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${RED}✗ UNCOMMITTED CHANGES FOUND:${NC}"
    git status --short
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Working directory clean${NC}"
fi
echo ""

# 2. Check for stashes
echo "▓▓▓ STASHED WORK ▓▓▓"
STASH_COUNT=$(git stash list | wc -l | tr -d ' ')
if [[ $STASH_COUNT -gt 0 ]]; then
    echo -e "${RED}✗ $STASH_COUNT STASH(ES) FOUND:${NC}"
    git stash list
    echo ""
    echo "  Run 'git stash pop' to apply, or 'git stash drop' to discard"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ No stashes${NC}"
fi
echo ""

# 3. Check for unpushed commits
echo "▓▓▓ UNPUSHED COMMITS ▓▓▓"
git fetch origin --quiet
UNPUSHED=$(git log origin/main..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ')
if [[ $UNPUSHED -gt 0 ]]; then
    echo -e "${RED}✗ $UNPUSHED UNPUSHED COMMIT(S):${NC}"
    git log origin/main..HEAD --oneline
    echo ""
    echo "  Run 'git push origin main' to push"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ All commits pushed to origin${NC}"
fi
echo ""

# 4. Run tests
echo "▓▓▓ TEST STATUS ▓▓▓"
if [[ -d "app" ]]; then
    cd app
    TEST_OUTPUT=$(xcodebuild test -scheme Async -destination 'platform=macOS' 2>&1 | tail -5)
    if echo "$TEST_OUTPUT" | grep -q "TEST SUCCEEDED"; then
        TEST_COUNT=$(echo "$TEST_OUTPUT" | grep -oE "Executed [0-9]+ tests" | head -1)
        echo -e "${GREEN}✓ $TEST_COUNT passed${NC}"
    else
        echo -e "${RED}✗ TESTS FAILED${NC}"
        echo "$TEST_OUTPUT"
        ERRORS=$((ERRORS + 1))
    fi
    cd ..
else
    echo -e "${YELLOW}⚠ No app directory found, skipping tests${NC}"
fi
echo ""

# 5. Summary
echo "═══════════════════════════════════════════════════════════════"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}"
    echo "     █████╗ ██╗     ██╗          ██████╗██╗     ███████╗ █████╗ ██████╗ "
    echo "    ██╔══██╗██║     ██║         ██╔════╝██║     ██╔════╝██╔══██╗██╔══██╗"
    echo "    ███████║██║     ██║         ██║     ██║     █████╗  ███████║██████╔╝"
    echo "    ██╔══██║██║     ██║         ██║     ██║     ██╔══╝  ██╔══██║██╔══██╗"
    echo "    ██║  ██║███████╗███████╗    ╚██████╗███████╗███████╗██║  ██║██║  ██║"
    echo "    ╚═╝  ╚═╝╚══════╝╚══════╝     ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo "  Safe to close. All work preserved on GitHub."
else
    echo -e "${RED}"
    echo "   ██████╗██████╗ ██╗████████╗██╗ ██████╗ █████╗ ██╗     "
    echo "  ██╔════╝██╔══██╗██║╚══██╔══╝██║██╔════╝██╔══██╗██║     "
    echo "  ██║     ██████╔╝██║   ██║   ██║██║     ███████║██║     "
    echo "  ██║     ██╔══██╗██║   ██║   ██║██║     ██╔══██║██║     "
    echo "  ╚██████╗██║  ██║██║   ██║   ██║╚██████╗██║  ██║███████╗"
    echo "   ╚═════╝╚═╝  ╚═╝╚═╝   ╚═╝   ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝"
    echo -e "${NC}"
    echo "  $ERRORS ISSUE(S) FOUND - Fix before closing!"
fi
echo "═══════════════════════════════════════════════════════════════"
echo ""

exit $ERRORS
