#!/bin/bash
# Start the Async Dashboard

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="AsyncDashboard"

# Kill any existing instance
pkill -f "$APP_NAME" 2>/dev/null || true

# Check for gh CLI
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) not found. Install with: brew install gh"
    exit 1
fi

# Check gh authentication
if ! gh auth status &>/dev/null; then
    echo "Error: Not authenticated. Run: gh auth login"
    exit 1
fi

# Build
echo "Building $APP_NAME..."
cd "$DASHBOARD_DIR"
swift build -c release 2>&1

# Run
echo "Launching $APP_NAME..."
".build/release/$APP_NAME" &

echo "Dashboard started. Run 'pkill -f $APP_NAME' to stop."
