#!/bin/bash
# Removes claude-never-sleeps: the launchd agent, the Claude Code hook, the sudoers rule and the installed files, and turns sleep back on.
set -uo pipefail

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
. "$REPO_DIR/lib/paths.sh"

failed=0
"$LAUNCHCTL" bootout "gui/$(id -u)/$LABEL" 2>/dev/null
# the agent records the Claude dir the install used
if [ -e "$PLIST" ] && recorded_dir=$(/usr/bin/plutil -extract EnvironmentVariables.CLAUDE_CONFIG_DIR raw -o - "$PLIST" 2>/dev/null); then
  use_claude_dir "$recorded_dir"
fi
rm -f "$PLIST"
if [ -e "$SETTINGS" ]; then
  [ -e "$SETTINGS.claude-never-sleeps.bak" ] || cp "$SETTINGS" "$SETTINGS.claude-never-sleeps.bak"
  "${SETTINGS_HOOK[@]}" remove "$SETTINGS" >/dev/null || { echo "claude-never-sleeps: could not remove the hook from $SETTINGS" >&2; failed=1; }
fi
if [ -e "$SUDOERS_FILE" ]; then
  # turn sleep on while the sudoers rule still allows it without a password
  # keep the rule when that fails, so a rerun can still turn sleep on without a password
  if "$SUDO" /usr/bin/pmset -a disablesleep 0; then
    "$SUDO" rm -f "$SUDOERS_FILE" || failed=1
  else
    failed=1
  fi
fi
if [ "$failed" = 1 ]; then
  echo "claude-never-sleeps: not fully removed; fix the error above and run $INSTALL_DIR/uninstall.sh again" >&2
  exit 1
fi
rm -rf "$STATE_DIR" "$INSTALL_DIR"
echo "claude-never-sleeps is removed."
