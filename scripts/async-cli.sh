#!/bin/bash
# async-cli.sh - CLI interface for STEF to interact with Async app
# Usage:
#   ./scripts/async-cli.sh conversations          # List recent conversations
#   ./scripts/async-cli.sh messages <conv_id>     # Read messages in a conversation
#   ./scripts/async-cli.sh send <conv_id> "msg"   # Send a message as Terminal STEF
#   ./scripts/async-cli.sh users                  # List users
#   ./scripts/async-cli.sh unread                 # Check for unread/recent activity
#   ./scripts/async-cli.sh watch                  # Start watch daemon (responds to human messages)
#   ./scripts/async-cli.sh stop                   # Stop watch daemon
#   ./scripts/async-cli.sh status                 # Check if watch daemon is running
#   ./scripts/async-cli.sh respond <conv_id>      # Manually trigger response in conversation
#   ./scripts/async-cli.sh context <conv_id>      # Preview what context STEF would see

set -e

# Supabase config
SUPABASE_URL="https://ujokdwgpwruyiuioseir.supabase.co"
SUPABASE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqb2tkd2dwd3J1eWl1aW9zZWlyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzNzM0MjQsImV4cCI6MjA4NDk0OTQyNH0.DLz3djC6RGqs0gkhH4XalTUwizcBYFHWnvfG9X-dwxk"

# State file for watch daemon
STATE_FILE="$HOME/.async-cli-state.json"

# Terminal STEF's user ID (the terminal-side agent in the database)
STEF_USER_ID=""  # Will be populated by lookup for "Terminal STEF"

# Poll interval for watch mode (seconds)
POLL_INTERVAL="${ASYNC_POLL_INTERVAL:-3}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Get Terminal STEF's user ID
get_stef_id() {
    if [ -n "$STEF_USER_ID" ]; then
        return
    fi
    STEF_USER_ID=$(api "users?display_name=eq.Terminal%20STEF&select=id" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null)
    if [ -z "$STEF_USER_ID" ]; then
        echo -e "${RED}Error: Could not find Terminal STEF user in database${NC}"
        exit 1
    fi
}

