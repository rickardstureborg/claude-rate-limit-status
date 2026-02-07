#!/bin/bash
# Install claude-rate-limit-status

set -e

INSTALL_DIR="$HOME/.claude/rate-limit-status"
COMMANDS_DIR="$HOME/.claude/commands"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "Installing to $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR"
cp statusline.sh get-usage.sh get-usage.exp generate-dashboard.sh "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR"/*.sh "$INSTALL_DIR"/*.exp

# Install slash command
mkdir -p "$COMMANDS_DIR"
cp commands/usage-tracking.md "$COMMANDS_DIR/"
echo "Installed /usage-tracking slash command"

echo "Configuring Claude Code settings..."

if [ -f "$SETTINGS_FILE" ]; then
    # Check if statusLine already configured
    if grep -q '"statusLine"' "$SETTINGS_FILE"; then
        echo "Warning: statusLine already configured in $SETTINGS_FILE"
        echo "Please manually update the command to: $INSTALL_DIR/statusline.sh"
    else
        # Add statusLine to existing settings (simple approach - may need manual fix for complex JSON)
        echo "Note: Please add this to your $SETTINGS_FILE:"
        echo '  "statusLine": {'
        echo '    "type": "command",'
        echo "    \"command\": \"$INSTALL_DIR/statusline.sh\""
        echo '  }'
    fi
else
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    cat > "$SETTINGS_FILE" << EOF
{
  "statusLine": {
    "type": "command",
    "command": "$INSTALL_DIR/statusline.sh"
  }
}
EOF
    echo "Created $SETTINGS_FILE"
fi

echo "Done! Restart Claude Code to see the new status line."
echo "Use /usage-tracking in Claude Code to generate and open the usage dashboard."
