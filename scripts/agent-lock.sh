#!/bin/bash
# Agent file locking system for multi-agent coordination
# Usage:
#   agent-lock.sh check <file>     - Check if file is locked (exit 0 if free, 1 if locked)
#   agent-lock.sh acquire <file>   - Acquire lock on file
#   agent-lock.sh release <file>   - Release lock on file
#   agent-lock.sh status           - Show all current locks
#   agent-lock.sh cleanup          - Remove stale locks (>10 min old)

LOCK_DIR="$HOME/Projects/async/.agent-locks"
LOCK_TTL=600  # 10 minutes in seconds

mkdir -p "$LOCK_DIR"

# Get agent ID - priority: env var > persisted file > generate new
# This ensures consistent ID across script invocations in same session
AGENT_ID_FILE="$HOME/.claude/agent-id"
if [[ -n "$CLAUDE_AGENT_ID" ]]; then
    AGENT_ID="$CLAUDE_AGENT_ID"
elif [[ -f "$AGENT_ID_FILE" ]]; then
    AGENT_ID=$(cat "$AGENT_ID_FILE")
else
    # Generate and persist a new ID
    AGENT_ID="$(hostname)-$(date +%s)-$$"
    mkdir -p "$(dirname "$AGENT_ID_FILE")"
    echo "$AGENT_ID" > "$AGENT_ID_FILE"
fi

get_lock_file() {
    local file="$1"
    local safe_name=$(echo "$file" | sed 's/[\/]/_/g')
    echo "$LOCK_DIR/${safe_name}.lock"
}

is_lock_stale() {
    local lock_file="$1"
    if [[ ! -f "$lock_file" ]]; then
        return 0  # No lock = stale
    fi
    local lock_time=$(jq -r '.timestamp' "$lock_file" 2>/dev/null)
    local now=$(date +%s)
    local age=$((now - lock_time))
    [[ $age -gt $LOCK_TTL ]]
}

case "$1" in
    check)
        file="$2"
        lock_file=$(get_lock_file "$file")

        if [[ ! -f "$lock_file" ]]; then
            echo "FREE"
            exit 0
        fi

        if is_lock_stale "$lock_file"; then
            echo "STALE"
            exit 0
        fi

        owner=$(jq -r '.agent' "$lock_file")
        working_on=$(jq -r '.working_on // "unknown"' "$lock_file")
        echo "LOCKED by $owner ($working_on)"
        exit 1
        ;;

    acquire)
        file="$2"
        description="${3:-editing}"
        lock_file=$(get_lock_file "$file")
        mutex_dir="${lock_file}.mutex"

        # Use mkdir for atomic mutex (works on all POSIX systems including macOS)
        # mkdir is atomic - only one process can create a directory
        max_attempts=50
        attempt=0
        while ! mkdir "$mutex_dir" 2>/dev/null; do
            attempt=$((attempt + 1))
            if [[ $attempt -ge $max_attempts ]]; then
                echo "ERROR: Could not acquire mutex after $max_attempts attempts"
                exit 1
            fi
            sleep 0.1
        done

        # We have the mutex - now do the check-and-acquire atomically
        cleanup_mutex() {
            rmdir "$mutex_dir" 2>/dev/null
        }
        trap cleanup_mutex EXIT

        # Check if already locked by someone else
        if [[ -f "$lock_file" ]] && ! is_lock_stale "$lock_file"; then
            owner=$(jq -r '.agent' "$lock_file")
            if [[ "$owner" != "$AGENT_ID" ]]; then
                echo "ERROR: File locked by $owner"
                cleanup_mutex
                exit 1
            fi
        fi

        # Acquire lock (atomic within mutex)
        cat > "$lock_file" << LOCKEOF
{
    "agent": "$AGENT_ID",
    "file": "$file",
    "working_on": "$description",
    "timestamp": $(date +%s),
    "acquired": "$(date -Iseconds)"
}
LOCKEOF
        echo "ACQUIRED lock on $file"
        cleanup_mutex
        exit 0
        ;;

    release)
        file="$2"
        lock_file=$(get_lock_file "$file")
        mutex_dir="${lock_file}.mutex"

        # Use mkdir for atomic mutex
        max_attempts=50
        attempt=0
        while ! mkdir "$mutex_dir" 2>/dev/null; do
            attempt=$((attempt + 1))
            if [[ $attempt -ge $max_attempts ]]; then
                echo "ERROR: Could not acquire mutex for release"
                exit 1
            fi
            sleep 0.1
        done

        cleanup_mutex() {
            rmdir "$mutex_dir" 2>/dev/null
        }
        trap cleanup_mutex EXIT

        if [[ -f "$lock_file" ]]; then
            owner=$(jq -r '.agent' "$lock_file")
            if [[ "$owner" == "$AGENT_ID" ]] || is_lock_stale "$lock_file"; then
                rm "$lock_file"
                echo "RELEASED lock on $file"
                cleanup_mutex
                exit 0
            else
                echo "ERROR: Cannot release lock owned by $owner"
                cleanup_mutex
                exit 1
            fi
        fi
        echo "No lock to release"
        cleanup_mutex
        exit 0
        ;;

    status)
        echo "=== Active Agent Locks ==="
        if [[ -z "$(ls -A $LOCK_DIR 2>/dev/null)" ]]; then
            echo "No active locks"
            exit 0
        fi

        for lock_file in "$LOCK_DIR"/*.lock; do
            [[ -f "$lock_file" ]] || continue

            if is_lock_stale "$lock_file"; then
                status="STALE"
            else
                status="ACTIVE"
            fi

            agent=$(jq -r '.agent' "$lock_file")
            file=$(jq -r '.file' "$lock_file")
            working_on=$(jq -r '.working_on' "$lock_file")
            acquired=$(jq -r '.acquired' "$lock_file")

            echo "[$status] $file"
            echo "         Agent: $agent"
            echo "         Task: $working_on"
            echo "         Since: $acquired"
            echo ""
        done
        ;;

    cleanup)
        echo "Cleaning up stale locks..."
        for lock_file in "$LOCK_DIR"/*.lock; do
            [[ -f "$lock_file" ]] || continue
            if is_lock_stale "$lock_file"; then
                file=$(jq -r '.file' "$lock_file")
                rm "$lock_file"
                echo "Removed stale lock: $file"
            fi
        done
        ;;

    *)
        echo "Usage: agent-lock.sh {check|acquire|release|status|cleanup} [file] [description]"
        exit 1
        ;;
esac
