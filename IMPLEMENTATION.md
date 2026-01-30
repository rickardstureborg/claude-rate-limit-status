# Implementation Details

This document explains the technical challenges and solutions for displaying Claude Code rate limits in the status line. Written for LLMs helping users modify or debug this code.

## The Core Problem

Claude Code's `/usage` command is a **built-in CLI command**, not a skill or API endpoint. Built-in commands only work in interactive mode—they are explicitly disabled in headless mode (`claude -p`). From the official docs:

> User-invoked skills like `/commit` and built-in commands are only available in interactive mode. In `-p` mode, describe the task you want to accomplish instead.

This means we cannot simply run `claude -p "/usage"` to get rate limit data.

## Solution: Expect Script

We use `expect` to automate an interactive Claude session:

1. Spawn `claude`
2. Wait for the UI to be ready (status line shows `[0%]`)
3. Type `/usage`, Tab (autocomplete), Enter
4. Wait for the usage panel to render (~2-4 seconds)
5. Press Escape, then `/exit` + Tab + Enter

The expect script logs all terminal output to `/tmp/claude-usage-log.txt`, which we then parse.

## Key Timing Challenges

### The TUI is slow to initialize
Claude Code's terminal UI takes 2-3 seconds to fully initialize. We wait for the status line `[0%]` pattern before sending commands.

### The /usage panel takes time to load
After pressing Enter on `/usage`, the panel takes ~2 seconds to fetch and display data. We sleep for 4 seconds to ensure the data appears in the log.

### Total fetch time: ~25-30 seconds
This is far too slow for a status line that updates every 300ms. We solve this with caching.

## Caching Strategy

The status line script checks if the current minute is divisible by 5 (`:00`, `:05`, `:10`, etc.). If so, and we haven't already fetched this minute, it launches the fetch in the background:

```bash
if [ $((MIN % 5)) -eq 0 ]; then
    LOCK_MIN=$(cat "$USAGE_LOCK" 2>/dev/null)
    if [ "$LOCK_MIN" != "$MIN" ]; then
        echo "$MIN" > "$USAGE_LOCK"
        ("$SCRIPT_DIR/get-usage.sh" > "$USAGE_CACHE" 2>/dev/null &)
    fi
fi
```

The lock file prevents multiple fetches in the same minute. The background `&` ensures the status line returns immediately.

## Parsing the TUI Output

The expect log contains raw terminal output with ANSI escape codes, cursor movements, and Unicode box-drawing characters. We strip these before parsing:

```bash
CLEAN=$(cat "$LOG_FILE" | tr -d '\r' | \
    sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | \
    sed 's/\x1b\][0-9];[^\x07]*\x07//g' | \
    sed 's/\x1b[>=<]//g')
```

### Data format in the /usage panel

```
Current session
█                                                  2% used
Resets 5pm (America/New_York)

Current week (all models)
█▌                                                 3% used
Resets Feb 3 at 10am (America/New_York)

Current week (Sonnet only)
                                                   0% used
Resets Feb 6 at 9am (America/New_York)
```

After stripping escape codes, the text may be slightly mangled (e.g., "Resets" becomes "Reses" due to lost characters). The parsing regexes handle these variations:

```bash
SESSION_RESET=$(echo "$CLEAN" | grep "Current session" | grep -oE 'Rese[ts]*[[:space:]]*[0-9:]+[ap]m' | head -1 | sed 's/Rese[ts]*//' | tr -d ' ')
```

## Files

| File | Purpose |
|------|---------|
| `statusline.sh` | Main status line script. Reads JSON from stdin, triggers background fetch, outputs formatted line |
| `get-usage.sh` | Wrapper that runs expect and parses the log file into JSON |
| `get-usage.exp` | Expect script that automates the interactive session |

## Cache Files

| Path | Purpose |
|------|---------|
| `/tmp/claude-usage-cache.json` | Cached usage data (JSON) |
| `/tmp/claude-usage-fetch.lock` | Lock file containing last fetch minute |
| `/tmp/claude-usage-log.txt` | Raw terminal output from expect |

## Alternative Approaches (Not Used)

### OAuth API Endpoint
There is an undocumented API at `https://api.anthropic.com/api/oauth/usage` that returns usage data. This requires extracting the OAuth token from macOS Keychain. We chose not to use this because:
- It's undocumented and may change
- Some users reported it costs API credits (unverified)
- The expect approach works without any API calls

### Parsing the status line itself
If you already have usage data in your status line, it creates a circular dependency. The expect approach fetches fresh data from a new Claude session.

## Debugging Tips

1. **Check the log file**: `cat /tmp/claude-usage-log.txt | strings | grep -i session`
2. **Run fetch manually**: `/path/to/get-usage.sh` (takes ~25s)
3. **Clear the lock**: `rm /tmp/claude-usage-fetch.lock` to force a new fetch
4. **Test the statusline**: `echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":50}}' | ./statusline.sh`
