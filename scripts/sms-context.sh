#!/bin/bash
# sms-context.sh - Fetch shared SMS conversation context from Supabase
# Both Bill's and Noah's Claude Code can run this to sync understanding
#
# Usage: ./scripts/sms-context.sh [limit]
#   limit: number of messages to fetch (default: 50)

set -e

# Load environment
ENV_FILE="${ASYNC_ENV_FILE:-$HOME/Projects/async/backend/.env.local}"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: Environment file not found at $ENV_FILE"
    echo "Create backend/.env.local with SUPABASE_URL and SUPABASE_SERVICE_KEY"
    exit 1
fi

source "$ENV_FILE"

LIMIT="${1:-50}"
SMS_CONVERSATION_ID="00000000-0000-0000-0000-000000000002"

# Fetch messages with sender info
RESPONSE=$(curl -s "${SUPABASE_URL}/rest/v1/messages?conversation_id=eq.${SMS_CONVERSATION_ID}&order=created_at.desc&limit=${LIMIT}&select=content_raw,content_processed,is_from_agent,created_at,source,sender:sender_id(display_name,github_handle,phone_number)" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}")

# Check for errors
if echo "$RESPONSE" | grep -q '"error"'; then
    echo "Error fetching messages:"
    echo "$RESPONSE" | jq .
    exit 1
fi

# Display header
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ASYNC SMS GROUP CHAT - Shared Context (last $LIMIT messages)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Parse and display messages (reverse for chronological order)
echo "$RESPONSE" | jq -r '
    reverse | .[] |
    if .is_from_agent then
        "[\(.created_at | split("T")[0])] STEF: \(.content_raw)"
    else
        "[\(.created_at | split("T")[0])] \(.sender.github_handle // .sender.display_name // "Unknown"): \(.content_raw)"
    end
'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Run './scripts/sms-context.sh 100' for more history"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
