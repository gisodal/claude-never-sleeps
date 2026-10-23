#!/bin/bash
# Installs claude-never-sleeps for the current user: the binary, a sudoers rule for two pmset commands, the Claude Code hook and the launchd agent.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
. "$REPO_DIR/lib/paths.sh"

check_platform() {
  [ "$(uname -s)" = Darwin ] || die "macOS only"
  [ "$(id -u)" != 0 ] || die "run this as your own user, not as root"
  "$REPO_DIR/bin/claude-never-sleeps" version >/dev/null 2>&1 || die "no bin/claude-never-sleeps; build it with: go build -o bin/claude-never-sleeps ."
  [ -d "$CLAUDE_DIR" ] || die "no $CLAUDE_DIR; start Claude Code once first"
  [ -d "$CLAUDE_DIR/sessions" ] || echo "claude-never-sleeps: warning: no $CLAUDE_DIR/sessions; it needs Claude Code 2.1.296 or newer" >&2
  if [ -e "$SETTINGS" ]; then "${SETTINGS_HOOK[@]}" check "$SETTINGS" >/dev/null || die "$SETTINGS is not valid JSON; nothing installed"; fi
}

# only the two exact commands the binary runs, so the rule cannot be used for anything else
sudoers_rule_text() {
  echo "$(id -un) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
}

write_sudoers_rule() {
  local rule=$1
  sudoers_rule_text >"$rule"
  "$VISUDO" -c -q -f "$rule" || die "the sudoers rule failed validation; nothing installed"
}

install_files() {
  mkdir -p "$INSTALL_DIR/lib" "$STATE_DIR"
  /usr/bin/install -m 755 "$REPO_DIR/bin/claude-never-sleeps" "$REPO_DIR/uninstall.sh" "$INSTALL_DIR/"
  /usr/bin/install -m 644 "$REPO_DIR/lib/paths.sh" "$REPO_DIR/lib/settings-hook.js" "$INSTALL_DIR/lib/"
}

install_sudoers_rule() {
  local rule=$1 current
  echo "sudo asks for your password once, to add the pmset rule in $SUDOERS_FILE"
  "$SUDO" /usr/bin/install -m 0440 "$rule" "$SUDOERS_FILE"
  if [ "$("$SUDO" /bin/cat "$SUDOERS_FILE")" != "$(sudoers_rule_text)" ]; then
    "$SUDO" rm -f "$SUDOERS_FILE"
    die "the installed sudoers rule differs from the validated one, so it was removed"
  fi
  if ! "$SUDO" "$VISUDO" -c -q; then
    "$SUDO" rm -f "$SUDOERS_FILE"
    die "sudo rejected the rule, so it was removed again"
  fi
  # drop the cached credential, then a no-op write proves the rule works without a password
  "$SUDO" -k
  current=$(/usr/bin/pmset -g | awk '/SleepDisabled/ {print $2}')
  "$SUDO" -n /usr/bin/pmset -a disablesleep "${current:-0}" || die "sudo still asks a password for pmset"
}

install_hook() {
  # the backup keeps the original from before the first install
  if [ -e "$SETTINGS" ] && [ ! -e "$SETTINGS.claude-never-sleeps.bak" ]; then cp "$SETTINGS" "$SETTINGS.claude-never-sleeps.bak"; fi
  "${SETTINGS_HOOK[@]}" add "$SETTINGS" "$HOOK_COMMAND" >/dev/null
}

install_launch_agent() {
  local attempt
  mkdir -p "$(dirname "$PLIST")"
  sed -e "s|__LABEL__|$LABEL|" -e "s|__BINARY__|$INSTALL_DIR/claude-never-sleeps|" \
    -e "s|__CLAUDE_DIR__|$CLAUDE_DIR|" -e "s|__STATE_DIR__|$STATE_DIR|" \
    "$REPO_DIR/launchd/claude-never-sleeps.plist.template" >"$PLIST"
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
  RULE_FILE=$(mktemp "${TMPDIR:-/tmp}/claude-never-sleeps-sudoers.XXXXXX")
  trap 'rm -f "$RULE_FILE"' EXIT
  write_sudoers_rule "$RULE_FILE"
  # the binary replaces an older one only after the password step, which the user can abort
  install_sudoers_rule "$RULE_FILE"
  install_files
  install_hook
  install_launch_agent
  "$INSTALL_DIR/claude-never-sleeps" status
  echo "claude-never-sleeps is installed. Remove it with: $INSTALL_DIR/uninstall.sh"
}

main "$@"
