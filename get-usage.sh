#!/bin/bash
# Fetches Claude Code usage limits by running /usage command
# Output: JSON with session_pct, session_reset, weekly_pct, sonnet_pct

SCRIPT_DIR="$(dirname "$0")"
EXPECT_SCRIPT="$SCRIPT_DIR/get-usage.exp"
LOG_FILE="/tmp/claude-usage-log.txt"

timeout 30 expect "$EXPECT_SCRIPT" >/dev/null 2>&1

if [ ! -f "$LOG_FILE" ]; then
    echo '{"error": "No log file"}'
    exit 1
fi

# Strip ANSI codes and other escape sequences
CLEAN=$(cat "$LOG_FILE" | tr -d '\r' | \
    sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | \
    sed 's/\x1b\][0-9];[^\x07]*\x07//g' | \
    sed 's/\x1b[>=<]//g')

SESSION_PCT=$(echo "$CLEAN" | grep "Current session" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
SESSION_PCT=${SESSION_PCT:-0}

SESSION_RESET=$(echo "$CLEAN" | grep "Current session" | grep -oE 'Rese[ts]*[[:space:]]*[0-9:]+[ap]m' | head -1 | sed 's/Rese[ts]*//' | tr -d ' ')
SESSION_RESET=${SESSION_RESET:-"unknown"}

WEEKLY_PCT=$(echo "$CLEAN" | grep -A2 "Current week (all models)" | grep -oE '[0-9]+% used' | head -1 | grep -oE '[0-9]+')
WEEKLY_PCT=${WEEKLY_PCT:-0}

SONNET_PCT=$(echo "$CLEAN" | grep -A2 "Current week (Sonnet only)" | grep -oE '[0-9]+% used' | head -1 | grep -oE '[0-9]+')
SONNET_PCT=${SONNET_PCT:-0}

echo "{\"session_pct\": $SESSION_PCT, \"session_reset\": \"$SESSION_RESET\", \"weekly_pct\": $WEEKLY_PCT, \"sonnet_pct\": $SONNET_PCT}"
