#!/bin/bash
# Build and install Async.app to /Applications

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$APP_DIR/Async.app"
DEST="/Applications/Async.app"

echo "Building Async (release)..."
cd "$APP_DIR"
swift build -c release

echo "Copying binary to app bundle..."
cp "$APP_DIR/.build/release/Async" "$APP_BUNDLE/Contents/MacOS/Async"

echo "Closing running instance if any..."
pkill -f "Async.app" 2>/dev/null || true
sleep 1

echo "Installing to /Applications..."
rm -rf "$DEST"
cp -R "$APP_BUNDLE" "$DEST"

echo "Done! Async.app installed to /Applications"
echo ""
echo "To launch: open /Applications/Async.app"
