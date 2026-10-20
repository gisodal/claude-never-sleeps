# Paths and commands shared by install.sh and uninstall.sh; tests override the system commands and the sudoers file.
LABEL=dev.claude-no-sleep
use_claude_dir() {
  CLAUDE_DIR=$1
  SETTINGS=$CLAUDE_DIR/settings.json
}
use_claude_dir "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
INSTALL_DIR=$HOME/.local/share/claude-no-sleep
STATE_DIR=$HOME/.local/state/claude-no-sleep
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
SUDOERS_FILE=${CLAUDE_NO_SLEEP_SUDOERS_FILE:-/etc/sudoers.d/claude-no-sleep}
SUDO=${CLAUDE_NO_SLEEP_SUDO:-/usr/bin/sudo}
VISUDO=${CLAUDE_NO_SLEEP_VISUDO:-/usr/sbin/visudo}
LAUNCHCTL=${CLAUDE_NO_SLEEP_LAUNCHCTL:-/bin/launchctl}
HOOK_COMMAND="/bin/bash '$INSTALL_DIR/claude-no-sleep' wake"
SETTINGS_HOOK=(/usr/bin/osascript -l JavaScript "$REPO_DIR/lib/settings-hook.js")

die() {
  echo "claude-no-sleep: $*" >&2
  exit 1
}
