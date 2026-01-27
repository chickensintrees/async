#!/bin/bash
# Agent Coordination System for multi-agent awareness
# Usage:
#   agent-coord.sh register "task description"  - Register agent with task
#   agent-coord.sh update "new task"            - Update current task
#   agent-coord.sh heartbeat                    - Update heartbeat timestamp
#   agent-coord.sh status                       - Show all active agents
#   agent-coord.sh deregister                   - Remove agent from coordination
#   agent-coord.sh cleanup                      - Remove stale agents (>15 min no heartbeat)
#   agent-coord.sh json                         - Output raw JSON (for scripts)

COORD_FILE="$HOME/Projects/async/.claude/agent-coordination.json"
COORD_DIR="$(dirname "$COORD_FILE")"
HEARTBEAT_TTL=900  # 15 minutes in seconds

mkdir -p "$COORD_DIR"

# Initialize file if it doesn't exist
if [[ ! -f "$COORD_FILE" ]]; then
    echo '{"agents":[]}' > "$COORD_FILE"
fi

# Get agent ID (same logic as agent-lock.sh for consistency)
AGENT_ID_FILE="$HOME/.claude/agent-id"
if [[ -n "$CLAUDE_AGENT_ID" ]]; then
    AGENT_ID="$CLAUDE_AGENT_ID"
elif [[ -f "$AGENT_ID_FILE" ]]; then
    AGENT_ID=$(cat "$AGENT_ID_FILE")
else
    AGENT_ID="$(hostname -s)-$(date +%s)-$$"
    mkdir -p "$(dirname "$AGENT_ID_FILE")"
    echo "$AGENT_ID" > "$AGENT_ID_FILE"
fi

# Get a short display name from agent ID
get_display_name() {
    local id="$1"
    # Extract meaningful part - hostname or first segment
    echo "$id" | cut -d'-' -f1-2
}

now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

now_epoch() {
    date +%s
}

is_stale() {
    local heartbeat="$1"
    local heartbeat_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$heartbeat" +%s 2>/dev/null || echo 0)
    local now=$(now_epoch)
    local age=$((now - heartbeat_epoch))
    [[ $age -gt $HEARTBEAT_TTL ]]
}

