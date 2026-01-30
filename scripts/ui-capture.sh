#!/bin/bash
# UI Capture Tool for Async App
# Takes screenshots and can be read by Claude Code

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_DIR="$SCRIPT_DIR/../.ui-captures"
mkdir -p "$CAPTURE_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo "UI Capture & Automation Tool for Async App"
    echo ""
    echo "Usage: ui-capture.sh <command> [options]"
    echo ""
    echo "Screenshot Commands:"
    echo "  screenshot [name]     Take screenshot of Async app window"
    echo "  list                  List recent captures"
    echo "  latest                Show path to latest capture"
    echo "  clean                 Remove old captures"
    echo ""
    echo "Automation Commands:"
    echo "  login [bill|noah]     Log in as Bill or Noah"
    echo "  clickat <x%> <y%>     Click at percentage coordinates"
    echo "  click <element>       Click a UI element by name/description"
    echo "  type <text>           Type text into focused element"
    echo "  elements              List all UI elements (for debugging)"
    echo ""
    echo "Examples:"
    echo "  ui-capture.sh screenshot login     # Capture and name it 'login'"
    echo "  ui-capture.sh click 'Bill'         # Click the Bill button"
    echo "  ui-capture.sh type 'Hello world'   # Type text"
    echo ""
}

# Get window ID for a process
get_window_id() {
    local app_name="$1"
    # Use CGWindowListCopyWindowInfo to find window
    osascript -e "
        tell application \"System Events\"
            set appProcess to first process whose name is \"$app_name\"
            set frontWindow to first window of appProcess
            return id of frontWindow
        end tell
    " 2>/dev/null
}

# Take screenshot of specific app
cmd_screenshot() {
    local name="${1:-capture}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filename="${timestamp}_${name}.png"
    local filepath="$CAPTURE_DIR/$filename"

    # Try to find Async app first
    local app_name=""
    if pgrep -q "Async$"; then
        app_name="Async"
    elif pgrep -q "AsyncDashboard"; then
        app_name="AsyncDashboard"
    fi

    if [ -z "$app_name" ]; then
        echo -e "${RED}Error: No Async app running${NC}"
        echo "Start /Applications/Async.app or the dashboard first"
        exit 1
    fi

    echo -e "${CYAN}Capturing $app_name window...${NC}"

    # Get window ID using JavaScript for Automation (JXA)
    # This uses CoreGraphics to get the actual CGWindowID
    # Note: JXA returns value via the final expression, not console.log
    local window_id=$(osascript -l JavaScript << EOF
ObjC.import('Cocoa');
ObjC.import('CoreGraphics');

var windowList = $.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0);
var count = $.CFArrayGetCount(windowList);
var result = "";

for (var i = 0; i < count; i++) {
    var window = ObjC.castRefToObject($.CFArrayGetValueAtIndex(windowList, i));
    var ownerName = window.objectForKey('kCGWindowOwnerName');
    if (ownerName && ownerName.js && ownerName.js.includes('$app_name')) {
        result = window.objectForKey('kCGWindowNumber').js;
        break;
    }
}
result;
EOF
2>/dev/null)

    if [ -n "$window_id" ] && [ "$window_id" != "" ]; then
        echo -e "${CYAN}Found window ID: $window_id${NC}"
        # Capture specific window by CGWindowID
        screencapture -l "$window_id" -o "$filepath" 2>/dev/null

        if [ -f "$filepath" ]; then
            echo -e "${GREEN}✓ Captured: $filepath${NC}"
            echo "$filepath"
            return 0
        fi
    fi

    # Fallback: bring app to front and capture frontmost window
    echo -e "${CYAN}Fallback: activating app and capturing...${NC}"
    osascript -e "tell application \"$app_name\" to activate" 2>/dev/null
    sleep 0.5
    screencapture -o "$filepath" 2>/dev/null

    if [ -f "$filepath" ]; then
        echo -e "${GREEN}✓ Captured (full screen): $filepath${NC}"
        echo "$filepath"
    else
        echo -e "${RED}Failed to capture screenshot${NC}"
        exit 1
    fi
}

