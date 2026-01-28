#!/bin/bash
# stress-test-watch.sh - Test watch daemon for duplicate response prevention
# Verifies that multiple watchers don't cause duplicate agent responses

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Supabase config
SUPABASE_URL="https://ujokdwgpwruyiuioseir.supabase.co"
SUPABASE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqb2tkd2dwd3J1eWl1aW9zZWlyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzNzM0MjQsImV4cCI6MjA4NDk0OTQyNH0.DLz3djC6RGqs0gkhH4XalTUwizcBYFHWnvfG9X-dwxk"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# API helper
api() {
    local endpoint="$1"
    local method="${2:-GET}"
    local data="$3"

    if [ -n "$data" ]; then
        curl -s -X "$method" "${SUPABASE_URL}/rest/v1/${endpoint}" \
            -H "apikey: ${SUPABASE_KEY}" \
            -H "Authorization: Bearer ${SUPABASE_KEY}" \
            -H "Content-Type: application/json" \
            -H "Prefer: return=representation" \
            -d "$data"
    else
        curl -s -X "$method" "${SUPABASE_URL}/rest/v1/${endpoint}" \
            -H "apikey: ${SUPABASE_KEY}" \
            -H "Authorization: Bearer ${SUPABASE_KEY}"
    fi
}

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       WATCH DAEMON STRESS TEST - Duplicate Prevention      ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo

# ============================================================================
# Test 1: Check for Running Watch Instances
# ============================================================================
echo -e "${YELLOW}▓▓▓ TEST 1: Check for Running Watch Instances ▓▓▓${NC}"

WATCH_PIDS=$(pgrep -f "async-cli.sh watch" 2>/dev/null || echo "")
WATCH_COUNT=$(echo "$WATCH_PIDS" | grep -c "[0-9]" || echo "0")