# Expand short conversation ID to full UUID
expand_conv_id() {
    local conv_id="$1"
    if [ ${#conv_id} -lt 36 ]; then
        conv_id=$(api "conversations?select=id" | python3 -c "
import sys,json
prefix='$conv_id'
for c in json.load(sys.stdin):
    if c['id'].startswith(prefix):
        print(c['id'])
        break
" 2>/dev/null)
    fi
    echo "$conv_id"
}

# List conversations
cmd_conversations() {
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}  ASYNC CONVERSATIONS${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"

    api "conversations?select=id,title,mode,last_message_at,kind&order=last_message_at.desc&limit=10" | \
    python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)
for c in data:
    cid = c['id'][:8]
    title = c.get('title') or 'Untitled'
    mode = c.get('mode', 'direct')
    kind = c.get('kind', '')
    last = c.get('last_message_at', '')
    if last:
        # Parse and format time
        try:
            dt = datetime.fromisoformat(last.replace('Z', '+00:00'))
            last = dt.strftime('%b %d %H:%M')
        except:
            last = last[:16]

    mode_icon = {'anonymous': '👁️', 'assisted': '✨', 'direct': '↔️'}.get(mode, '?')
    print(f'  {cid}  {mode_icon} {title[:30]:<30}  {last}')
"
    echo ""
}

# Read messages in a conversation
cmd_messages() {
    local conv_id="$1"
    local limit="${2:-20}"

    if [ -z "$conv_id" ]; then
        echo -e "${RED}Usage: async-cli.sh messages <conversation_id> [limit]${NC}"
        exit 1
    fi

    conv_id=$(expand_conv_id "$conv_id")

    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  MESSAGES IN ${conv_id:0:8}...${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"

    api "messages?conversation_id=eq.${conv_id}&select=id,sender_id,content_raw,is_from_agent,created_at,attachments,source&order=created_at.desc&limit=${limit}" | \
    python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)
# Reverse to show oldest first
for m in reversed(data):
    sender = '🤖 AGENT' if m.get('is_from_agent') else '👤 USER '
    content = m.get('content_raw', '')[:100]
    has_attachment = '📎' if m.get('attachments') else ''
    source = m.get('source', 'app')
    source_tag = f'[{source}]' if source != 'app' else ''
    time = m.get('created_at', '')[:16]
    try:
        dt = datetime.fromisoformat(m.get('created_at', '').replace('Z', '+00:00'))
        time = dt.strftime('%H:%M')
    except:
        pass

    print(f'{time} {sender} {source_tag}{has_attachment}')
    if content:
        # Indent message content
        for line in content.split('\n')[:5]:
            print(f'         {line}')
    print()
"
}

# Send a message as Terminal STEF
cmd_send() {
    local conv_id="$1"
    local message="$2"

    if [ -z "$conv_id" ] || [ -z "$message" ]; then
        echo -e "${RED}Usage: async-cli.sh send <conversation_id> \"message\"${NC}"
        exit 1
    fi

    get_stef_id
    conv_id=$(expand_conv_id "$conv_id")

    if [ -z "$conv_id" ]; then
        echo -e "${RED}Conversation not found${NC}"
        exit 1
    fi

    # Create message JSON with source: terminal and idempotency key
    local idempotency_key=$(uuidgen | tr '[:upper:]' '[:lower:]')
    local msg_json=$(python3 -c "
import json, uuid
from datetime import datetime
print(json.dumps({
    'id': str(uuid.uuid4()),
    'conversation_id': '$conv_id',
    'sender_id': '$STEF_USER_ID',
    'content_raw': '''$message''',
    'is_from_agent': True,
    'source': 'terminal',
    'created_at': datetime.utcnow().isoformat() + 'Z',
    'agent_context': {
        'idempotency_key': '$idempotency_key',
        'source_agent': 'terminal-stef'
    }
}))
")

    result=$(api "messages" "POST" "$msg_json")

    if echo "$result" | grep -q '"id"'; then
        # Update conversation's last_message_at so it appears in cross-conversation context
        local now=$(python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')")
        api "conversations?id=eq.${conv_id}" "PATCH" "{\"last_message_at\": \"$now\"}" > /dev/null 2>&1
        echo -e "${GREEN}✓ Message sent (source: terminal)${NC}"
    else
        echo -e "${RED}Error sending message: $result${NC}"
    fi
}

# List users
cmd_users() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  USERS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

    api "users?select=id,display_name,github_handle,user_type&order=display_name" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for u in data:
    uid = u['id'][:8]
    name = u.get('display_name') or 'Unknown'
    gh = u.get('github_handle') or ''
    utype = '🤖' if u.get('user_type') == 'agent' else '👤'
    print(f'  {uid}  {utype} {name:<20} @{gh}')
"
    echo ""
}

# Check recent activity
cmd_unread() {
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  RECENT ACTIVITY (last hour)${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

    # Get messages from last hour
    local since=$(python3 -c "from datetime import datetime, timedelta; print((datetime.utcnow() - timedelta(hours=1)).isoformat() + 'Z')")

    api "messages?created_at=gte.${since}&select=id,conversation_id,sender_id,content_raw,is_from_agent,created_at,source&order=created_at.desc" | \
    python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)
if not data:
    print('  No recent messages')
else:
    print(f'  {len(data)} message(s) in the last hour')
    print()
    for m in data[:10]:
        sender = '🤖' if m.get('is_from_agent') else '👤'
        content = (m.get('content_raw', '') or '')[:60].replace('\n', ' ')
        conv = m.get('conversation_id', '')[:8]
        source = m.get('source', 'app')
        source_tag = f'[{source}]' if source != 'app' else ''
        time = m.get('created_at', '')[:16]
        try:
            dt = datetime.fromisoformat(m.get('created_at', '').replace('Z', '+00:00'))
            time = dt.strftime('%H:%M')
        except:
            pass
        print(f'  {time} [{conv}] {sender}{source_tag} {content}')
"
    echo ""
}

# Preview context STEF would see for a conversation
cmd_context() {
    local conv_id="$1"
    local limit="${2:-20}"

    if [ -z "$conv_id" ]; then
        echo -e "${RED}Usage: async-cli.sh context <conversation_id> [limit]${NC}"
        exit 1
    fi

    conv_id=$(expand_conv_id "$conv_id")

    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  STEF'S CONTEXT FOR ${conv_id:0:8}...${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"

    # Get conversation info
    local conv_info=$(api "conversations?id=eq.${conv_id}&select=id,title,mode")

    # Get messages with sender info
    api "messages?conversation_id=eq.${conv_id}&select=content_raw,is_from_agent,created_at,sender:users!messages_sender_id_fkey(display_name)&order=created_at.desc&limit=${limit}" | \
    python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)
print('Recent conversation:')
print('---')
# Reverse to chronological
for m in reversed(data):
    sender_data = m.get('sender')
    if m.get('is_from_agent'):
        sender = 'STEF'
    elif isinstance(sender_data, dict):
        sender = sender_data.get('display_name', 'User')
    else:
        sender = 'User'
    content = m.get('content_raw', '')
    time = m.get('created_at', '')[:16]
    try:
        dt = datetime.fromisoformat(m.get('created_at', '').replace('Z', '+00:00'))
        time = dt.strftime('%H:%M')
    except:
        pass
    print(f'[{time}] {sender}: {content}')
print('---')
print(f'Total: {len(data)} messages')
"
}

# Check watch daemon status
cmd_status() {
    if [ -f "$STATE_FILE" ]; then
        local pid=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('watch_pid', ''))" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            local last_checked=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('last_checked_at', 'unknown'))" 2>/dev/null)
            echo -e "${GREEN}✓ Watch daemon running (PID: $pid)${NC}"
            echo -e "  Last checked: $last_checked"
        else
            echo -e "${YELLOW}⚠ Watch daemon not running (stale state file)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Watch daemon not running${NC}"
    fi
}

