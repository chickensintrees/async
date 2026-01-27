#!/bin/bash
# Sync STEF's identity from GitHub repo to Supabase
# Run this after editing openspec/stef-personality/ files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PERSONALITY_DIR="$REPO_ROOT/openspec/stef-personality"

# Supabase config
SUPABASE_URL="https://ujokdwgpwruyiuioseir.supabase.co"
SUPABASE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqb2tkd2dwd3J1eWl1aW9zZWlyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzNzM0MjQsImV4cCI6MjA4NDk0OTQyNH0.DLz3djC6RGqs0gkhH4XalTUwizcBYFHWnvfG9X-dwxk"
STEF_USER_ID="00000000-0000-0000-0000-000000000001"

echo "🔄 Syncing STEF identity to Supabase..."

# Check if personality files exist
if [[ ! -f "$PERSONALITY_DIR/identity.md" ]] || [[ ! -f "$PERSONALITY_DIR/memories.md" ]]; then
    echo "❌ Missing personality files in $PERSONALITY_DIR"
    exit 1
fi

# Concatenate all personality files into backstory
# Order: soul (meta) → identity (who) → memories (what happened) → origin (founding)
BACKSTORY=""

# Soul (optional but recommended)
if [[ -f "$PERSONALITY_DIR/soul.md" ]]; then
    BACKSTORY+=$(cat "$PERSONALITY_DIR/soul.md")
    BACKSTORY+=$'\n\n---\n\n'
fi

# Identity (required)
BACKSTORY+=$(cat "$PERSONALITY_DIR/identity.md")
BACKSTORY+=$'\n\n---\n\n'

# Memories (required)
BACKSTORY+=$(cat "$PERSONALITY_DIR/memories.md")

# Origin (optional - founding conversation)
if [[ -f "$PERSONALITY_DIR/origin.md" ]]; then
    BACKSTORY+=$'\n\n---\n\n'
    BACKSTORY+=$(cat "$PERSONALITY_DIR/origin.md")
fi

# Write to temp file for jq
TEMP_FILE=$(mktemp)
echo "$BACKSTORY" > "$TEMP_FILE"

# Build JSON payload with proper escaping
JSON_PAYLOAD=$(jq -n --rawfile backstory "$TEMP_FILE" '{backstory: $backstory}')
rm "$TEMP_FILE"

echo "📤 Uploading to Supabase agent_configs..."

# Update Supabase
RESPONSE=$(curl -s -X PATCH "$SUPABASE_URL/rest/v1/agent_configs?user_id=eq.$STEF_USER_ID" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "$JSON_PAYLOAD")

# Check response
if echo "$RESPONSE" | grep -q "backstory"; then
    CHAR_COUNT=$(echo "$BACKSTORY" | wc -c | tr -d ' ')
    echo "✅ STEF identity synced! ($CHAR_COUNT characters)"
    echo ""
    echo "Files synced:"
    [[ -f "$PERSONALITY_DIR/soul.md" ]] && echo "  - openspec/stef-personality/soul.md"
    echo "  - openspec/stef-personality/identity.md"
    echo "  - openspec/stef-personality/memories.md"
    [[ -f "$PERSONALITY_DIR/origin.md" ]] && echo "  - openspec/stef-personality/origin.md"
else
    echo "❌ Failed to sync identity:"
    echo "$RESPONSE"
    exit 1
fi
