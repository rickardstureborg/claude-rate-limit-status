# Implementation Details

This document explains the technical challenges and solutions for displaying Claude Code rate limits in the status line. Written for LLMs helping users modify or debug this code.

## The Core Problem

Claude Code's `/usage` command is a **built-in CLI command**, not a skill or API endpoint. Built-in commands only work in interactive mode—they are explicitly disabled in headless mode (`claude -p`). From the official docs:

> User-invoked skills like `/commit` and built-in commands are only available in interactive mode. In `-p` mode, describe the task you want to accomplish instead.

This means we cannot simply run `claude -p "/usage"` to get rate limit data.

## Solution: Expect Script

We use `expect` to automate an interactive Claude session:

1. Spawn `claude`
2. Wait for the UI to be ready (status line shows `[N%]`)
3. Type `/usage`, Tab (autocomplete), Enter
4. Wait for "Sonnet" to appear (last section of /usage output)
5. Press Escape, then `/exit` + Tab + Enter

The expect script uses pattern matching instead of fixed sleeps — it waits for the actual output to appear rather than guessing how long things take.

All terminal output is logged to `/tmp/claude-usage-log.txt` for parsing.

## ANSI Escape Code Stripping

The expect log contains raw terminal output with ANSI escape codes, cursor movements, and Unicode box-drawing characters. The critical insight:

**Claude Code uses `\x1b[1C` (cursor right 1) to represent spaces.** This must be replaced with a literal space *before* stripping other ANSI codes, otherwise words merge (e.g., "Resets 5pm" becomes "Reses5pm").

```bash
CLEAN=$(cat "$LOG_FILE" | \
    tr -d '\r' | \
    sed 's/\x1b\[1C/ /g' | \              # cursor-right-1 → space (MUST be first)
    sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | \ # CSI sequences (colors, cursor moves)
    sed 's/\x1b\][0-9]*;[^\x07]*\x07//g' | \ # OSC sequences (title bar, etc)
    sed 's/\x1b\][0-9]*;[^\x1b]*\x1b\\//g' | \ # OSC with ST terminator
    sed 's/\x1b[>=<()]//g' | \             # simple escape sequences
    sed 's/\x1b(B//g' | \                  # character set selection
    sed 's/\x1b//g' | \                    # catch any remaining escapes
    tr -s ' ')                              # collapse multiple spaces
```

### Data format in the /usage panel

After stripping, the output looks like:

```
Current session █████▌ 11% used
Rese s 1:59pm (America/New_York)

Current week (all models)
████████████▌ 25% used
Resets Feb 10 at 10:59am (America/New_York)

Current week (Sonnet only)
 0% used
```

Note: "Resets" may appear as "Rese s" (with a space from the cursor-right conversion). The parsing regexes handle these variations via `Rese[t ]*s`.

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

The cache now includes `fetch_time` (unix epoch) so the status line can display cache age and dim stale data.

## Staleness Handling

When the cache is older than 10 minutes, all usage values are wrapped in dim ANSI codes to visually signal that the data may be outdated. The cache age is always shown (e.g., "3m ago", "1h ago").

If a fetch fails (parse failure or expect timeout), the existing cache is preserved — the status line continues showing the last known good values rather than blanking out.

## JSONL Tracking

Every successful fetch appends a record to `~/.claude/usage-tracking.jsonl`:

```json
{"timestamp": "2026-02-07T18:00:39Z", "session_pct": 11, "session_reset": "1:59pm", "weekly_pct": 25, "sonnet_pct": 0}
```

This enables the HTML dashboard to show usage over time.

## HTML Dashboard

`generate-dashboard.sh` reads the JSONL data, the current cache, and the last stdin JSON from Claude Code, then generates a self-contained HTML file.

The HTML is generated in parts (heredoc PART1, data injection, heredoc PART2) to avoid fragile sed/perl escaping of JSON data.

The dashboard includes a canvas-based chart that detects usage resets by looking for drops in percentage values (>2 point decrease between consecutive data points).

## Stdin JSON from Claude Code

The statusline script receives rich JSON on stdin, including:

```json
{
  "session_id": "...",
  "model": {"id": "claude-opus-4-6", "display_name": "Opus 4.6"},
  "cost": {"total_cost_usd": 2.53, "total_duration_ms": 6212629, "total_lines_added": 240, "total_lines_removed": 49},
  "context_window": {"total_input_tokens": 147671, "total_output_tokens": 44244, "used_percentage": 23,
    "current_usage": {"cache_read_input_tokens": 45884, "cache_creation_input_tokens": 233}}
}
```

This is logged to `/tmp/claude-statusline-stdin.json` and used by the dashboard for session info display.

## Files

| File | Purpose |
|------|---------|
| `statusline.sh` | Main status line script. Reads JSON from stdin, triggers background fetch, outputs formatted line |
| `get-usage.sh` | Wrapper that runs expect and parses the log file into JSON. Appends to JSONL tracking. |
| `get-usage.exp` | Expect script that automates the interactive session |
| `generate-dashboard.sh` | Generates the HTML dashboard from JSONL, cache, and stdin data |
| `commands/usage-tracking.md` | Slash command definition for `/usage-tracking` |

## Cache Files

| Path | Purpose |
|------|---------|
| `/tmp/claude-usage-cache.json` | Cached usage data (JSON with fetch_time) |
| `/tmp/claude-usage-fetch.lock` | Lock file containing last fetch minute |
| `/tmp/claude-usage-log.txt` | Raw terminal output from expect |
| `/tmp/claude-usage-clean.txt` | ANSI-stripped output for debugging |
| `/tmp/claude-statusline-stdin.json` | Last stdin JSON from Claude Code |
| `~/.claude/usage-tracking.jsonl` | Append-only historical usage data |
| `~/.claude/usage-dashboard.html` | Generated HTML dashboard |

## Alternative Approaches (Not Used)

### OAuth API Endpoint
There is an undocumented API at `https://api.anthropic.com/api/oauth/usage` that returns usage data. This requires extracting the OAuth token from macOS Keychain. We chose not to use this because:
- It's undocumented and may change
- Some users reported it costs API credits (unverified)
- The expect approach works without any API calls

### Parsing the status line itself
If you already have usage data in your status line, it creates a circular dependency. The expect approach fetches fresh data from a new Claude session.

## Debugging Tips

1. **Check the cleaned output**: `cat /tmp/claude-usage-clean.txt`
2. **Check the raw log**: `cat /tmp/claude-usage-log.txt | strings | grep -i session`
3. **Run fetch manually**: `~/.claude/rate-limit-status/get-usage.sh` (takes ~20-30s)
4. **Clear the lock**: `rm /tmp/claude-usage-fetch.lock` to force a new fetch
5. **Test the statusline**: `echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":50}}' | ./statusline.sh`
6. **Check JSONL data**: `cat ~/.claude/usage-tracking.jsonl`
7. **Regenerate dashboard**: `bash ~/.claude/rate-limit-status/generate-dashboard.sh`
