# Claude Code Rate Limit Status

Display your Claude Code rate limits in the status line, with historical usage tracking and an HTML dashboard.

In contrast to some other workarounds, we use claude's built in `/usage` command, rather than a minimal 1 max_token API call. This saves you hundredths of cents every time it runs, but still took me an hour to implement!

![alt text](example-statusline.png)

## What it shows

**Status line:**
- **Session limit** (5-hour rolling window) with reset time
- **Weekly limit** (all models)
- **Cache age** — how fresh the usage data is
- **Staleness indicator** — dims values when data is >10 minutes old

Colors change based on usage: gray → yellow (50%) → red (75%)

**Dashboard (`/usage-tracking`):**
- Current usage bars for session/weekly/sonnet
- Active session info (model, cost, tokens, lines changed)
- Usage over time chart with session/weekly reset markers
- Fetch history table
- Time range selector (1d to all)

## Requirements

- macOS (uses `expect` which is pre-installed)
- Claude Code CLI

## Install

```bash
git clone https://github.com/rickardstureborg/claude-rate-limit-status ~/.claude/rate-limit-status
cd ~/.claude/rate-limit-status
bash install.sh
```

Or manually:

```bash
# Clone and make executable
git clone https://github.com/rickardstureborg/claude-rate-limit-status ~/.claude/rate-limit-status
chmod +x ~/.claude/rate-limit-status/*.sh ~/.claude/rate-limit-status/*.exp

# Install the slash command
mkdir -p ~/.claude/commands
cp ~/.claude/rate-limit-status/commands/usage-tracking.md ~/.claude/commands/

# Add to your ~/.claude/settings.json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/rate-limit-status/statusline.sh"
  }
}
```

## How it works

Usage data is fetched every 5 minutes (at :00, :05, :10, etc.) to avoid slowing down the status line. We spawn a claude session and run `/usage` via an expect script, wait for the output using pattern matching, then parse the results. Results are cached in `/tmp/claude-usage-cache.json` with a timestamp so the status line can show cache age.

Each successful fetch also appends a record to `~/.claude/usage-tracking.jsonl` for historical tracking.

For technical implementation details, see [IMPLEMENTATION.md](IMPLEMENTATION.md).

## Usage dashboard

Run `/usage-tracking` in Claude Code to generate and open an HTML dashboard showing usage over time. The dashboard is a self-contained HTML file at `~/.claude/usage-dashboard.html` — bookmark it for quick access.

## Example output

```
~/projects/myapp (main) user@host [Opus 4.6] [12%] [sesh: 3% (ends 5pm) week: 12% - 2m ago]
```