cmd_list() {
    echo -e "${CYAN}Recent captures:${NC}"
    ls -lt "$CAPTURE_DIR"/*.png 2>/dev/null | head -10 | while read line; do
        echo "  $line"
    done
}

cmd_latest() {
    local latest=$(ls -t "$CAPTURE_DIR"/*.png 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
        echo "$latest"
    else
        echo "No captures found"
        exit 1
    fi
}

cmd_clean() {
    local count=$(ls "$CAPTURE_DIR"/*.png 2>/dev/null | wc -l)
    rm -f "$CAPTURE_DIR"/*.png
    echo -e "${GREEN}Cleaned $count captures${NC}"
}

# Get window info as "x,y,width,height"
get_window_info() {
    osascript << 'EOF'
tell application "System Events"
    tell process "Async"
        set win to window 1
        set winPos to position of win
        set winSize to size of win
        set px to item 1 of winPos as integer
        set py to item 2 of winPos as integer
        set sx to item 1 of winSize as integer
        set sy to item 2 of winSize as integer
        return "" & px & "," & py & "," & sx & "," & sy
    end tell
end tell
EOF
}

# Click at coordinates relative to window (0-100% for x and y)
cmd_clickat() {
    local x_pct="$1"
    local y_pct="$2"

    if [ -z "$x_pct" ] || [ -z "$y_pct" ]; then
        echo -e "${RED}Usage: ui-capture.sh clickat <x%> <y%>${NC}"
        echo "  Examples:"
        echo "    ui-capture.sh clickat 50 48    # Click at center-x, 48% down"
        echo "    ui-capture.sh clickat 25 50    # Click at 25% from left, center-y"
        exit 1
    fi

    if ! pgrep -q "Async$"; then
        echo -e "${RED}Async app not running${NC}"
        exit 1
    fi

    osascript -e 'tell application "Async" to activate'
    sleep 0.2

    local wininfo=$(get_window_info)
    IFS=',' read -r wx wy ww wh <<< "$wininfo"

    local click_x=$((wx + ww * x_pct / 100))
    local click_y=$((wy + wh * y_pct / 100))

    echo -e "${CYAN}Clicking at ${x_pct}%, ${y_pct}% → ($click_x, $click_y)${NC}"
    cliclick c:$click_x,$click_y
    echo -e "${GREEN}✓ Clicked${NC}"
}

# Login as a specific user (bill or noah)
cmd_login() {
    local user="${1:-bill}"

    if ! pgrep -q "Async$"; then
        echo -e "${CYAN}Starting Async app...${NC}"
        open /Applications/Async.app
        sleep 2
    fi

    osascript -e 'tell application "Async" to activate'
    sleep 0.3

    local wininfo=$(get_window_info)
    IFS=',' read -r wx wy ww wh <<< "$wininfo"

    # Account buttons are at center-x
    # Bill is at ~48% from top, Noah is at ~60%
    local click_x=$((wx + ww / 2))
    local click_y

    if [ "$user" = "noah" ]; then
        click_y=$((wy + wh * 60 / 100))
        echo -e "${CYAN}Logging in as Noah...${NC}"
    else
        click_y=$((wy + wh * 48 / 100))
        echo -e "${CYAN}Logging in as Bill...${NC}"
    fi

    cliclick c:$click_x,$click_y
    sleep 0.5
    echo -e "${GREEN}✓ Logged in as $user${NC}"
}

# Click on a UI element by description (uses accessibility)
cmd_click() {
    local element_desc="$1"

    if [ -z "$element_desc" ]; then
        echo -e "${RED}Usage: ui-capture.sh click <element description>${NC}"
        echo "  Examples:"
        echo "    ui-capture.sh click 'Bill'           # Click button with text 'Bill'"
        echo "    ui-capture.sh click 'button:Send'    # Click button named 'Send'"
        echo "    ui-capture.sh click 'text:Hello'     # Click text field"
        exit 1
    fi

    local app_name="Async"
    if ! pgrep -q "Async$"; then
        echo -e "${RED}Async app not running${NC}"
        exit 1
    fi

    echo -e "${CYAN}Clicking '$element_desc'...${NC}"

    # Parse element type if specified (button:X, text:X, etc.)
    local elem_type=""
    local elem_name="$element_desc"
    if [[ "$element_desc" == *":"* ]]; then
        elem_type="${element_desc%%:*}"
        elem_name="${element_desc#*:}"
    fi

    # Use AppleScript to find and click the element
    local result=$(osascript << EOF
tell application "System Events"
    tell process "Async"
        set frontmost to true
        delay 0.2

        -- Try to find and click the element
        try
            if "$elem_type" is "button" then
                click button "$elem_name" of window 1
                return "clicked button"
            else if "$elem_type" is "text" then
                set focused of text field "$elem_name" of window 1 to true
                return "focused text field"
            else
                -- Try various element types
                try
                    click button "$elem_name" of window 1
                    return "clicked button"
                end try
                try
                    click static text "$elem_name" of window 1
                    return "clicked text"
                end try
                -- Search recursively for any clickable element containing the text
                set allElements to entire contents of window 1
                repeat with elem in allElements
                    try
                        if description of elem contains "$elem_name" or name of elem contains "$elem_name" or value of elem contains "$elem_name" then
                            click elem
                            return "clicked element"
                        end if
                    end try
                end repeat
                return "not found"
            end if
        on error errMsg
            return "error: " & errMsg
        end try
    end tell
end tell
EOF
2>&1)

    if [[ "$result" == *"clicked"* ]] || [[ "$result" == *"focused"* ]]; then
        echo -e "${GREEN}✓ $result${NC}"
    else
        echo -e "${RED}Failed: $result${NC}"
        exit 1
    fi
}

# Type text into the focused element
cmd_type() {
    local text="$1"

    if [ -z "$text" ]; then
        echo -e "${RED}Usage: ui-capture.sh type <text>${NC}"
        exit 1
    fi

    local app_name="Async"
    if ! pgrep -q "Async$"; then
        echo -e "${RED}Async app not running${NC}"
        exit 1
    fi

    echo -e "${CYAN}Typing '$text'...${NC}"

    osascript << EOF
tell application "System Events"
    tell process "Async"
        set frontmost to true
        delay 0.1
        keystroke "$text"
    end tell
end tell
EOF

    echo -e "${GREEN}✓ Typed text${NC}"
}

# List UI elements in the app (for debugging)
cmd_elements() {
    local app_name="Async"
    if ! pgrep -q "Async$"; then
        echo -e "${RED}Async app not running${NC}"
        exit 1
    fi

    echo -e "${CYAN}UI Elements in Async:${NC}"

    osascript << 'EOF'
tell application "System Events"
    tell process "Async"
        set output to ""
        set allElements to entire contents of window 1
        repeat with elem in allElements
            try
                set elemClass to class of elem as string
                set elemName to name of elem as string
                set elemDesc to description of elem as string
                set output to output & elemClass & ": " & elemName & " (" & elemDesc & ")" & return
            end try
        end repeat
        return output
    end tell
end tell
EOF
}

# Main
case "${1:-}" in
    screenshot|ss|s)
        cmd_screenshot "$2"
        ;;
    click|c)
        cmd_click "$2"
        ;;
    clickat|ca)
        cmd_clickat "$2" "$3"
        ;;
    login)
        cmd_login "$2"
        ;;
    type|t)
        cmd_type "$2"
        ;;
    elements|e)
        cmd_elements
        ;;
    list|ls|l)
        cmd_list
        ;;
    latest)
        cmd_latest
        ;;
    clean)
        cmd_clean
        ;;
    *)
        usage
        ;;
esac
