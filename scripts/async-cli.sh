#!/bin/bash
# async-cli.sh - CLI interface for STEF to interact with Async app
# Usage:
#   ./scripts/async-cli.sh conversations          # List recent conversations
#   ./scripts/async-cli.sh messages <conv_id>     # Read messages in a conversation
#   ./scripts/async-cli.sh send <conv_id> "msg"   # Send a message as STEF
#   ./scripts/async-cli.sh users                  # List users
#   ./scripts/async-cli.sh unread                 # Check for unread/recent activity

set -e

# Supabase config
SUPABASE_URL="https://ujokdwgpwruyiuioseir.supabase.co"
SUPABASE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqb2tkd2dwd3J1eWl1aW9zZWlyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzNzM0MjQsImV4cCI6MjA4NDk0OTQyNH0.DLz3djC6RGqs0gkhH4XalTUwizcBYFHWnvfG9X-dwxk"

# STEF's user ID (the agent in the database)
STEF_USER_ID=""  # Will be populated by lookup

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

# Get STEF's user ID
get_stef_id() {
    STEF_USER_ID=$(api "users?display_name=eq.STEF&select=id" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null)
    if [ -z "$STEF_USER_ID" ]; then
        echo -e "${RED}Error: Could not find STEF user in database${NC}"
        exit 1
    fi
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

    # Expand short ID to full UUID if needed
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

    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  MESSAGES IN ${conv_id:0:8}...${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"

    api "messages?conversation_id=eq.${conv_id}&select=id,sender_id,content_raw,is_from_agent,created_at,attachments&order=created_at.desc&limit=${limit}" | \
    python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)
# Reverse to show oldest first
for m in reversed(data):
    sender = '🤖 AGENT' if m.get('is_from_agent') else '👤 USER '
    content = m.get('content_raw', '')[:100]
    has_attachment = '📎' if m.get('attachments') else ''
    time = m.get('created_at', '')[:16]
    try:
        dt = datetime.fromisoformat(m.get('created_at', '').replace('Z', '+00:00'))
        time = dt.strftime('%H:%M')
    except:
        pass

    print(f'{time} {sender} {has_attachment}')
    if content:
        # Indent message content
        for line in content.split('\n')[:5]:
            print(f'         {line}')
    print()
"
}

# Send a message as STEF
cmd_send() {
    local conv_id="$1"
    local message="$2"

    if [ -z "$conv_id" ] || [ -z "$message" ]; then
        echo -e "${RED}Usage: async-cli.sh send <conversation_id> \"message\"${NC}"
        exit 1
    fi

    get_stef_id

    # Expand short ID
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

    if [ -z "$conv_id" ]; then
        echo -e "${RED}Conversation not found${NC}"
        exit 1
    fi

    # Create message JSON
    local msg_json=$(python3 -c "
import json, uuid
from datetime import datetime
print(json.dumps({
    'id': str(uuid.uuid4()),
    'conversation_id': '$conv_id',
    'sender_id': '$STEF_USER_ID',
    'content_raw': '''$message''',
    'is_from_agent': True,
    'created_at': datetime.utcnow().isoformat() + 'Z'
}))
")

    result=$(api "messages" "POST" "$msg_json")

    if echo "$result" | grep -q '"id"'; then
        echo -e "${GREEN}✓ Message sent${NC}"
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

    api "messages?created_at=gte.${since}&select=id,conversation_id,sender_id,content_raw,is_from_agent,created_at&order=created_at.desc" | \
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
        time = m.get('created_at', '')[:16]
        try:
            dt = datetime.fromisoformat(m.get('created_at', '').replace('Z', '+00:00'))
            time = dt.strftime('%H:%M')
        except:
            pass
        print(f'  {time} [{conv}] {sender} {content}')
"
    echo ""
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
    *)
        echo -e "${CYAN}async-cli.sh - STEF's interface to Async app${NC}"
        echo ""
        echo "Commands:"
        echo "  conversations, c     List recent conversations"
        echo "  messages, m <id>     Read messages in a conversation"
        echo "  send, s <id> \"msg\"   Send a message as STEF"
        echo "  users, u             List all users"
        echo "  unread, r            Check recent activity"
        echo ""
        echo "Examples:"
        echo "  ./scripts/async-cli.sh c"
        echo "  ./scripts/async-cli.sh m 41204b5f"
        echo "  ./scripts/async-cli.sh s 41204b5f \"Hey, this is STEF from the terminal!\""
        ;;
esac
