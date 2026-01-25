#!/bin/bash
# One-time setup for Async Dashboard

set -e

echo "=== Async Dashboard Setup ==="

# Check prerequisites
echo "Checking prerequisites..."

# Check Swift
if ! command -v swift &> /dev/null; then
    echo "Error: Swift not found. Install Xcode Command Line Tools."
    exit 1
fi
echo "  Swift: $(swift --version 2>&1 | head -1)"

# Check gh CLI
if ! command -v gh &> /dev/null; then
    echo "  GitHub CLI: Not found"
    echo "  Installing via Homebrew..."
    brew install gh
else
    echo "  GitHub CLI: $(gh --version | head -1)"
fi

# Check gh auth
if ! gh auth status &>/dev/null; then
    echo ""
    echo "GitHub CLI needs authentication. Running 'gh auth login'..."
    gh auth login
fi

# Build
echo ""
echo "Building dashboard..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"
swift build -c release

echo ""
echo "=== Setup Complete ==="
echo "Run './scripts/start-dashboard.sh' to launch the dashboard."
