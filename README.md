# Claude Code Rate Limit Status

Display your Claude Code rate limits in the status line.

![Example](https://img.shields.io/badge/session-3%25-gray) ![Example](https://img.shields.io/badge/week-12%25-yellow) ![Example](https://img.shields.io/badge/sonnet-0%25-gray)

## What it shows

- **Session limit** (5-hour rolling window) with reset time
- **Weekly limit** (all models)
- **Sonnet-only weekly limit**

Colors change based on usage: gray → yellow (50%) → red (75%)

## Requirements

- macOS (uses `expect` which is pre-installed)
- Claude Code CLI

## Install

```bash
# Clone to your .claude directory
git clone https://github.com/acrebase/claude-rate-limit-status ~/.claude/rate-limit-status

# Make scripts executable
chmod +x ~/.claude/rate-limit-status/*.sh ~/.claude/rate-limit-status/*.exp

# Configure Claude Code to use the statusline
cat >> ~/.claude/settings.json << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/rate-limit-status/statusline.sh"
  }
}
EOF
```

## How it works

Usage data is fetched every 5 minutes (at :00, :05, :10, etc.) to avoid slowing down the status line. The fetch runs in the background and caches results to `/tmp/claude-usage-cache.json`.

For technical implementation details, see [IMPLEMENTATION.md](IMPLEMENTATION.md).

## Example output

```
~/projects/myapp (main) user@host [Opus 4.5] [12%] session: 3% (resets 5pm) week: 12% sonnet: 0%
```
