#!/bin/bash
# Update STEF's knowledge_base with current repo context
# Run this after significant changes or before sessions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/app"

# Supabase config
SUPABASE_URL="https://ujokdwgpwruyiuioseir.supabase.co"
SUPABASE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqb2tkd2dwd3J1eWl1aW9zZWlyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzNzM0MjQsImV4cCI6MjA4NDk0OTQyNH0.DLz3djC6RGqs0gkhH4XalTUwizcBYFHWnvfG9X-dwxk"
STEF_USER_ID="00000000-0000-0000-0000-000000000001"

echo "📦 Generating STEF repo context..."

# Get current git info
GIT_BRANCH=$(cd "$REPO_ROOT" && git branch --show-current)
GIT_HASH=$(cd "$REPO_ROOT" && git rev-parse --short HEAD)
GIT_DATE=$(cd "$REPO_ROOT" && git log -1 --format=%ci)

# Get recent commits (last 10)
RECENT_COMMITS=$(cd "$REPO_ROOT" && git log --oneline -10 | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')

# Get file structure for app/Sources
FILE_STRUCTURE=$(cd "$APP_DIR" && find Sources -name "*.swift" -type f | sort | awk '{printf "%s\\n", $0}')

# Extract model summaries (struct/class names and key properties)
echo "📝 Extracting models..."
MODELS_SUMMARY=""
for file in "$APP_DIR/Sources/Async/Models/"*.swift; do
    if [[ -f "$file" ]]; then
        filename=$(basename "$file")
        # Get struct/class/enum definitions
        definitions=$(grep -E "^(struct|class|enum) \w+" "$file" 2>/dev/null | head -10 | sed 's/"/\\"/g' | awk '{printf "%s; ", $0}')
        if [[ -n "$definitions" ]]; then
            MODELS_SUMMARY+="$filename: $definitions\\n"
        fi
    fi
done

# Extract service summaries
echo "🔧 Extracting services..."
SERVICES_SUMMARY=""
for file in "$APP_DIR/Sources/Async/Services/"*.swift; do
    if [[ -f "$file" ]]; then
        filename=$(basename "$file")
        # Get class/struct and func definitions
        definitions=$(grep -E "^(class|struct|func) \w+" "$file" 2>/dev/null | head -5 | sed 's/"/\\"/g' | awk '{printf "%s; ", $0}')
        if [[ -n "$definitions" ]]; then
            SERVICES_SUMMARY+="$filename: $definitions\\n"
        fi
    fi
done

# Extract view list
echo "🖼️ Extracting views..."
VIEWS_LIST=$(cd "$APP_DIR" && find Sources/Async/Views -name "*.swift" -type f -exec basename {} \; | sort | awk '{printf "%s, ", $0}' | sed 's/, $//')

# Count tests
TEST_COUNT=$(cd "$APP_DIR" && find Tests -name "*.swift" -type f -exec grep -l "func test" {} \; 2>/dev/null | wc -l | tr -d ' ')

# Build the knowledge base content
KNOWLEDGE_BASE="REPO STATE (auto-generated $(date '+%Y-%m-%d %H:%M'))
Branch: $GIT_BRANCH @ $GIT_HASH
Last commit: $GIT_DATE

FILE STRUCTURE:
$FILE_STRUCTURE

MODELS (Sources/Async/Models/):
$MODELS_SUMMARY

SERVICES (Sources/Async/Services/):
$SERVICES_SUMMARY

VIEWS: $VIEWS_LIST

TESTS: $TEST_COUNT test files

RECENT COMMITS:
$RECENT_COMMITS

KEY PATHS:
- Models: app/Sources/Async/Models/
- Services: app/Sources/Async/Services/
- Views: app/Sources/Async/Views/
- Tests: app/Tests/AsyncTests/
- Config: app/Sources/Async/Config.swift
- Database schema: backend/database/schema.sql"

# Write to temp file and use jq for proper JSON encoding
TEMP_FILE=$(mktemp)
echo "$KNOWLEDGE_BASE" > "$TEMP_FILE"

# Use jq to properly escape the content into AgentKnowledgeBase format
# The knowledge_base field is JSONB with {context: string, documents: [], examples: []}
JSON_PAYLOAD=$(jq -n --rawfile content "$TEMP_FILE" '{knowledge_base: {context: $content, documents: [], examples: []}}')
rm "$TEMP_FILE"

echo "☁️ Uploading to Supabase..."

# Update Supabase
RESPONSE=$(curl -s -X PATCH "$SUPABASE_URL/rest/v1/agent_configs?user_id=eq.$STEF_USER_ID" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "$JSON_PAYLOAD")

# Check response
if echo "$RESPONSE" | grep -q "knowledge_base"; then
    echo "✅ STEF context updated successfully!"
    echo ""
    echo "Summary:"
    echo "  - Files: $(echo "$FILE_STRUCTURE" | grep -c "swift" || echo 0) Swift files"
    echo "  - Tests: $TEST_COUNT test files"
    echo "  - Branch: $GIT_BRANCH @ $GIT_HASH"
else
    echo "❌ Failed to update context:"
    echo "$RESPONSE"
    exit 1
fi
