#!/bin/bash
# Protocol Thunderdome - AI Scrum Master Routine
# Run with: ./scripts/thunderdome.sh

echo "⚔️  PROTOCOL THUNDERDOME ⚔️"
echo "=========================="
echo ""

# 1. Recent commits
echo "📝 RECENT COMMITS"
echo "-----------------"
gh api repos/chickensintrees/async/commits --jq '.[:10] | .[] | "\(.sha[0:7]) \(.author.login // "unknown"): \(.commit.message | split("\n")[0])"'
echo ""

# 2. Activity feed
echo "🔔 RECENT ACTIVITY"
echo "------------------"
gh api repos/chickensintrees/async/events --jq '.[:8] | .[] | "\(.created_at | split("T")[0]) \(.actor.login): \(.type | gsub("Event$";""))"'
echo ""

# 3. Open issues (backlog)
echo "📋 BACKLOG (Open Issues)"
echo "------------------------"
gh api repos/chickensintrees/async/issues --jq '.[] | select(.state=="open") | "#\(.number) \(.title) [\(.labels | map(.name) | join(", "))]"'
echo ""

# 4. Branches
echo "🌿 BRANCHES"
echo "-----------"
gh api repos/chickensintrees/async/branches --jq '.[].name'
echo ""

# 5. Latest comments
echo "💬 RECENT COMMENTS"
echo "------------------"
gh api repos/chickensintrees/async/issues/comments --jq '.[-5:] | .[] | "Issue \(.issue_url | split("/") | last) - \(.user.login): \(.body | split("\n")[0] | .[0:80])"' 2>/dev/null || echo "No recent comments"
echo ""

# 6. PR status
echo "🔀 PULL REQUESTS"
echo "----------------"
gh api repos/chickensintrees/async/pulls --jq '.[] | "#\(.number) \(.title) by \(.user.login) [\(.state)]"' 2>/dev/null || echo "No open PRs"
echo ""

# 7. Local status
echo "💻 LOCAL STATUS"
echo "---------------"
cd /Users/BillMoore/async
git status --short
echo ""

echo "⚔️  END THUNDERDOME ⚔️"
