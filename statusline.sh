#!/bin/bash
# Claude Code status line with rate limit display

INPUT=$(cat)

MODEL_NAME=$(echo "$INPUT" | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:.*"\([^"]*\)"/\1/')
[ -z "$MODEL_NAME" ] && MODEL_NAME="Unknown"

CONTEXT_PCT=$(echo "$INPUT" | grep -o '"used_percentage"[[:space:]]*:[[:space:]]*[0-9.]*' | head -1 | sed 's/.*:[[:space:]]*//' | cut -d'.' -f1)
[ -z "$CONTEXT_PCT" ] && CONTEXT_PCT=0

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
RESET='\033[0m'

# Usage limits: fetched via expect script that spawns claude and runs /usage
# Takes ~25s so we cache and only refresh every 5 min (on :00, :05, :10, etc.)
USAGE_CACHE="/tmp/claude-usage-cache.json"
USAGE_LOCK="/tmp/claude-usage-fetch.lock"
SCRIPT_DIR="$(dirname "$0")"

MIN=$(date +%M | sed 's/^0//')
[ -z "$MIN" ] && MIN=0

if [ $((MIN % 5)) -eq 0 ]; then
    LOCK_MIN=$(cat "$USAGE_LOCK" 2>/dev/null)
    if [ "$LOCK_MIN" != "$MIN" ]; then
        echo "$MIN" > "$USAGE_LOCK"
        ("$SCRIPT_DIR/get-usage.sh" > "$USAGE_CACHE" 2>/dev/null &)
    fi
fi

if [ -f "$USAGE_CACHE" ]; then
    CACHE=$(cat "$USAGE_CACHE")
    SESSION_PCT=$(echo "$CACHE" | grep -o '"session_pct"[[:space:]]*:[[:space:]]*[0-9]*' | grep -oE '[0-9]+$')
    WEEKLY_PCT=$(echo "$CACHE" | grep -o '"weekly_pct"[[:space:]]*:[[:space:]]*[0-9]*' | grep -oE '[0-9]+$')
    SONNET_PCT=$(echo "$CACHE" | grep -o '"sonnet_pct"[[:space:]]*:[[:space:]]*[0-9]*' | grep -oE '[0-9]+$')
    SESSION_RESET=$(echo "$CACHE" | grep -o '"session_reset"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/')
fi

DIR="${PWD/#$HOME/~}"
DIR_OUT="${CYAN}${DIR}${RESET}"

GIT_BRANCH=""
if git rev-parse --git-dir &>/dev/null; then
    BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            GIT_BRANCH=" ${YELLOW}(${BRANCH})${RESET}"
        else
            GIT_BRANCH=" ${GREEN}(${BRANCH})${RESET}"
        fi
    fi
fi

USER_HOST="${DIM}${USER}@$(hostname -s)${RESET}"

MODEL_OUT="[${MODEL_NAME}]"

if [ "$CONTEXT_PCT" -lt 50 ]; then
    CTX_COLOR=$GREEN
elif [ "$CONTEXT_PCT" -lt 75 ]; then
    CTX_COLOR=$YELLOW
else
    CTX_COLOR=$RED
fi
CTX_OUT="${CTX_COLOR}[${CONTEXT_PCT}%]${RESET}"

# Usage color: gray < 50%, yellow 50-74%, red >= 75%
usage_color() {
    local pct=$1
    [ -z "$pct" ] && pct=0
    if [ "$pct" -lt 50 ]; then echo "$DIM"
    elif [ "$pct" -lt 75 ]; then echo "$YELLOW"
    else echo "$RED"
    fi
}

USAGE_OUT=""
if [ -n "$SESSION_PCT" ]; then
    S_COLOR=$(usage_color "$SESSION_PCT")
    W_COLOR=$(usage_color "$WEEKLY_PCT")
    SON_COLOR=$(usage_color "$SONNET_PCT")

    USAGE_OUT=" ${S_COLOR}session: ${SESSION_PCT}%${RESET}"
    [ -n "$SESSION_RESET" ] && [ "$SESSION_RESET" != "unknown" ] && USAGE_OUT+=" ${DIM}(resets ${SESSION_RESET})${RESET}"
    USAGE_OUT+=" ${W_COLOR}week: ${WEEKLY_PCT}%${RESET} ${SON_COLOR}sonnet: ${SONNET_PCT}%${RESET}"
fi

echo -e "${DIR_OUT}${GIT_BRANCH} ${USER_HOST} ${MODEL_OUT} ${CTX_OUT}${USAGE_OUT}"
