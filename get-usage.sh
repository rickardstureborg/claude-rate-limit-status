#!/bin/bash
# Fetches Claude Code usage limits by running /usage command via expect.
# Output: JSON with session_pct, session_reset, weekly_pct, sonnet_pct, fetch_time.
# On failure, preserves existing cache and exits non-zero.

SCRIPT_DIR="$(dirname "$0")"
EXPECT_SCRIPT="$SCRIPT_DIR/get-usage.exp"
LOG_FILE="/tmp/claude-usage-log.txt"
USAGE_CACHE="/tmp/claude-usage-cache.json"
TRACKING_FILE="$HOME/.claude/usage-tracking.jsonl"

# Run expect script
timeout 35 expect "$EXPECT_SCRIPT" >/dev/null 2>&1
EXPECT_EXIT=$?

if [ ! -f "$LOG_FILE" ]; then
    echo '{"error": "no log file"}' >&2
    exit 1
fi

# Comprehensive ANSI/terminal escape stripping:
# 1. Remove carriage returns
# 2. CSI sequences: \e[...X where X is a letter (covers colors, cursor moves, etc)
# 3. OSC sequences: \e]...BEL or \e]...ST
# 4. Simple escapes: \e followed by single char like >, =, <
# 5. Replace \e[1C (cursor right 1) with a space BEFORE stripping, since it represents whitespace
CLEAN=$(cat "$LOG_FILE" | \
    tr -d '\r' | \
    sed 's/\x1b\[1C/ /g' | \
    sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | \
    sed 's/\x1b\][0-9]*;[^\x07]*\x07//g' | \
    sed 's/\x1b\][0-9]*;[^\x1b]*\x1b\\//g' | \
    sed 's/\x1b[>=<()]//g' | \
    sed 's/\x1b(B//g' | \
    sed 's/\x1b//g' | \
    tr -s ' ')

# Debug: save cleaned output for troubleshooting
echo "$CLEAN" > /tmp/claude-usage-clean.txt

# --- Parse session usage ---
# Look for "Current session" line, then find N% used on the following lines
SESSION_BLOCK=$(echo "$CLEAN" | grep -A3 "Current session")
SESSION_PCT=$(echo "$SESSION_BLOCK" | grep -oE '[0-9]+%[[:space:]]*used' | head -1 | grep -oE '[0-9]+')

# Session reset time: "Resets 2pm" or "Resets 1:59pm" or "Rese s 2pm" (garbled)
SESSION_RESET=$(echo "$SESSION_BLOCK" | grep -oE 'Rese[t ]*s[[:space:]]*[0-9:]+[ap]m' | head -1 | sed 's/Rese[t ]*s[[:space:]]*//')
[ -z "$SESSION_RESET" ] && SESSION_RESET=$(echo "$SESSION_BLOCK" | grep -oE '[0-9]{1,2}(:[0-9]{2})?[ap]m[[:space:]]*([(]America' | head -1 | grep -oE '[0-9:]+[ap]m')

# --- Parse weekly (all models) usage ---
WEEKLY_BLOCK=$(echo "$CLEAN" | grep -A3 "all models")
WEEKLY_PCT=$(echo "$WEEKLY_BLOCK" | grep -oE '[0-9]+%[[:space:]]*used' | head -1 | grep -oE '[0-9]+')

# --- Parse weekly (Sonnet only) usage ---
SONNET_BLOCK=$(echo "$CLEAN" | grep -A3 "Sonnet only")
SONNET_PCT=$(echo "$SONNET_BLOCK" | grep -oE '[0-9]+%[[:space:]]*used' | head -1 | grep -oE '[0-9]+')

# Validate: at least session should have parsed. If not, this fetch failed.
if [ -z "$SESSION_PCT" ] && [ -z "$WEEKLY_PCT" ] && [ -z "$SONNET_PCT" ]; then
    echo '{"error": "parse failed", "expect_exit": '$EXPECT_EXIT'}' >&2
    exit 1
fi

# Defaults
SESSION_PCT=${SESSION_PCT:-0}
SESSION_RESET=${SESSION_RESET:-"unknown"}
WEEKLY_PCT=${WEEKLY_PCT:-0}
SONNET_PCT=${SONNET_PCT:-0}
FETCH_TIME=$(date +%s)

# Build output JSON
JSON="{\"session_pct\": $SESSION_PCT, \"session_reset\": \"$SESSION_RESET\", \"weekly_pct\": $WEEKLY_PCT, \"sonnet_pct\": $SONNET_PCT, \"fetch_time\": $FETCH_TIME}"

echo "$JSON"

# Append to JSONL tracking file
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TRACK="{\"timestamp\": \"$TIMESTAMP\", \"session_pct\": $SESSION_PCT, \"session_reset\": \"$SESSION_RESET\", \"weekly_pct\": $WEEKLY_PCT, \"sonnet_pct\": $SONNET_PCT}"
echo "$TRACK" >> "$TRACKING_FILE"
