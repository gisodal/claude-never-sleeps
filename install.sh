#!/bin/bash
# Installs claude-no-sleep for the current user: the script, a sudoers rule for two pmset commands, the Claude Code hook and the launchd agent.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
. "$REPO_DIR/lib/paths.sh"

check_platform() {
  [ "$(uname -s)" = Darwin ] || die "macOS only"
  [ "$(id -u)" != 0 ] || die "run this as your own user, not as root"
  [ -d "$CLAUDE_DIR" ] || die "no $CLAUDE_DIR; start Claude Code once first"
  [ -d "$CLAUDE_DIR/sessions" ] || echo "claude-no-sleep: warning: no $CLAUDE_DIR/sessions; it needs Claude Code 2.1.296 or newer" >&2
  if [ -e "$SETTINGS" ]; then "${SETTINGS_HOOK[@]}" check "$SETTINGS" >/dev/null || die "$SETTINGS is not valid JSON; nothing installed"; fi
}

# only the two exact commands the script runs, so the rule cannot be used for anything else
write_sudoers_rule() {
  local rule=$1
  echo "$(id -un) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" >"$rule"
  "$VISUDO" -c -q -f "$rule" || die "the sudoers rule failed validation; nothing installed"
}

install_files() {
  mkdir -p "$INSTALL_DIR/lib" "$STATE_DIR"
  /usr/bin/install -m 755 "$REPO_DIR/bin/claude-no-sleep" "$REPO_DIR/uninstall.sh" "$INSTALL_DIR/"
  /usr/bin/install -m 644 "$REPO_DIR/lib/paths.sh" "$REPO_DIR/lib/settings-hook.js" "$INSTALL_DIR/lib/"
}

install_sudoers_rule() {
  local rule=$1
  echo "sudo asks for your password once, to add the pmset rule in $SUDOERS_FILE"
  "$SUDO" /usr/bin/install -m 0440 "$rule" "$SUDOERS_FILE"
  if ! "$SUDO" /bin/cat "$SUDOERS_FILE" | /usr/bin/cmp -s - "$rule"; then
    "$SUDO" rm -f "$SUDOERS_FILE"
    die "the installed sudoers rule differs from the validated one, so it was removed"
  fi
  if ! "$SUDO" "$VISUDO" -c -q; then
    "$SUDO" rm -f "$SUDOERS_FILE"
    die "sudo rejected the rule, so it was removed again"
  fi
  "$SUDO" -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null || die "sudo still asks a password for pmset"
}

install_hook() {
  [ -e "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.claude-no-sleep.bak"
  "${SETTINGS_HOOK[@]}" add "$SETTINGS" "$HOOK_COMMAND" >/dev/null
}

install_launch_agent() {
  local attempt
  mkdir -p "$(dirname "$PLIST")"
  sed -e "s|__LABEL__|$LABEL|" -e "s|__SCRIPT__|$INSTALL_DIR/claude-no-sleep|" \
    -e "s|__CLAUDE_DIR__|$CLAUDE_DIR|" -e "s|__STATE_DIR__|$STATE_DIR|" \
    "$REPO_DIR/launchd/claude-no-sleep.plist.template" >"$PLIST"
  /usr/bin/plutil -lint -s "$PLIST"
  "$LAUNCHCTL" bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  # bootstrap right after bootout can fail while launchd still removes the old job
  for attempt in 1 2 3 4 5; do
    "$LAUNCHCTL" bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null && return 0
    sleep 1
  done
  die "launchctl bootstrap failed; run it in a logged-in desktop session, not over ssh"
}

main() {
  check_platform
  RULE_FILE=$(mktemp "${TMPDIR:-/tmp}/claude-no-sleep-sudoers.XXXXXX")
  trap 'rm -f "$RULE_FILE"' EXIT
  write_sudoers_rule "$RULE_FILE"
  install_files
  install_sudoers_rule "$RULE_FILE"
  install_hook
  install_launch_agent
  "$INSTALL_DIR/claude-no-sleep" status
  echo "claude-no-sleep is installed. Remove it with: $INSTALL_DIR/uninstall.sh"
}

main "$@"
