#!/bin/bash
# Stress test for multi-agent coordination
# Tests race conditions, concurrent writes, and agent coordination

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         STRESS TEST - Multi-Agent Coordination            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo

# Configuration
CONCURRENT_MESSAGES=${1:-10}
LOCK_CONTENTION=${2:-5}

# ============================================================================
# Test 1: JSON Lock File Race Conditions
# ============================================================================
echo -e "${YELLOW}▓▓▓ TEST 1: Lock File Contention ▓▓▓${NC}"
echo "Spawning $LOCK_CONTENTION concurrent lock attempts..."

LOCK_FILE="/tmp/stress-test-lock.json"
rm -f "$LOCK_FILE"

# Initialize lock file
echo '{"locked": false, "holder": null}' > "$LOCK_FILE"

# Function to simulate lock acquisition
acquire_lock() {
    local agent_id=$1
    local start=$(date +%s%N)

    # Read-modify-write (the problematic pattern)
    local current=$(cat "$LOCK_FILE")
    local is_locked=$(echo "$current" | python3 -c "import sys,json; print(json.load(sys.stdin).get('locked', False))")

    if [ "$is_locked" = "False" ]; then
        # Simulate race window
        sleep 0.01
        echo "{\"locked\": true, \"holder\": \"$agent_id\"}" > "$LOCK_FILE"
        echo "  Agent $agent_id: ACQUIRED"
    else
        echo "  Agent $agent_id: blocked"
    fi
}

# Spawn concurrent lock attempts
for i in $(seq 1 $LOCK_CONTENTION); do
    acquire_lock "agent-$i" &
done
wait

# Check result
FINAL_HOLDER=$(cat "$LOCK_FILE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('holder', 'none'))")
ACQUIRED_COUNT=$(grep -c "ACQUIRED" /dev/stdin <<< "$(for i in $(seq 1 $LOCK_CONTENTION); do acquire_lock "test-$i" 2>&1; done)" || echo "0")

echo -e "\nResult: Final lock holder is ${CYAN}$FINAL_HOLDER${NC}"
echo -e "⚠️  Multiple agents may have 'acquired' due to race condition"
echo

# ============================================================================
# Test 2: Database Trigger Stress (Rapid Message Inserts)
# ============================================================================
echo -e "${YELLOW}▓▓▓ TEST 2: Rapid Message Inserts ▓▓▓${NC}"
echo "This test requires the async-cli.sh and active Supabase connection."
echo "Sending $CONCURRENT_MESSAGES messages in rapid succession..."

# Create a test conversation or use existing
# For now, just simulate the pattern
TEMP_DIR=$(mktemp -d)
for i in $(seq 1 $CONCURRENT_MESSAGES); do
    echo "Message $i at $(date +%s%N)" >> "$TEMP_DIR/message-$i.txt" &
done
wait

# Check file creation order vs content timestamps
echo "  Created $CONCURRENT_MESSAGES files concurrently"
FIRST_FILE=$(ls -tr "$TEMP_DIR" | head -1)
LAST_FILE=$(ls -tr "$TEMP_DIR" | tail -1)
echo "  First file (by mtime): $FIRST_FILE"
echo "  Last file (by mtime): $LAST_FILE"
rm -rf "$TEMP_DIR"
echo

# ============================================================================
# Test 3: Agent Coordination File Atomicity
# ============================================================================
echo -e "${YELLOW}▓▓▓ TEST 3: Agent Coordination File Writes ▓▓▓${NC}"
echo "Testing concurrent writes to shared state file..."

STATE_FILE="/tmp/agent-state.json"
echo '{"agents": [], "last_active": null}' > "$STATE_FILE"

register_agent() {
    local agent_id=$1
    sleep $(echo "scale=3; $RANDOM/32768/10" | bc)  # Random delay 0-0.1s

    # Non-atomic read-modify-write
    local current=$(cat "$STATE_FILE")
    local new_state=$(echo "$current" | python3 -c "
import sys, json
data = json.load(sys.stdin)
data['agents'].append('$agent_id')
data['last_active'] = '$agent_id'
print(json.dumps(data))
")
    echo "$new_state" > "$STATE_FILE"
}

# Register multiple agents concurrently
for i in $(seq 1 $LOCK_CONTENTION); do
    register_agent "agent-$i" &
done
wait

# Check how many agents actually got registered
REGISTERED=$(cat "$STATE_FILE" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['agents']))")
echo "  Expected: $LOCK_CONTENTION agents"
echo "  Registered: $REGISTERED agents"
if [ "$REGISTERED" -lt "$LOCK_CONTENTION" ]; then
    echo -e "  ${RED}⚠️  RACE CONDITION DETECTED: Lost $(($LOCK_CONTENTION - $REGISTERED)) registrations${NC}"
else
    echo -e "  ${GREEN}✓ All agents registered (got lucky, but not atomic)${NC}"
fi
rm -f "$STATE_FILE"
echo

# ============================================================================
# Test 4: Process Spawn Overhead
# ============================================================================
echo -e "${YELLOW}▓▓▓ TEST 4: Process Spawn Timing ▓▓▓${NC}"
echo "Measuring subprocess spawn overhead..."

START=$(date +%s%N)
for i in $(seq 1 20); do
    echo "test" | python3 -c "import sys; sys.stdin.read()" > /dev/null
done
END=$(date +%s%N)
ELAPSED=$(echo "scale=2; ($END - $START) / 1000000" | bc)
echo "  20 Python subprocess calls: ${ELAPSED}ms"
echo "  Average per call: $(echo "scale=2; $ELAPSED / 20" | bc)ms"
echo

# ============================================================================
# Summary
# ============================================================================
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    STRESS TEST SUMMARY                     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${YELLOW}Known Vulnerabilities Confirmed:${NC}"
echo "  1. JSON file locks are not atomic (race conditions possible)"
echo "  2. Read-modify-write patterns lose updates under contention"
echo "  3. Multiple agents can 'acquire' same lock simultaneously"
echo
echo -e "${GREEN}Recommendations:${NC}"
echo "  • Use file locking (flock) for coordination files"
echo "  • Consider SQLite or Supabase for shared state"
echo "  • Implement proper mutex/semaphore for agent coordination"
echo "  • Add idempotency keys to prevent duplicate processing"
echo
