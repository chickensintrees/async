#!/bin/bash
# Protocol Thunderdome - AI Scrum Master Routine
# Run with: ./scripts/thunderdome.sh

# ══════════════════════════════════════════════════════════════════════════════
# TERMINAL SETUP
# ══════════════════════════════════════════════════════════════════════════════

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
ORANGE='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
BLINK='\033[5m'
RESET='\033[0m'

# Box drawing
H_LINE="═"
V_LINE="║"
TL="╔"
TR="╗"
BL="╚"
BR="╝"
T_DOWN="╦"
T_UP="╩"
T_RIGHT="╠"
T_LEFT="╣"
CROSS="╬"

# Typewriter effect
typewrite() {
    local text="$1"
    local delay="${2:-0.02}"
    for (( i=0; i<${#text}; i++ )); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
    echo ""
}

# Glitch effect
glitch() {
    local text="$1"
    local glitch_chars="@#$%&*!?"
    for i in {1..3}; do
        # Random glitch
        local glitched=""
        for (( j=0; j<${#text}; j++ )); do
            if [ $((RANDOM % 4)) -eq 0 ]; then
                glitched+="${glitch_chars:$((RANDOM % ${#glitch_chars})):1}"
            else
                glitched+="${text:$j:1}"
            fi
        done
        printf "\r${RED}%s${RESET}" "$glitched"
        sleep 0.05
    done
    printf "\r${WHITE}%s${RESET}\n" "$text"
}

# Play boot sound (macOS)
play_sound() {
    # Try to play a system sound
    if [ -f "/System/Library/Sounds/Funk.aiff" ]; then
        afplay "/System/Library/Sounds/Funk.aiff" &
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# BOOT SEQUENCE
# ══════════════════════════════════════════════════════════════════════════════

clear

# Play sound
play_sound

# Dramatic pause with loading bar
echo ""
printf "${GRAY}"
for i in {1..60}; do
    printf "▓"
    sleep 0.008
done
printf "${RESET}\n"

# ASCII Art Header
echo ""
printf "${RED}"
cat << 'EOF'
  ▄▄▄█████▓ ██░ ██  █    ██  ███▄    █ ▓█████▄ ▓█████  ██▀███  ▓█████▄  ▒█████   ███▄ ▄███▓▓█████
  ▓  ██▒ ▓▒▓██░ ██▒ ██  ▓██▒ ██ ▀█   █ ▒██▀ ██▌▓█   ▀ ▓██ ▒ ██▒▒██▀ ██▌▒██▒  ██▒▓██▒▀█▀ ██▒▓█   ▀
  ▒ ▓██░ ▒░▒██▀▀██░▓██  ▒██░▓██  ▀█ ██▒░██   █▌▒███   ▓██ ░▄█ ▒░██   █▌▒██░  ██▒▓██    ▓██░▒███
  ░ ▓██▓ ░ ░▓█ ░██ ▓▓█  ░██░▓██▒  ▐▌██▒░▓█▄   ▌▒▓█  ▄ ▒██▀▀█▄  ░▓█▄   ▌▒██   ██░▒██    ▒██ ▒▓█  ▄
    ▒██▒ ░ ░▓█▒░██▓▒▒█████▓ ▒██░   ▓██░░▒████▓ ░▒████▒░██▓ ▒██▒░▒████▓ ░ ████▓▒░▒██▒   ░██▒░▒████▒
    ▒ ░░    ▒ ░░▒░▒░▒▓▒ ▒ ▒ ░ ▒░   ▒ ▒  ▒▒▓  ▒ ░░ ▒░ ░░ ▒▓ ░▒▓░ ▒▒▓  ▒ ░ ▒░▒░▒░ ░ ▒░   ░  ░░░ ▒░ ░
      ░     ▒ ░▒░ ░░░▒░ ░ ░ ░ ░░   ░ ▒░ ░ ▒  ▒  ░ ░  ░  ░▒ ░ ▒░ ░ ▒  ▒   ░ ▒ ▒░ ░  ░      ░ ░ ░  ░
    ░       ░  ░░ ░ ░░░ ░ ░    ░   ░ ░  ░ ░  ░    ░     ░░   ░  ░ ░  ░ ░ ░ ░ ▒  ░      ░      ░
            ░  ░  ░   ░              ░    ░       ░  ░   ░        ░        ░ ░         ░      ░  ░
EOF
printf "${RESET}"

echo ""
printf "${CYAN}${DIM}"
cat << 'EOF'
                         ╔═══════════════════════════════════════════════════╗
                         ║   P R O T O C O L   I N I T I A L I Z E D   ▓▓▓   ║
                         ║          TWO DEVS ENTER • ONE CODEBASE            ║
                         ╚═══════════════════════════════════════════════════╝
EOF
printf "${RESET}"
echo ""

# Boot messages
printf "${GRAY}["
printf "${GREEN}████████████████████████████████████████${GRAY}] "
printf "${WHITE}SYSTEM READY${RESET}\n"
echo ""

sleep 0.3

# System info
printf "${DIM}${CYAN}┌──────────────────────────────────────────────────────────────────────────────┐${RESET}\n"
printf "${DIM}${CYAN}│${RESET} ${GRAY}THUNDERDOME v2.0 // $(date '+%Y-%m-%d %H:%M:%S') // node: $(hostname -s)${DIM}${CYAN}$(printf '%*s' $((34 - ${#HOSTNAME})) '')│${RESET}\n"
printf "${DIM}${CYAN}│${RESET} ${GRAY}repo: chickensintrees/async // branch: $(git branch --show-current 2>/dev/null || echo 'unknown')${DIM}${CYAN}$(printf '%*s' 26 '')│${RESET}\n"
printf "${DIM}${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${RESET}\n"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# MAIN CHECKS
# ══════════════════════════════════════════════════════════════════════════════

cd /Users/BillMoore/async

# Track warnings
WARNINGS=()
CRITICAL=()

# ─────────────────────────────────────────────────────────────────────────────
section() {
    echo ""
    printf "${PURPLE}▓▓▓ ${WHITE}${BOLD}$1${RESET} ${PURPLE}"
    for i in $(seq 1 $((65 - ${#1}))); do printf "▓"; done
    printf "${RESET}\n"
}

status_ok() {
    printf "  ${GREEN}✓${RESET} ${WHITE}$1${RESET}\n"
}

status_warn() {
    printf "  ${YELLOW}⚠${RESET} ${YELLOW}$1${RESET}\n"
    WARNINGS+=("$1")
}

status_crit() {
    printf "  ${RED}✗${RESET} ${RED}${BOLD}$1${RESET}\n"
    CRITICAL+=("$1")
}

status_info() {
    printf "  ${CYAN}→${RESET} ${GRAY}$1${RESET}\n"
}

# ─────────────────────────────────────────────────────────────────────────────
section "LOCAL RECON"

# Uncommitted changes
UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$UNCOMMITTED" -gt 0 ]; then
    status_crit "$UNCOMMITTED UNCOMMITTED FILES"
    git status --porcelain | head -5 | while read line; do
        printf "      ${DIM}${GRAY}$line${RESET}\n"
    done
    [ "$UNCOMMITTED" -gt 5 ] && printf "      ${DIM}${GRAY}... and $((UNCOMMITTED - 5)) more${RESET}\n"
else
    status_ok "Working directory clean"
fi

# Unpushed commits
UNPUSHED=$(git log origin/main..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ')
if [ "$UNPUSHED" -gt 0 ]; then
    status_warn "$UNPUSHED unpushed commits"
    git log origin/main..HEAD --oneline | head -3 | while read line; do
        printf "      ${DIM}${CYAN}$line${RESET}\n"
    done
else
    status_ok "All commits pushed to origin"
fi

# Branch check
BRANCH=$(git branch --show-current)
if [ "$BRANCH" = "main" ]; then
    status_ok "On branch: main"
else
    status_info "On branch: $BRANCH"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "TEST GARRISON"

# Run tests silently and capture result
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_OUTPUT=$("$SCRIPT_DIR/run-tests.sh" 2>&1)
TEST_EXIT=$?
TEST_SUMMARY=$(echo "$TEST_OUTPUT" | grep "RESULT:" | sed 's/.*RESULT: //' | sed 's/\[0m//g' | sed 's/\[0;32m//g' | sed 's/\[0;31m//g')

if [ $TEST_EXIT -eq 0 ]; then
    status_ok "Tests: $TEST_SUMMARY"
else
    status_crit "Tests: $TEST_SUMMARY"
    # Show first few test failures
    echo "$TEST_OUTPUT" | grep -E "✗|FAIL|failed" | head -3 | while read line; do
        printf "      ${DIM}${RED}$line${RESET}\n"
    done
fi

# ─────────────────────────────────────────────────────────────────────────────
section "GITHUB SYNC"

git fetch origin --quiet 2>/dev/null

LOCAL=$(git rev-parse HEAD 2>/dev/null)
REMOTE=$(git rev-parse origin/main 2>/dev/null)

if [ "$LOCAL" = "$REMOTE" ]; then
    status_ok "In sync with origin/main"
else
    BEHIND=$(git rev-list HEAD..origin/main --count 2>/dev/null || echo "0")
    AHEAD=$(git rev-list origin/main..HEAD --count 2>/dev/null || echo "0")
    [ "$BEHIND" -gt 0 ] && status_warn "$BEHIND commits behind - run: git pull"
    [ "$AHEAD" -gt 0 ] && status_info "$AHEAD commits ahead of origin"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "COMBATANTS"

printf "  ${BLUE}┌─────────────────────────┐${RESET}     ${PURPLE}┌─────────────────────────┐${RESET}\n"
printf "  ${BLUE}│${RESET}  ${WHITE}${BOLD}BILL${RESET} ${GRAY}(chickensintrees)${RESET} ${BLUE}│${RESET}     ${PURPLE}│${RESET}  ${WHITE}${BOLD}NOAH${RESET} ${GRAY}(ginzatron)${RESET}        ${PURPLE}│${RESET}\n"

# Get commit counts for today
BILL_TODAY=$(gh api repos/chickensintrees/async/commits --jq '[.[] | select(.author.login == "chickensintrees") | select(.commit.author.date | startswith("'"$(date +%Y-%m-%d)"'"))] | length' 2>/dev/null || echo "?")
NOAH_TODAY=$(gh api repos/chickensintrees/async/commits --jq '[.[] | select(.author.login == "ginzatron") | select(.commit.author.date | startswith("'"$(date +%Y-%m-%d)"'"))] | length' 2>/dev/null || echo "?")

printf "  ${BLUE}│${RESET}  Commits today: ${GREEN}$BILL_TODAY${RESET}       ${BLUE}│${RESET}     ${PURPLE}│${RESET}  Commits today: ${GREEN}$NOAH_TODAY${RESET}       ${PURPLE}│${RESET}\n"
printf "  ${BLUE}└─────────────────────────┘${RESET}     ${PURPLE}└─────────────────────────┘${RESET}\n"

# ─────────────────────────────────────────────────────────────────────────────
section "RECENT TRANSMISSIONS"

gh api repos/chickensintrees/async/commits --jq '.[:5] | .[] | "\(.sha[0:7]) \(.author.login // "unknown"): \(.commit.message | split("\n")[0] | .[0:50])"' 2>/dev/null | while read line; do
    SHA=$(echo "$line" | cut -d' ' -f1)
    REST=$(echo "$line" | cut -d' ' -f2-)
    if [[ "$REST" == *"chickensintrees"* ]]; then
        printf "  ${BLUE}${SHA}${RESET} ${GRAY}$REST${RESET}\n"
    elif [[ "$REST" == *"ginzatron"* ]]; then
        printf "  ${PURPLE}${SHA}${RESET} ${GRAY}$REST${RESET}\n"
    else
        printf "  ${CYAN}${SHA}${RESET} ${GRAY}$REST${RESET}\n"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
section "BATTLE QUEUE"

PR_COUNT=$(gh api repos/chickensintrees/async/pulls --jq 'length' 2>/dev/null || echo "0")
ISSUE_COUNT=$(gh api repos/chickensintrees/async/issues --jq '[.[] | select(.pull_request == null)] | length' 2>/dev/null || echo "0")

if [ "$PR_COUNT" -gt 0 ]; then
    status_warn "$PR_COUNT open PRs awaiting review"
    gh api repos/chickensintrees/async/pulls --jq '.[] | "  PR #\(.number): \(.title | .[0:40])"' 2>/dev/null | while read line; do
        printf "    ${ORANGE}$line${RESET}\n"
    done
else
    status_ok "No PRs pending"
fi

status_info "$ISSUE_COUNT issues in backlog"
gh api repos/chickensintrees/async/issues --jq '.[:3] | .[] | select(.pull_request == null) | "#\(.number) \(.title | .[0:45])"' 2>/dev/null | while read line; do
    printf "      ${DIM}$line${RESET}\n"
done

# ─────────────────────────────────────────────────────────────────────────────
section "REMOTE OUTPOSTS"

gh api repos/chickensintrees/async/branches --jq '.[].name' 2>/dev/null | while read branch; do
    if [ "$branch" = "main" ]; then
        printf "  ${GREEN}●${RESET} ${WHITE}$branch${RESET} ${GRAY}(primary)${RESET}\n"
    else
        printf "  ${YELLOW}○${RESET} ${GRAY}$branch${RESET}\n"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
section "DOC STALENESS"

# Check when key docs were last modified vs last code change
LAST_CODE_COMMIT=$(git log -1 --format="%H" -- "app/" 2>/dev/null)
LAST_CODE_DATE=$(git log -1 --format="%ci" -- "app/" 2>/dev/null | cut -d' ' -f1)

check_doc_staleness() {
    local doc="$1"
    local name="$2"
    if [ -f "$doc" ]; then
        local doc_date=$(git log -1 --format="%ci" -- "$doc" 2>/dev/null | cut -d' ' -f1)
        local doc_age=$(( ($(date +%s) - $(date -j -f "%Y-%m-%d" "$doc_date" +%s 2>/dev/null || echo 0)) / 86400 ))

        if [ "$doc_age" -gt 7 ]; then
            status_warn "$name: $doc_age days old"
            WARNINGS+=("$name not updated in $doc_age days")
        elif [ "$doc_age" -gt 3 ]; then
            status_info "$name: $doc_age days old"
        else
            status_ok "$name: updated $doc_date"
        fi
    else
        status_warn "$name: FILE MISSING"
        WARNINGS+=("$name is missing")
    fi
}

check_doc_staleness "README.md" "README"
check_doc_staleness "CLAUDE.md" "CLAUDE.md"
check_doc_staleness "openspec/project.md" "openspec/project"

# ══════════════════════════════════════════════════════════════════════════════
# FINAL REPORT
# ══════════════════════════════════════════════════════════════════════════════

echo ""
printf "${GRAY}══════════════════════════════════════════════════════════════════════════════${RESET}\n"

if [ ${#CRITICAL[@]} -gt 0 ]; then
    echo ""
    printf "${RED}${BOLD}  ██████╗ ██████╗ ██╗████████╗██╗ ██████╗ █████╗ ██╗     ${RESET}\n"
    printf "${RED}${BOLD} ██╔════╝██╔══██╗██║╚══██╔══╝██║██╔════╝██╔══██╗██║     ${RESET}\n"
    printf "${RED}${BOLD} ██║     ██████╔╝██║   ██║   ██║██║     ███████║██║     ${RESET}\n"
    printf "${RED}${BOLD} ██║     ██╔══██╗██║   ██║   ██║██║     ██╔══██║██║     ${RESET}\n"
    printf "${RED}${BOLD} ╚██████╗██║  ██║██║   ██║   ██║╚██████╗██║  ██║███████╗${RESET}\n"
    printf "${RED}${BOLD}  ╚═════╝╚═╝  ╚═╝╚═╝   ╚═╝   ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝${RESET}\n"
    echo ""
    for c in "${CRITICAL[@]}"; do
        printf "  ${RED}▸ $c${RESET}\n"
    done
    echo ""
    printf "${YELLOW}  RECOMMENDED:${RESET}\n"
    printf "    ${WHITE}git add -A && git commit -m 'your message'${RESET}\n"
    printf "    ${WHITE}git push origin main${RESET}\n"

elif [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    printf "${YELLOW}  ⚠ ${#WARNINGS[@]} WARNINGS DETECTED${RESET}\n"
    for w in "${WARNINGS[@]}"; do
        printf "    ${YELLOW}▸ $w${RESET}\n"
    done

else
    echo ""
    printf "${GREEN}${BOLD}"
    cat << 'EOF'
     █████╗ ██╗     ██╗          ██████╗██╗     ███████╗ █████╗ ██████╗
    ██╔══██╗██║     ██║         ██╔════╝██║     ██╔════╝██╔══██╗██╔══██╗
    ███████║██║     ██║         ██║     ██║     █████╗  ███████║██████╔╝
    ██╔══██║██║     ██║         ██║     ██║     ██╔══╝  ██╔══██║██╔══██╗
    ██║  ██║███████╗███████╗    ╚██████╗███████╗███████╗██║  ██║██║  ██║
    ╚═╝  ╚═╝╚══════╝╚══════╝     ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝
EOF
    printf "${RESET}"
    echo ""
    printf "  ${GREEN}Ready for battle. May your commits be atomic and your tests green.${RESET}\n"
fi

echo ""
printf "${DIM}${GRAY}══════════════════════════════════════════════════════════════════════════════${RESET}\n"
printf "${DIM}${GRAY}  THUNDERDOME COMPLETE // $(date '+%H:%M:%S') // type 'td' to run again${RESET}\n"
printf "${DIM}${GRAY}══════════════════════════════════════════════════════════════════════════════${RESET}\n"
echo ""