# Stop watch daemon
cmd_stop() {
    local leader_lock="$HOME/.async-watch-leader.lock"
    local stopped=false

    if [ -f "$STATE_FILE" ]; then
        local pid=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('watch_pid', ''))" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            echo -e "${GREEN}✓ Watch daemon stopped (PID: $pid)${NC}"
            stopped=true
        fi
        rm -f "$STATE_FILE"
    fi

    # Also clean up leader lock
    if [ -d "$leader_lock" ]; then
        rm -rf "$leader_lock"
        echo -e "${GREEN}✓ Leader lock released${NC}"
        stopped=true
    fi

    if ! $stopped; then
        echo -e "${YELLOW}Watch daemon not running${NC}"
    fi
}

# Generate STEF response for a message
generate_response() {
    local conv_id="$1"
    local message_content="$2"
    local sender_name="$3"

    # Check for ANTHROPIC_API_KEY
    if [ -z "$ANTHROPIC_API_KEY" ]; then
        # Try to read from config
        if [ -f "$HOME/.claude/config.json" ]; then
            ANTHROPIC_API_KEY=$(python3 -c "import json; print(json.load(open('$HOME/.claude/config.json')).get('api_keys', {}).get('anthropic', ''))" 2>/dev/null)
        fi
    fi

    if [ -z "$ANTHROPIC_API_KEY" ]; then
        echo -e "${RED}Error: ANTHROPIC_API_KEY not set. Set it in environment or ~/.claude/config.json${NC}" >&2
        return 1
    fi

    # Load STEF's system prompt from agent_configs (or use fallback)
    local system_prompt=$(api "agent_configs?user_id=eq.${STEF_USER_ID}&select=system_prompt" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data and data[0].get('system_prompt'):
    print(data[0]['system_prompt'])
else:
    print('''You are STEF, an AI agent in the Async messaging app.
You are helpful, witty, and conversational. Keep responses relatively brief.
Don't use excessive formatting - this is a chat, not documentation.''')
" 2>/dev/null)

    # Build conversation context
    local context=$(api "messages?conversation_id=eq.${conv_id}&select=content_raw,is_from_agent,created_at,sender:users!messages_sender_id_fkey(display_name)&order=created_at.desc&limit=20" | python3 -c "
import sys, json

data = json.load(sys.stdin)
lines = []
# Reverse to chronological
for m in reversed(data):
    sender_data = m.get('sender')
    if m.get('is_from_agent'):
        sender = 'STEF'
    elif isinstance(sender_data, dict):
        sender = sender_data.get('display_name', 'User')
    else:
        sender = 'User'
    content = m.get('content_raw', '')
    lines.append(f'{sender}: {content}')
print('\n'.join(lines))
" 2>/dev/null)

    # Call Claude API using temp files to avoid shell escaping issues
    local tmp_system=$(mktemp)
    local tmp_context=$(mktemp)
    local tmp_sender=$(mktemp)
    printf '%s' "$system_prompt" > "$tmp_system"
    printf '%s' "$context" > "$tmp_context"
    printf '%s' "$sender_name" > "$tmp_sender"

    local response=$(ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
        TMP_SYSTEM="$tmp_system" \
        TMP_CONTEXT="$tmp_context" \
        TMP_SENDER="$tmp_sender" \
        python3 << 'PYTHON_SCRIPT'
import json
import os

# Read from temp files
with open(os.environ['TMP_SYSTEM']) as f:
    system = f.read()
with open(os.environ['TMP_CONTEXT']) as f:
    context = f.read()
with open(os.environ['TMP_SENDER']) as f:
    sender = f.read()

payload = json.dumps({
    'model': 'claude-sonnet-4-20250514',
    'max_tokens': 1024,
    'system': system,
    'messages': [{
        'role': 'user',
        'content': f'Recent conversation:\n{context}\n\nRespond to the latest message from {sender}.'
    }]
})

api_key = os.environ.get('ANTHROPIC_API_KEY', '')

import urllib.request
req = urllib.request.Request(
    'https://api.anthropic.com/v1/messages',
    data=payload.encode('utf-8'),
    headers={
        'x-api-key': api_key,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json'
    }
)
try:
    with urllib.request.urlopen(req) as resp:
        print(resp.read().decode('utf-8'))
except urllib.error.HTTPError as e:
    print(e.read().decode('utf-8'))
PYTHON_SCRIPT
)

    # Clean up temp files
    rm -f "$tmp_system" "$tmp_context" "$tmp_sender"

    # Extract response text
    local text=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'content' in data and len(data['content']) > 0:
        print(data['content'][0].get('text', ''))
    elif 'error' in data:
        print(f'Error: {data[\"error\"].get(\"message\", \"Unknown error\")}', file=sys.stderr)
except Exception as e:
    print(f'Error parsing response: {e}', file=sys.stderr)
" 2>/dev/null)

    echo "$text"
}

# Manually trigger response in a conversation
cmd_respond() {
    local conv_id="$1"

    if [ -z "$conv_id" ]; then
        echo -e "${RED}Usage: async-cli.sh respond <conversation_id>${NC}"
        exit 1
    fi

    get_stef_id
    conv_id=$(expand_conv_id "$conv_id")

    if [ -z "$conv_id" ]; then
        echo -e "${RED}Conversation not found${NC}"
        exit 1
    fi

    echo -e "${CYAN}Generating response...${NC}"

    # Get the last message
    local last_msg=$(api "messages?conversation_id=eq.${conv_id}&is_from_agent=eq.false&select=content_raw,sender:users!messages_sender_id_fkey(display_name)&order=created_at.desc&limit=1")
    local content=$(echo "$last_msg" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['content_raw'] if d else '')" 2>/dev/null)
    local sender=$(echo "$last_msg" | python3 -c "import sys,json; d=json.load(sys.stdin); print((d[0].get('sender') or {}).get('display_name', 'User') if d else 'User')" 2>/dev/null)

    if [ -z "$content" ]; then
        echo -e "${YELLOW}No human messages to respond to${NC}"
        return
    fi

    # Generate response
    local response=$(generate_response "$conv_id" "$content" "$sender")

    if [ -z "$response" ]; then
        echo -e "${RED}Failed to generate response${NC}"
        return 1
    fi

    # Generate idempotency key based on conversation (manual trigger)
    local idempotency_key="manual-$(echo "$conv_id-$(date +%s)" | md5sum | cut -c1-16)"

    # Insert response with idempotency key
    local msg_json=$(python3 -c "
import json, uuid
from datetime import datetime
print(json.dumps({
    'id': str(uuid.uuid4()),
    'conversation_id': '$conv_id',
    'sender_id': '$STEF_USER_ID',
    'content_raw': '''$response''',
    'is_from_agent': True,
    'source': 'app',
    'created_at': datetime.utcnow().isoformat() + 'Z',
    'agent_context': {
        'idempotency_key': '$idempotency_key',
        'source_agent': 'terminal-stef',
        'trigger': 'manual'
    }
}))
")

    result=$(api "messages" "POST" "$msg_json")

    if echo "$result" | grep -q '"id"'; then
        echo -e "${GREEN}✓ Response sent${NC}"
        echo -e "${PURPLE}STEF:${NC} ${response:0:200}..."
    else
        echo -e "${RED}Error sending response: $result${NC}"
    fi
}

# Watch mode - poll for new messages and respond
cmd_watch() {
    local background=false
    if [ "$1" = "--background" ] || [ "$1" = "-b" ]; then
        background=true
    fi

    get_stef_id

    # Pre-check for existing leader (before banner)
    local leader_lock="$HOME/.async-watch-leader.lock"
    if [ -d "$leader_lock" ]; then
        local existing_pid=""
        if [ -f "${leader_lock}/pid" ]; then
            existing_pid=$(cat "${leader_lock}/pid" 2>/dev/null)
        fi
        if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
            echo -e "${RED}ERROR: Another watch daemon is already running (PID: $existing_pid)${NC}"
            echo -e "  Run './scripts/async-cli.sh stop' first"
            exit 1
        fi
    fi

    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  STEF WATCH MODE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "  Polling interval: ${POLL_INTERVAL}s"
    echo -e "  STEF user ID: ${STEF_USER_ID:0:8}..."
    echo ""

    if $background; then
        echo -e "${YELLOW}Starting in background...${NC}"
        nohup "$0" watch_loop > /dev/null 2>&1 &
        local pid=$!
        # Wait briefly for the background process to acquire leader lock
        sleep 0.5
        python3 -c "
import json
with open('$STATE_FILE', 'w') as f:
    json.dump({'watch_pid': $pid, 'last_checked_at': None}, f)
"
        echo -e "${GREEN}✓ Watch daemon started (PID: $pid)${NC}"
        echo -e "  Run 'async-cli stop' to stop"
        return
    fi

    # Run watch loop in foreground
    watch_loop
}

# Internal: watch loop with single-leader election
watch_loop() {
    get_stef_id

    # Single-leader election using mkdir mutex
    local leader_lock="$HOME/.async-watch-leader.lock"

    # Check if another watcher is already running
    if [ -d "$leader_lock" ]; then
        # Check if the process is still alive
        local existing_pid=""
        if [ -f "${leader_lock}/pid" ]; then
            existing_pid=$(cat "${leader_lock}/pid" 2>/dev/null)
        fi

        if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
            echo -e "${RED}ERROR: Another watch daemon is already running (PID: $existing_pid)${NC}"
            echo -e "  Run './scripts/async-cli.sh stop' first, or kill PID $existing_pid"
            exit 1
        else
            # Stale lock - remove it
            echo -e "${YELLOW}Removing stale leader lock...${NC}"
            rm -rf "$leader_lock"
        fi
    fi

    # Try to acquire leader lock (atomic mkdir)
    if ! mkdir "$leader_lock" 2>/dev/null; then
        echo -e "${RED}ERROR: Could not acquire leader lock (race condition)${NC}"
        exit 1
    fi

    # Write our PID to the lock
    echo $$ > "${leader_lock}/pid"

    # Cleanup function to release leader lock
    cleanup_leader() {
        rm -rf "$leader_lock" 2>/dev/null
        echo -e "\n${YELLOW}Released leader lock${NC}"
    }
    trap "cleanup_leader; exit 0" INT TERM EXIT

    echo -e "${GREEN}✓ Acquired leader lock (PID: $$)${NC}"

    local last_checked=$(python3 -c "from datetime import datetime, timedelta; print((datetime.utcnow() - timedelta(seconds=10)).isoformat() + 'Z')")

    # Save initial state
    python3 -c "
import json
with open('$STATE_FILE', 'w') as f:
    json.dump({'watch_pid': $$, 'last_checked_at': '$last_checked'}, f)
"

    echo -e "${GREEN}✓ Watch mode active. Press Ctrl+C to stop.${NC}"
    echo ""

    trap "echo -e '\n${YELLOW}Stopping watch mode...${NC}'; rm -f '$STATE_FILE'; exit 0" INT TERM

    while true; do
        # Get conversations where STEF is a participant
        local stef_convos=$(api "conversation_participants?user_id=eq.${STEF_USER_ID}&select=conversation_id")

        # Get new messages from humans since last check
        local new_messages=$(api "messages?created_at=gt.${last_checked}&is_from_agent=eq.false&select=id,conversation_id,content_raw,sender:users!messages_sender_id_fkey(display_name),created_at&order=created_at.asc")

        # Process each new message (now includes message ID for idempotency)
        echo "$new_messages" | python3 -c "
import sys, json

stef_convos = set()
try:
    stef_data = json.loads('''$stef_convos''')
    stef_convos = {c['conversation_id'] for c in stef_data}
except:
    pass

messages = json.load(sys.stdin)
for m in messages:
    conv_id = m.get('conversation_id', '')
    if conv_id in stef_convos:
        msg_id = m.get('id', '')
        sender = (m.get('sender') or {}).get('display_name', 'User')
        content = m.get('content_raw', '')[:50]
        print(f'RESPOND|{conv_id}|{msg_id}|{sender}|{content}')
" 2>/dev/null | while IFS='|' read -r action conv_id trigger_msg_id sender content; do
            if [ "$action" = "RESPOND" ]; then
                # Generate idempotency key based on triggering message
                local idempotency_key="response-to-${trigger_msg_id}"

                # Check if we already responded to this message (idempotency check)
                local existing=$(api "messages?conversation_id=eq.${conv_id}&is_from_agent=eq.true&agent_context->>idempotency_key=eq.${idempotency_key}&select=id" 2>/dev/null)
                if echo "$existing" | grep -q '"id"'; then
                    echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} Already responded to ${trigger_msg_id:0:8}, skipping"
                    continue
                fi

                echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} New message from ${sender} in ${conv_id:0:8}..."
                echo -e "  ${content}..."

                # Generate and send response with idempotency key
                local response=$(generate_response "$conv_id" "$content" "$sender")
                if [ -n "$response" ]; then
                    local msg_json=$(python3 -c "
import json, uuid
from datetime import datetime
print(json.dumps({
    'id': str(uuid.uuid4()),
    'conversation_id': '$conv_id',
    'sender_id': '$STEF_USER_ID',
    'content_raw': '''$response''',
    'is_from_agent': True,
    'source': 'app',
    'created_at': datetime.utcnow().isoformat() + 'Z',
    'agent_context': {
        'idempotency_key': '$idempotency_key',
        'trigger_message_id': '$trigger_msg_id',
        'source_agent': 'terminal-stef-watch'
    }
}))
")
                    api "messages" "POST" "$msg_json" > /dev/null
                    echo -e "${GREEN}  ✓ Responded${NC}"
                fi
            fi
        done

        # Update last checked
        last_checked=$(python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')")
        python3 -c "
import json
with open('$STATE_FILE', 'w') as f:
    json.dump({'watch_pid': $$, 'last_checked_at': '$last_checked'}, f)
"

        sleep "$POLL_INTERVAL"
    done
}

# Main
case "${1:-}" in
    conversations|convos|c)
        cmd_conversations
        ;;
    messages|msgs|m)
        cmd_messages "$2" "$3"
        ;;
    send|s)
        cmd_send "$2" "$3"
        ;;
    users|u)
        cmd_users
        ;;
    unread|recent|r)
        cmd_unread
        ;;
    context|ctx)
        cmd_context "$2" "$3"
        ;;
    respond|reply)
        cmd_respond "$2"
        ;;
    watch|w)
        cmd_watch "$2"
        ;;
    watch_loop)
        watch_loop
        ;;
    stop)
        cmd_stop
        ;;
    status|st)
        cmd_status
        ;;
    *)
        echo -e "${CYAN}async-cli.sh - STEF's interface to Async app${NC}"
        echo ""
        echo "Commands:"
        echo "  conversations, c     List recent conversations"
        echo "  messages, m <id>     Read messages in a conversation"
        echo "  send, s <id> \"msg\"   Send a message as Terminal STEF"
        echo "  users, u             List all users"
        echo "  unread, r            Check recent activity"
        echo ""
        echo -e "${YELLOW}Watch Mode:${NC}"
        echo "  watch, w             Start watch daemon (respond to humans)"
        echo "  watch --background   Start in background"
        echo "  stop                 Stop watch daemon"
        echo "  status, st           Check if daemon is running"
        echo ""
        echo -e "${YELLOW}Response Tools:${NC}"
        echo "  respond, reply <id>  Manually trigger response"
        echo "  context, ctx <id>    Preview STEF's context"
        echo ""
        echo "Examples:"
        echo "  ./scripts/async-cli.sh c"
        echo "  ./scripts/async-cli.sh m 41204b5f"
        echo "  ./scripts/async-cli.sh s 41204b5f \"Hey from terminal!\""
        echo "  ./scripts/async-cli.sh watch"
        ;;
esac
