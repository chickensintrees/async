#!/bin/bash
# Thunderdome Data Gatherer - outputs JSON for narrative generation
# Called by STEF to generate pundit commentary

cd /Users/BillMoore/async

# Get the data
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
UNPUSHED=$(git log origin/main..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ')

# Fetch from GitHub
git fetch origin --quiet 2>/dev/null

# Commit counts (activity, not value)
BILL_TODAY=$(gh api repos/chickensintrees/async/commits --jq '[.[] | select(.author.login == "chickensintrees") | select(.commit.author.date | startswith("'"$(date +%Y-%m-%d)"'"))] | length' 2>/dev/null || echo "0")
NOAH_TODAY=$(gh api repos/chickensintrees/async/commits --jq '[.[] | select(.author.login == "ginzatron") | select(.commit.author.date | startswith("'"$(date +%Y-%m-%d)"'"))] | length' 2>/dev/null || echo "0")

# Weekly counts
WEEK_AGO=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d)
BILL_WEEK=$(gh api repos/chickensintrees/async/commits --jq '[.[] | select(.author.login == "chickensintrees") | select(.commit.author.date >= "'"$WEEK_AGO"'")] | length' 2>/dev/null || echo "0")
NOAH_WEEK=$(gh api repos/chickensintrees/async/commits --jq '[.[] | select(.author.login == "ginzatron") | select(.commit.author.date >= "'"$WEEK_AGO"'")] | length' 2>/dev/null || echo "0")

# VALUE METRICS - What actually matters
# PRs merged this week (by author of the PR, not merger)
BILL_PRS_MERGED=$(gh api repos/chickensintrees/async/pulls?state=closed --jq '[.[] | select(.merged_at != null) | select(.user.login == "chickensintrees") | select(.merged_at >= "'"$WEEK_AGO"'")] | length' 2>/dev/null || echo "0")
NOAH_PRS_MERGED=$(gh api repos/chickensintrees/async/pulls?state=closed --jq '[.[] | select(.merged_at != null) | select(.user.login == "ginzatron") | select(.merged_at >= "'"$WEEK_AGO"'")] | length' 2>/dev/null || echo "0")

# Issues closed this week
BILL_ISSUES_CLOSED=$(gh api "repos/chickensintrees/async/issues?state=closed&since=$WEEK_AGO" --jq '[.[] | select(.pull_request == null) | select(.closed_by.login == "chickensintrees")] | length' 2>/dev/null || echo "0")
NOAH_ISSUES_CLOSED=$(gh api "repos/chickensintrees/async/issues?state=closed&since=$WEEK_AGO" --jq '[.[] | select(.pull_request == null) | select(.closed_by.login == "ginzatron")] | length' 2>/dev/null || echo "0")

# Specs in openspec/changes (count files by author via git log)
SPECS_BY_BILL=$(git log --all --oneline --author="chickensintrees" -- "openspec/changes/**/*.md" 2>/dev/null | wc -l | tr -d ' ')
SPECS_BY_NOAH=$(git log --all --oneline --author="ginzatron" -- "openspec/changes/**/*.md" 2>/dev/null | wc -l | tr -d ' ')

# Recent commits (last 10)
RECENT_COMMITS=$(gh api repos/chickensintrees/async/commits --jq '[.[:10] | .[] | {sha: .sha[0:7], author: .author.login, message: (.commit.message | split("\n")[0]), date: .commit.author.date}]' 2>/dev/null || echo "[]")

# Open PRs
OPEN_PRS=$(gh api repos/chickensintrees/async/pulls --jq '[.[] | {number, title, author: .user.login, created_at, draft}]' 2>/dev/null || echo "[]")
PR_COUNT=$(echo "$OPEN_PRS" | jq 'length' 2>/dev/null || echo "0")

# Open issues (not PRs)
OPEN_ISSUES=$(gh api repos/chickensintrees/async/issues --jq '[.[] | select(.pull_request == null) | {number, title, author: .user.login, created_at, labels: [.labels[].name]}]' 2>/dev/null || echo "[]")
ISSUE_COUNT=$(echo "$OPEN_ISSUES" | jq 'length' 2>/dev/null || echo "0")

# Branches
BRANCHES=$(gh api repos/chickensintrees/async/branches --jq '[.[].name]' 2>/dev/null || echo "[]")

# Last session timestamp (from session logs)
LAST_SESSION=$(ls -t ~/.claude/session-logs/*.md 2>/dev/null | head -1)
if [ -n "$LAST_SESSION" ]; then
    LAST_SESSION_DATE=$(basename "$LAST_SESSION" | cut -d'-' -f1-3)
else
    LAST_SESSION_DATE="unknown"
fi

# Hours since last session
NOW=$(date +%s)
if [ -n "$LAST_SESSION" ]; then
    LAST_MOD=$(stat -f %m "$LAST_SESSION" 2>/dev/null || stat -c %Y "$LAST_SESSION" 2>/dev/null)
    HOURS_SINCE=$(( (NOW - LAST_MOD) / 3600 ))
else
    HOURS_SINCE="unknown"
fi

# Recent activity by contributor
BILL_RECENT=$(gh api repos/chickensintrees/async/commits --jq '[.[:20] | .[] | select(.author.login == "chickensintrees") | .commit.message | split("\n")[0]][:5]' 2>/dev/null || echo "[]")
NOAH_RECENT=$(gh api repos/chickensintrees/async/commits --jq '[.[:20] | .[] | select(.author.login == "ginzatron") | .commit.message | split("\n")[0]][:5]' 2>/dev/null || echo "[]")

# Output JSON
cat << EOF
{
  "timestamp": "$(date -Iseconds)",
  "repo": {
    "branch": "$BRANCH",
    "uncommitted": $UNCOMMITTED,
    "unpushed": $UNPUSHED
  },
  "combatants": {
    "chickensintrees": {
      "activity": {
        "commits_today": $BILL_TODAY,
        "commits_week": $BILL_WEEK
      },
      "delivered_value": {
        "prs_merged_week": $BILL_PRS_MERGED,
        "issues_closed_week": $BILL_ISSUES_CLOSED,
        "specs_contributed": $SPECS_BY_BILL
      },
      "recent_messages": $BILL_RECENT
    },
    "ginzatron": {
      "activity": {
        "commits_today": $NOAH_TODAY,
        "commits_week": $NOAH_WEEK
      },
      "delivered_value": {
        "prs_merged_week": $NOAH_PRS_MERGED,
        "issues_closed_week": $NOAH_ISSUES_CLOSED,
        "specs_contributed": $SPECS_BY_NOAH
      },
      "recent_messages": $NOAH_RECENT
    }
  },
  "activity": {
    "recent_commits": $RECENT_COMMITS,
    "open_prs": $OPEN_PRS,
    "pr_count": $PR_COUNT,
    "open_issues": $OPEN_ISSUES,
    "issue_count": $ISSUE_COUNT,
    "branches": $BRANCHES
  },
  "session": {
    "last_session_date": "$LAST_SESSION_DATE",
    "hours_since_last": $HOURS_SINCE
  }
}
EOF
