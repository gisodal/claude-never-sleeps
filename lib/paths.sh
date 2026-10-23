# Paths and commands shared by install.sh and uninstall.sh; tests override the system commands and the sudoers file.
LABEL=dev.claude-never-sleeps
use_claude_dir() {
  CLAUDE_DIR=$1
  SETTINGS=$CLAUDE_DIR/settings.json
}
use_claude_dir "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
INSTALL_DIR=$HOME/.local/share/claude-never-sleeps
STATE_DIR=$HOME/.local/state/claude-never-sleeps
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
SUDOERS_FILE=${CLAUDE_NEVER_SLEEPS_SUDOERS_FILE:-/etc/sudoers.d/claude-never-sleeps}
SUDO=${CLAUDE_NEVER_SLEEPS_SUDO:-/usr/bin/sudo}
VISUDO=${CLAUDE_NEVER_SLEEPS_VISUDO:-/usr/sbin/visudo}
LAUNCHCTL=${CLAUDE_NEVER_SLEEPS_LAUNCHCTL:-/bin/launchctl}
HOOK_COMMAND="'$INSTALL_DIR/claude-never-sleeps' wake"
SETTINGS_HOOK=(/usr/bin/osascript -l JavaScript "$REPO_DIR/lib/settings-hook.js")

die() {
  echo "claude-never-sleeps: $*" >&2
  exit 1
}