case "$1" in
    register)
        task="${2:-Working on async project}"
        files="${3:-}"

        # Remove existing entry for this agent (if re-registering)
        TEMP=$(mktemp)
        jq --arg id "$AGENT_ID" '.agents = [.agents[] | select(.id != $id)]' "$COORD_FILE" > "$TEMP" && mv "$TEMP" "$COORD_FILE"

        # Add new entry
        TEMP=$(mktemp)
        jq --arg id "$AGENT_ID" \
           --arg task "$task" \
           --arg files "$files" \
           --arg started "$(now_iso)" \
           --arg heartbeat "$(now_iso)" \
           '.agents += [{
               id: $id,
               task: $task,
               files: ($files | split(",") | map(select(. != ""))),
               started: $started,
               heartbeat: $heartbeat
           }]' "$COORD_FILE" > "$TEMP" && mv "$TEMP" "$COORD_FILE"

        echo "REGISTERED: $AGENT_ID"
        echo "Task: $task"
        ;;

    update)
        task="${2:-}"
        files="${3:-}"

        if [[ -z "$task" ]]; then
            echo "Usage: agent-coord.sh update \"task description\" [\"file1,file2\"]"
            exit 1
        fi

        TEMP=$(mktemp)
        jq --arg id "$AGENT_ID" \
           --arg task "$task" \
           --arg files "$files" \
           --arg heartbeat "$(now_iso)" \
           '(.agents[] | select(.id == $id)) |= . + {
               task: $task,
               files: ($files | split(",") | map(select(. != ""))),
               heartbeat: $heartbeat
           }' "$COORD_FILE" > "$TEMP" && mv "$TEMP" "$COORD_FILE"

        echo "UPDATED: $task"
        ;;

    heartbeat)
        TEMP=$(mktemp)
        jq --arg id "$AGENT_ID" \
           --arg heartbeat "$(now_iso)" \
           '(.agents[] | select(.id == $id)).heartbeat = $heartbeat' "$COORD_FILE" > "$TEMP" && mv "$TEMP" "$COORD_FILE"

        echo "HEARTBEAT: $(now_iso)"
        ;;

    deregister)
        TEMP=$(mktemp)
        jq --arg id "$AGENT_ID" '.agents = [.agents[] | select(.id != $id)]' "$COORD_FILE" > "$TEMP" && mv "$TEMP" "$COORD_FILE"

        echo "DEREGISTERED: $AGENT_ID"
        ;;

    status)
        echo "=== Active Agents ==="

        # First cleanup stale entries
        TEMP=$(mktemp)
        NOW=$(now_epoch)
        jq --argjson ttl "$HEARTBEAT_TTL" --argjson now "$NOW" '
            .agents = [.agents[] | select(
                (($now - (.heartbeat | sub("\\.[0-9]+"; "") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)) <= $ttl)
            )]
        ' "$COORD_FILE" > "$TEMP" 2>/dev/null && mv "$TEMP" "$COORD_FILE"

        AGENT_COUNT=$(jq '.agents | length' "$COORD_FILE")

        if [[ "$AGENT_COUNT" -eq 0 ]]; then
            echo "No active agents"
            exit 0
        fi

        echo ""
        jq -r '.agents[] | "[\(.id | split("-")[0:2] | join("-"))]  \(.task)\n         Files: \(if .files | length > 0 then .files | join(", ") else "(none specified)" end)\n         Since: \(.started | split("T")[1] | split("Z")[0]) UTC\n"' "$COORD_FILE"

        echo "─────────────────────────────────────"
        echo "Total: $AGENT_COUNT active agent(s)"
        ;;

    cleanup)
        echo "Cleaning up stale agents..."
        BEFORE=$(jq '.agents | length' "$COORD_FILE")

        TEMP=$(mktemp)
        NOW=$(now_epoch)
        jq --argjson ttl "$HEARTBEAT_TTL" --argjson now "$NOW" '
            .agents = [.agents[] | select(
                (($now - (.heartbeat | sub("\\.[0-9]+"; "") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)) <= $ttl)
            )]
        ' "$COORD_FILE" > "$TEMP" 2>/dev/null && mv "$TEMP" "$COORD_FILE"

        AFTER=$(jq '.agents | length' "$COORD_FILE")
        REMOVED=$((BEFORE - AFTER))

        echo "Removed $REMOVED stale agent(s)"
        ;;

    json)
        # Raw JSON output for other scripts
        cat "$COORD_FILE"
        ;;

    check-conflicts)
        # Check if any other agent is working on specified files
        files="${2:-}"
        if [[ -z "$files" ]]; then
            echo "Usage: agent-coord.sh check-conflicts \"file1,file2\""
            exit 1
        fi

        IFS=',' read -ra CHECK_FILES <<< "$files"
        CONFLICTS=""

        for file in "${CHECK_FILES[@]}"; do
            file=$(echo "$file" | xargs)  # trim whitespace
            CONFLICT=$(jq -r --arg file "$file" --arg myid "$AGENT_ID" '
                .agents[] | select(.id != $myid) | select(.files[] | contains($file)) |
                "  \(.id | split("-")[0:2] | join("-")) is working on \($file)"
            ' "$COORD_FILE" 2>/dev/null)

            if [[ -n "$CONFLICT" ]]; then
                CONFLICTS+="$CONFLICT\n"
            fi
        done

        if [[ -n "$CONFLICTS" ]]; then
            echo "POTENTIAL CONFLICTS:"
            echo -e "$CONFLICTS"
            exit 1
        else
            echo "No conflicts detected"
            exit 0
        fi
        ;;

    sync-github)
        # Sync coordination state to GitHub issue #28
        ISSUE_NUM=28

        # Build markdown table
        AGENT_COUNT=$(jq '.agents | length' "$COORD_FILE")

        if [[ "$AGENT_COUNT" -eq 0 ]]; then
            TABLE="| (none) | - | - | - |"
        else
            TABLE=$(jq -r '.agents[] | "| \(.id | split("-")[0:2] | join("-")) | \(.task) | \(if .files | length > 0 then .files | join(", ") else "-" end) | \(.started | split("T")[1] | split("Z")[0]) UTC |"' "$COORD_FILE")
        fi

        BODY="## Active Agents

This issue tracks active Claude Code agents working on the codebase.

**Auto-updated by Thunderdome.**

---

| Agent | Task | Files | Since |
|-------|------|-------|-------|
$TABLE

---

*Last sync: $(date '+%Y-%m-%d %H:%M:%S')*"

        gh issue edit "$ISSUE_NUM" --body "$BODY" >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            echo "SYNCED to GitHub issue #$ISSUE_NUM"
        else
            echo "SYNC FAILED (check gh auth)"
            exit 1
        fi
        ;;

    *)
        echo "Agent Coordination System"
        echo ""
        echo "Usage: agent-coord.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  register \"task\" [\"files\"]  - Register agent with task and optional file list"
        echo "  update \"task\" [\"files\"]    - Update current task/files"
        echo "  heartbeat                   - Update heartbeat (keeps agent active)"
        echo "  status                      - Show all active agents"
        echo "  deregister                  - Remove this agent from coordination"
        echo "  cleanup                     - Remove stale agents (>15 min inactive)"
        echo "  check-conflicts \"files\"    - Check if files conflict with other agents"
        echo "  json                        - Output raw JSON"
        echo "  sync-github                 - Sync state to GitHub issue #28"
        echo ""
        echo "Your agent ID: $AGENT_ID"
        exit 1
        ;;
esac
