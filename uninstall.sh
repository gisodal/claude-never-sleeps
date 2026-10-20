#!/bin/bash
# Removes claude-no-sleep: the launchd agent, the Claude Code hook, the sudoers rule and the installed files, and turns sleep back on.
set -uo pipefail

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
. "$REPO_DIR/lib/paths.sh"

failed=0
"$LAUNCHCTL" bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$PLIST"
if [ -e "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.claude-no-sleep.bak"
  "${SETTINGS_HOOK[@]}" remove "$SETTINGS" >/dev/null || { echo "claude-no-sleep: could not remove the hook from $SETTINGS" >&2; failed=1; }
fi
if [ -e "$SUDOERS_FILE" ]; then
  # turn sleep on while the sudoers rule still allows it without a password
  "$SUDO" /usr/bin/pmset -a disablesleep 0 || failed=1
  "$SUDO" rm -f "$SUDOERS_FILE" || failed=1
fi
if [ "$failed" = 1 ]; then
  echo "claude-no-sleep: not fully removed; fix the error above and run $INSTALL_DIR/uninstall.sh again" >&2
  exit 1
fi
rm -rf "$STATE_DIR" "$INSTALL_DIR"
echo "claude-no-sleep is removed."
