#!/bin/bash
# Removes claude-no-sleep: the launchd agent, the Claude Code hook, the sudoers rule and the installed files, and turns sleep back on.
set -uo pipefail

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
. "$REPO_DIR/lib/paths.sh"

"$LAUNCHCTL" bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$PLIST"
if [ -e "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.claude-no-sleep.bak"
  "${SETTINGS_HOOK[@]}" remove "$SETTINGS" >/dev/null || echo "claude-no-sleep: could not remove the hook from $SETTINGS" >&2
fi
# turn sleep on while the sudoers rule still allows it without a password
"$SUDO" /usr/bin/pmset -a disablesleep 0
"$SUDO" rm -f "$SUDOERS_FILE"
rm -rf "$STATE_DIR" "$INSTALL_DIR"
echo "claude-no-sleep is removed."
