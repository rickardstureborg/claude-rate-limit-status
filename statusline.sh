#!/bin/bash
# Claude Code status line — af-magic zsh theme style
# Receives JSON on stdin from Claude Code with model info, context %, tokens, etc.

INPUT=$(cat)

# Log the raw stdin JSON once for field discovery, then periodically
STDIN_LOG="/tmp/claude-statusline-stdin.json"
echo "$INPUT" > "$STDIN_LOG"

# --- Parse stdin fields ---
json_string() { echo "$INPUT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/'; }
json_number() { echo "$INPUT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9.]*" | head -1 | sed 's/.*:[[:space:]]*//' | cut -d'.' -f1; }

MODEL_NAME=$(json_string "display_name")
CONTEXT_PCT=$(json_number "used_percentage")
INPUT_TOKENS=$(json_number "input_tokens")
OUTPUT_TOKENS=$(json_number "output_tokens")
CACHE_READ=$(json_number "cache_read_input_tokens")
CACHE_CREATE=$(json_number "cache_creation_input_tokens")

[ -z "$MODEL_NAME" ] && MODEL_NAME="Unknown"
[ -z "$CONTEXT_PCT" ] && CONTEXT_PCT=0

# --- Colors ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
MAGENTA='\033[0;35m'
RESET='\033[0m'

# --- Usage limits (cached, fetched every 5 min) ---
USAGE_CACHE="/tmp/claude-usage-cache.json"
USAGE_LOCK="/tmp/claude-usage-fetch.lock"
SCRIPT_DIR="$(dirname "$0")"

# Trigger fetch on 5-minute boundaries
MIN=$(date +%M | sed 's/^0//')
[ -z "$MIN" ] && MIN=0

if [ $((MIN % 5)) -eq 0 ]; then
    LOCK_MIN=$(cat "$USAGE_LOCK" 2>/dev/null)
    if [ "$LOCK_MIN" != "$MIN" ]; then
        echo "$MIN" > "$USAGE_LOCK"
        ("$SCRIPT_DIR/get-usage.sh" > "$USAGE_CACHE" 2>/dev/null &)
    fi
fi

# Read cached usage data
SESSION_PCT=""
WEEKLY_PCT=""
SESSION_RESET=""
FETCH_TIME=""
CACHE_STALE=0

if [ -f "$USAGE_CACHE" ]; then
    CACHE=$(cat "$USAGE_CACHE")
    # Only parse if it looks like valid data (not an error)
    if echo "$CACHE" | grep -q '"session_pct"'; then
        SESSION_PCT=$(echo "$CACHE" | grep -o '"session_pct"[[:space:]]*:[[:space:]]*[0-9]*' | grep -oE '[0-9]+$')
        WEEKLY_PCT=$(echo "$CACHE" | grep -o '"weekly_pct"[[:space:]]*:[[:space:]]*[0-9]*' | grep -oE '[0-9]+$')
        SESSION_RESET=$(echo "$CACHE" | grep -o '"session_reset"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/')
        FETCH_TIME=$(echo "$CACHE" | grep -o '"fetch_time"[[:space:]]*:[[:space:]]*[0-9]*' | grep -oE '[0-9]+$')
    fi
fi

# Compute cache age string
CACHE_AGE=""
if [ -n "$FETCH_TIME" ] && [ "$FETCH_TIME" -gt 0 ] 2>/dev/null; then
    NOW=$(date +%s)
    AGE_SEC=$((NOW - FETCH_TIME))
    if [ "$AGE_SEC" -lt 60 ]; then
        CACHE_AGE="<1m"
    elif [ "$AGE_SEC" -lt 3600 ]; then
        CACHE_AGE="$((AGE_SEC / 60))m"
    else
        CACHE_AGE="$((AGE_SEC / 3600))h"
    fi
    # Mark stale if older than 10 minutes
    [ "$AGE_SEC" -gt 600 ] && CACHE_STALE=1
fi

# --- Build segments ---

# Directory with ~ substitution
DIR="${PWD/#$HOME/~}"
DIR_OUT="${CYAN}${DIR}${RESET}"

# Git branch + dirty indicator
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

# User@host
USER_HOST="${DIM}${USER}@$(hostname -s)${RESET}"

# Model
MODEL_OUT="[${MODEL_NAME}]"

# Context % with color thresholds
if [ "$CONTEXT_PCT" -lt 50 ]; then
    CTX_COLOR=$GREEN
elif [ "$CONTEXT_PCT" -lt 75 ]; then
    CTX_COLOR=$YELLOW
else
    CTX_COLOR=$RED
fi
CTX_OUT="${CTX_COLOR}[${CONTEXT_PCT}%]${RESET}"

# Usage color: dim < 50, yellow 50-74, red >= 75
usage_color() {
    local pct=${1:-0}
    if [ "$pct" -lt 50 ]; then echo "$DIM"
    elif [ "$pct" -lt 75 ]; then echo "$YELLOW"
    else echo "$RED"
    fi
}

# Usage limits segment with cache age and staleness
USAGE_OUT=""
if [ -n "$SESSION_PCT" ]; then
    S_COLOR=$(usage_color "$SESSION_PCT")
    W_COLOR=$(usage_color "$WEEKLY_PCT")

    # Round :59 times up (e.g. 3:59pm -> 4pm)
    RESET_DISPLAY="$SESSION_RESET"
    if echo "$SESSION_RESET" | grep -q ':59'; then
        R_HOUR=$(echo "$SESSION_RESET" | grep -oE '^[0-9]+')
        R_SUFFIX=$(echo "$SESSION_RESET" | grep -oE '[ap]m$')
        R_HOUR=$((R_HOUR + 1))
        if [ "$R_HOUR" -eq 13 ]; then
            R_HOUR=1
        elif [ "$R_HOUR" -eq 12 ]; then
            [ "$R_SUFFIX" = "am" ] && R_SUFFIX="pm" || R_SUFFIX="am"
        fi
        RESET_DISPLAY="${R_HOUR}${R_SUFFIX}"
    fi

    # If data is stale, wrap in dim to signal it's old
    STALE_PRE=""
    STALE_POST=""
    if [ "$CACHE_STALE" -eq 1 ]; then
        STALE_PRE="${DIM}"
        STALE_POST="${RESET}"
    fi

    USAGE_OUT=" ${STALE_PRE}[${S_COLOR}sesh: ${SESSION_PCT}%${RESET}"
    [ -n "$RESET_DISPLAY" ] && [ "$RESET_DISPLAY" != "unknown" ] && USAGE_OUT+=" ${DIM}(ends ${RESET_DISPLAY})${RESET}"
    USAGE_OUT+=" ${STALE_PRE}${W_COLOR}week: ${WEEKLY_PCT}%${RESET}"

    # Cache age indicator
    if [ -n "$CACHE_AGE" ]; then
        USAGE_OUT+=" ${DIM}- ${CACHE_AGE} ago${RESET}"
    fi
    USAGE_OUT+="]${STALE_POST}"
fi

echo -e "${DIR_OUT}${GIT_BRANCH} ${USER_HOST} ${MODEL_OUT} ${CTX_OUT}${USAGE_OUT}"
