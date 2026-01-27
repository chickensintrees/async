#!/bin/bash
# =============================================================================
# Async Project Test Runner
# Runs all tests and outputs a summary
# Usage: ./scripts/run-tests.sh [--verbose]
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
DIM='\033[2m'
RESET='\033[0m'

VERBOSE=""
if [ "$1" = "--verbose" ]; then
    VERBOSE="1"
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

run_swift_tests() {
    local dir=$1
    local name=$2

    if [ ! -d "$dir" ]; then
        printf "  ${YELLOW}⊘${RESET} ${name}: ${DIM}Directory not found${RESET}\n"
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        return 0
    fi

    # Check if there's a Package.swift with test target
    if ! grep -q "testTarget" "$dir/Package.swift" 2>/dev/null; then
        printf "  ${YELLOW}⊘${RESET} ${name}: ${DIM}No test target${RESET}\n"
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        return 0
    fi

    if [ -n "$VERBOSE" ]; then
        swift test --package-path "$dir" 2>&1 | tee /tmp/test_output_${name}.txt
    else
        swift test --package-path "$dir" > /tmp/test_output_${name}.txt 2>&1
    fi

    local exit_code=$?

    # Parse XCTest output for counts
    local passed
    local failed
    passed=$(grep -c "Test Case.*passed" /tmp/test_output_${name}.txt 2>/dev/null) || passed=0
    failed=$(grep -c "Test Case.*failed" /tmp/test_output_${name}.txt 2>/dev/null) || failed=0

    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))

    if [ "$failed" -gt 0 ] || [ $exit_code -ne 0 ]; then
        printf "  ${RED}✗${RESET} ${name}: ${passed}/$((passed + failed)) passed\n"
        if [ -n "$VERBOSE" ]; then
            grep -E "(FAIL|error:|failed)" /tmp/test_output_${name}.txt | head -5
        fi
        return 1
    else
        if [ "$passed" -gt 0 ]; then
            printf "  ${GREEN}✓${RESET} ${name}: ${passed}/${passed} passed\n"
        else
            printf "  ${YELLOW}⊘${RESET} ${name}: ${DIM}No tests${RESET}\n"
            TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        fi
        return 0
    fi
}

run_deno_tests() {
    local dir="$PROJECT_ROOT/backend"

    # Check if Deno is installed
    if ! command -v deno &> /dev/null; then
        printf "  ${YELLOW}⊘${RESET} Edge Functions: ${DIM}Deno not installed${RESET}\n"
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        return 0
    fi

    # Check if tests exist
    if [ ! -d "$dir/tests" ] || [ -z "$(ls -A "$dir/tests"/*.ts 2>/dev/null)" ]; then
        printf "  ${YELLOW}⊘${RESET} Edge Functions: ${DIM}No tests${RESET}\n"
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        return 0
    fi

    if [ -n "$VERBOSE" ]; then
        deno test --allow-env "$dir/tests/" 2>&1 | tee /tmp/deno_output.txt
    else
        deno test --allow-env "$dir/tests/" > /tmp/deno_output.txt 2>&1
    fi

    local exit_code=$?

    # Parse Deno output (format: "X passed | Y failed")
    local passed=$(grep -oE '[0-9]+ passed' /tmp/deno_output.txt | grep -oE '[0-9]+' | head -1 || echo "0")
    local failed=$(grep -oE '[0-9]+ failed' /tmp/deno_output.txt | grep -oE '[0-9]+' | head -1 || echo "0")

    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))

    if [ "$failed" -gt 0 ] || [ $exit_code -ne 0 ]; then
        printf "  ${RED}✗${RESET} Edge Functions: ${passed}/$((passed + failed)) passed\n"
        if [ -n "$VERBOSE" ]; then
            grep -E "(FAILED|error)" /tmp/deno_output.txt | head -5
        fi
        return 1
    else
        printf "  ${GREEN}✓${RESET} Edge Functions: ${passed}/${passed} passed\n"
        return 0
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ASYNC TEST SUITE"
echo "════════════════════════════════════════════════════════════════"
echo ""

FAILED=0

# Run Swift tests for app
run_swift_tests "app" "App" || FAILED=1

# Run Swift tests for dashboard
run_swift_tests "dashboard" "Dashboard" || FAILED=1

# Run Deno tests for Edge Functions
run_deno_tests || FAILED=1

echo ""
echo "════════════════════════════════════════════════════════════════"

# Calculate total
TOTAL=$((TOTAL_PASSED + TOTAL_FAILED))

if [ "$TOTAL_FAILED" -gt 0 ] || [ "$FAILED" -eq 1 ]; then
    printf "  ${RED}RESULT: ${TOTAL_PASSED}/${TOTAL} tests passed${RESET}"
    if [ "$TOTAL_SKIPPED" -gt 0 ]; then
        printf " ${DIM}(${TOTAL_SKIPPED} skipped)${RESET}"
    fi
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    exit 1
else
    if [ "$TOTAL" -eq 0 ]; then
        printf "  ${YELLOW}RESULT: No tests to run${RESET}"
        if [ "$TOTAL_SKIPPED" -gt 0 ]; then
            printf " ${DIM}(${TOTAL_SKIPPED} skipped)${RESET}"
        fi
    else
        printf "  ${GREEN}RESULT: ${TOTAL_PASSED}/${TOTAL} tests passed${RESET}"
        if [ "$TOTAL_SKIPPED" -gt 0 ]; then
            printf " ${DIM}(${TOTAL_SKIPPED} skipped)${RESET}"
        fi
    fi
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    exit 0
fi
