#!/bin/bash
# Stops Shortcut Coach and removes the app and its login agent. Touches nothing else.
set -euo pipefail
label=local.shortcut-coach
launchctl bootout "gui/$UID/$label" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$label.plist"
rm -rf "$HOME/Applications/Shortcut Coach.app"
echo "Uninstalled."
