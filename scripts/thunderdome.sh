#!/bin/bash
# Protocol Thunderdome - AI Scrum Master Routine
# Run with: ./scripts/thunderdome.sh

set -e
cd /Users/BillMoore/async

echo ""
echo "⚔️  PROTOCOL THUNDERDOME ⚔️"
echo "=========================="
echo ""

# Track warnings
WARNINGS=()

# 1. LOCAL HEALTH CHECK (Most Important!)
echo "🏥 LOCAL HEALTH CHECK"
echo "---------------------"

# Check for uncommitted changes
UNCOMMITTED=$(git status --porcelain | wc -l | tr -d ' ')
if [ "$UNCOMMITTED" -gt 0 ]; then
    echo "⚠️  UNCOMMITTED CHANGES: $UNCOMMITTED files"
    git status --short
    WARNINGS+=("$UNCOMMITTED uncommitted files")
else
    echo "✅ Working directory clean"
fi

# Check for unpushed commits
UNPUSHED=$(git log origin/main..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ')
if [ "$UNPUSHED" -gt 0 ]; then
    echo "⚠️  UNPUSHED COMMITS: $UNPUSHED"
    git log origin/main..HEAD --oneline
    WARNINGS+=("$UNPUSHED unpushed commits")
else
    echo "✅ All commits pushed"
fi

# Check if we're on main
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
    echo "📌 On branch: $BRANCH (not main)"
else
    echo "✅ On branch: main"
fi
echo ""

# 2. GITHUB SYNC STATUS
echo "🔄 GITHUB SYNC"
echo "--------------"
git fetch origin --quiet
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)
if [ "$LOCAL" = "$REMOTE" ]; then
    echo "✅ In sync with origin/main"
else
    BEHIND=$(git rev-list HEAD..origin/main --count)
    AHEAD=$(git rev-list origin/main..HEAD --count)
    [ "$BEHIND" -gt 0 ] && echo "⚠️  $BEHIND commits behind origin/main" && WARNINGS+=("$BEHIND commits behind remote")
    [ "$AHEAD" -gt 0 ] && echo "📤 $AHEAD commits ahead of origin/main"
fi
echo ""

# 3. Recent commits (GitHub)
echo "📝 RECENT COMMITS (GitHub)"
echo "--------------------------"
gh api repos/chickensintrees/async/commits --jq '.[:8] | .[] | "\(.sha[0:7]) \(.author.login // "unknown"): \(.commit.message | split("\n")[0])"' 2>/dev/null || echo "Could not fetch"
echo ""

# 4. Open PRs
echo "🔀 PULL REQUESTS"
echo "----------------"
PR_COUNT=$(gh api repos/chickensintrees/async/pulls --jq 'length' 2>/dev/null || echo "0")
if [ "$PR_COUNT" -gt 0 ]; then
    gh api repos/chickensintrees/async/pulls --jq '.[] | "PR #\(.number): \(.title) by \(.user.login) [\(.state)]"'
    WARNINGS+=("$PR_COUNT open PRs")
else
    echo "No open PRs"
fi
echo ""

# 5. Open issues (backlog)
echo "📋 BACKLOG (Open Issues)"
echo "------------------------"
ISSUE_COUNT=$(gh api repos/chickensintrees/async/issues --jq '[.[] | select(.pull_request == null)] | length' 2>/dev/null || echo "0")
echo "$ISSUE_COUNT open issues"
gh api repos/chickensintrees/async/issues --jq '.[:5] | .[] | select(.pull_request == null) | "#\(.number) \(.title)"' 2>/dev/null || echo "Could not fetch"
echo ""

# 6. Branch check
echo "🌿 REMOTE BRANCHES"
echo "------------------"
gh api repos/chickensintrees/async/branches --jq '.[].name' 2>/dev/null || echo "Could not fetch"
echo ""

# 7. Test status (if tests exist)
echo "🧪 TEST STATUS"
echo "--------------"
if [ -d "app/Tests" ] || [ -f "Package.swift" ]; then
    # Try to run tests quickly
    if swift test --skip-build 2>/dev/null; then
        echo "✅ Tests passing"
    else
        echo "⚠️  Run 'swift test' to check test status"
    fi
else
    echo "⚠️  No tests found"
    WARNINGS+=("No tests")
fi
echo ""

# 8. Summary
echo "📊 SUMMARY"
echo "----------"
if [ ${#WARNINGS[@]} -eq 0 ]; then
    echo "✅ ALL CLEAR - Ready to code!"
else
    echo "⚠️  ${#WARNINGS[@]} WARNINGS:"
    for w in "${WARNINGS[@]}"; do
        echo "   • $w"
    done
    echo ""
    echo "🛠️  RECOMMENDED ACTIONS:"
    if [[ " ${WARNINGS[*]} " =~ "uncommitted" ]]; then
        echo "   git add -A && git commit -m 'Your message'"
    fi
    if [[ " ${WARNINGS[*]} " =~ "unpushed" ]]; then
        echo "   git push origin main"
    fi
    if [[ " ${WARNINGS[*]} " =~ "behind" ]]; then
        echo "   git pull origin main"
    fi
fi
echo ""
echo "⚔️  END THUNDERDOME ⚔️"
echo ""