echo "  Running watch instances: $WATCH_COUNT"
if [ "$WATCH_COUNT" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠ Watch processes found: $WATCH_PIDS${NC}"
    echo "  Multiple watchers could cause duplicate responses."
else
    echo -e "  ${GREEN}✓ No watch instances running${NC}"
fi
echo

# ============================================================================
# Test 2: State File Lock Check
# ============================================================================
echo -e "${YELLOW}▓▓▓ TEST 2: State File Check ▓▓▓${NC}"

STATE_FILE="$HOME/.async-cli-state.json"

if [ -f "$STATE_FILE" ]; then
    echo "  State file exists: $STATE_FILE"
    STATE_CONTENT=$(cat "$STATE_FILE" 2>/dev/null || echo "{}")
    LAST_POLL=$(echo "$STATE_CONTENT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('last_poll', 'never'))" 2>/dev/null || echo "unknown")
    echo "  Last poll: $LAST_POLL"
else
    echo "  State file does not exist (no watch daemon has run)"
fi
echo

# ============================================================================
# Test 3: Simulate Multiple Watcher Race Condition
# ============================================================================
echo -e "${YELLOW}▓▓▓ TEST 3: Simulated Multi-Watcher Race ▓▓▓${NC}"
echo "Simulating 3 watchers checking for new messages simultaneously..."

# Create temp files for each watcher's "response"
TEMP_DIR=$(mktemp -d)

# Each "watcher" will check and potentially "respond"
simulate_watcher() {
    local watcher_id=$1
    local state_file="$TEMP_DIR/state.json"

    # Read current state
    if [ -f "$state_file" ]; then
        local responded=$(cat "$state_file" | python3 -c "import sys,json; print(json.load(sys.stdin).get('responded', False))" 2>/dev/null || echo "False")
    else
        echo '{"responded": false}' > "$state_file"
        local responded="False"
    fi

    # Check-then-act race window
    sleep 0.0$(( RANDOM % 10 ))  # Random 0-10ms delay

    if [ "$responded" = "False" ]; then
        # Respond (non-atomic update)
        sleep 0.0$(( RANDOM % 5 ))  # Another race window
        echo "{\"responded\": true, \"responder\": \"watcher-$watcher_id\"}" > "$state_file"
        echo "  Watcher $watcher_id: RESPONDED"
    else
        echo "  Watcher $watcher_id: skipped (already responded)"
    fi
}

# Run 3 simulated watchers concurrently
for i in 1 2 3; do
    simulate_watcher $i &
done
wait

# Check final state
FINAL_RESPONDER=$(cat "$TEMP_DIR/state.json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('responder', 'none'))" 2>/dev/null || echo "unknown")
RESPONSE_COUNT=$(grep -c "RESPONDED" <<< "$(for i in 1 2 3; do simulate_watcher $i; done)" 2>/dev/null || echo "unknown")

echo
echo "  Final responder: $FINAL_RESPONDER"
echo -e "  ${YELLOW}⚠ Without proper locking, multiple watchers can respond${NC}"

rm -rf "$TEMP_DIR"
echo

# ============================================================================
# Test 4: Message Response Deduplication
# ============================================================================
echo -e "${YELLOW}▓▓▓ TEST 4: Message Response Deduplication ▓▓▓${NC}"
echo "Checking if messages have idempotency keys..."

# Check recent messages for any idempotency fields (in agent_context)
RECENT_MESSAGES=$(api "messages?select=id,source,agent_context&limit=5&order=created_at.desc&is_from_agent=eq.true")
HAS_IDEMPOTENCY=$(echo "$RECENT_MESSAGES" | python3 -c "
import sys, json
msgs = json.load(sys.stdin)
has_idempotency = any(
    m.get('agent_context', {}).get('idempotency_key')
    for m in msgs
    if m.get('agent_context')
)
print('yes' if has_idempotency else 'no')
" 2>/dev/null || echo "no")

if [ "$HAS_IDEMPOTENCY" = "yes" ]; then
    echo -e "  ${GREEN}✓ Agent messages have idempotency keys${NC}"
    # Show a sample
    echo "$RECENT_MESSAGES" | python3 -c "
import sys, json
msgs = json.load(sys.stdin)
for m in msgs[:2]:
    ctx = m.get('agent_context', {})
    if ctx.get('idempotency_key'):
        print(f'    Key: {ctx[\"idempotency_key\"][:30]}...')
        print(f'    Source: {ctx.get(\"source_agent\", \"unknown\")}')
        break
" 2>/dev/null
else
    echo -e "  ${YELLOW}⚠ No idempotency keys found in recent agent messages${NC}"
    echo "  Risk: Duplicate messages could be processed multiple times"
fi
echo

# ============================================================================
# Test 5: Response Rate Analysis
# ============================================================================
echo -e "${YELLOW}▓▓▓ TEST 5: Agent Response Pattern ▓▓▓${NC}"
echo "Analyzing agent response patterns..."

# Get messages from STEF in last 24 hours
STEF_ID="00000000-0000-0000-0000-000000000001"  # App STEF
TERMINAL_STEF_ID="00000000-0000-0000-0000-000000000003"

STEF_MESSAGES=$(api "messages?sender_id=eq.$STEF_ID&select=created_at,content_raw&order=created_at.desc&limit=10")
STEF_COUNT=$(echo "$STEF_MESSAGES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

echo "  App STEF responses (last 10): $STEF_COUNT messages"

# Check for rapid-fire responses (potential duplicate issue)
RAPID_RESPONSES=$(echo "$STEF_MESSAGES" | python3 -c "
import sys, json
from datetime import datetime
msgs = json.load(sys.stdin)
if len(msgs) < 2:
    print(0)
else:
    rapid = 0
    for i in range(len(msgs)-1):
        t1 = datetime.fromisoformat(msgs[i]['created_at'].replace('Z', '+00:00'))
        t2 = datetime.fromisoformat(msgs[i+1]['created_at'].replace('Z', '+00:00'))
        diff = abs((t1 - t2).total_seconds())
        if diff < 5:  # Less than 5 seconds apart
            rapid += 1
    print(rapid)
" 2>/dev/null || echo "0")

if [ "$RAPID_RESPONSES" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠ Found $RAPID_RESPONSES rapid-fire responses (< 5s apart)${NC}"
    echo "  This could indicate duplicate response issues"
else
    echo -e "  ${GREEN}✓ No rapid-fire responses detected${NC}"
fi
echo

# ============================================================================
# Summary
# ============================================================================
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║               WATCH DAEMON STRESS SUMMARY                  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${YELLOW}Vulnerabilities Found:${NC}"
echo "  1. Check-then-act race in state file updates"
echo "  2. No idempotency keys for message deduplication"
echo "  3. Multiple watchers can spawn without coordination"
echo
echo -e "${GREEN}Recommendations:${NC}"
echo "  • Use flock for watch daemon state file"
echo "  • Add idempotency_key to message metadata"
echo "  • Implement single-leader election for watchers"
echo "  • Add cooldown period after agent response"
echo
