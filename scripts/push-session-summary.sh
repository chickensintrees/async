#!/bin/bash
# Push a session summary to Supabase agent_context table
# Usage: push-session-summary.sh "Summary text" "Optional title"
#    or: STEF_SESSION_SUMMARY="text" push-session-summary.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Supabase config
SUPABASE_URL="https://ujokdwgpwruyiuioseir.supabase.co"
SUPABASE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqb2tkd2dwd3J1eWl1aW9zZWlyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzNzM0MjQsImV4cCI6MjA4NDk0OTQyNH0.DLz3djC6RGqs0gkhH4XalTUwizcBYFHWnvfG9X-dwxk"
STEF_USER_ID="00000000-0000-0000-0000-000000000001"

# Get summary from argument or environment variable
SUMMARY="${1:-$STEF_SESSION_SUMMARY}"
TITLE="${2:-Session $(date '+%Y-%m-%d %H:%M')}"

if [[ -z "$SUMMARY" ]]; then
    echo "❌ No session summary provided"
    echo "Usage: push-session-summary.sh \"Summary text\" \"Optional title\""
    echo "   or: STEF_SESSION_SUMMARY=\"text\" push-session-summary.sh"
    exit 1
fi

echo "📤 Pushing session summary to agent_context..."

# Build JSON payload (let Supabase auto-generate ID)
JSON_PAYLOAD=$(jq -n \
    --arg context_type "session_summary" \
    --arg title "$TITLE" \
    --arg content "$SUMMARY" \
    --arg participant "$STEF_USER_ID" \
    '{
        context_type: $context_type,
        title: $title,
        content: $content,
        participants: [$participant]
    }')

# Insert into Supabase
RESPONSE=$(curl -s -X POST "$SUPABASE_URL/rest/v1/agent_context" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "$JSON_PAYLOAD")

# Check response
if echo "$RESPONSE" | grep -q "session_summary"; then
    echo "✅ Session summary pushed!"
    echo "   Title: $TITLE"
    echo "   Length: ${#SUMMARY} characters"
elif echo "$RESPONSE" | grep -q "row-level security"; then
    echo "❌ RLS policy blocking insert. Apply migration 008:"
    echo ""
    echo "   Run this SQL in Supabase Dashboard > SQL Editor:"
    echo ""
    echo "   CREATE POLICY \"Agent context is insertable\""
    echo "       ON agent_context FOR INSERT"
    echo "       TO anon, authenticated"
    echo "       WITH CHECK (true);"
    echo ""
    exit 1
else
    echo "❌ Failed to push session summary:"
    echo "$RESPONSE"
    exit 1
fi
