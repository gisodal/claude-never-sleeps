#!/bin/bash
# Tests for install.sh and uninstall.sh in a temporary HOME, with fake sudo, visudo and launchctl.
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
FAILURES=0

setup() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX")
  mkdir -p "$T/home/.claude/sessions" "$T/etc/sudoers.d" "$T/bin"
  cat >"$T/bin/sudo" <<FAKE
#!/bin/bash
echo "\$*" >>"$T/sudo_calls"
[ "\$1" = -n ] && shift
[ "\$1" = -l ] && exit 0
[ "\$1" = /usr/bin/pmset ] && exit 0
[ "\$1" = rm ] && [ -e "$T/sudo_rm_fails" ] && exit 1
[ "\$1" = /usr/bin/install ] && [ -e "$T/sudo_install_tampers" ] && echo "tampered ALL=(ALL) NOPASSWD: ALL" >>"\$4"
exec "\$@"
FAKE
  cat >"$T/bin/visudo" <<FAKE
#!/bin/bash
[ -e "$T/visudo_fails" ] && exit 1
exit 0
FAKE
  cat >"$T/bin/launchctl" <<FAKE
#!/bin/bash
echo "\$*" >>"$T/launchctl_calls"
FAKE
  chmod +x "$T/bin/"*
}

teardown() { rm -rf "$T"; }

with_fakes() {
  HOME=$T/home CLAUDE_CONFIG_DIR= CLAUDE_NO_SLEEP_SUDOERS_FILE=$T/etc/sudoers.d/claude-no-sleep CLAUDE_NO_SLEEP_SUDO=$T/bin/sudo \
    CLAUDE_NO_SLEEP_VISUDO=$T/bin/visudo CLAUDE_NO_SLEEP_LAUNCHCTL=$T/bin/launchctl CLAUDE_NO_SLEEP_PMSET=/bin/echo "$@" >"$T/out" 2>&1
}

field() { /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null; }
fail() { echo "FAIL $CASE: $*"; FAILURES=$((FAILURES + 1)); }

user_settings() { printf '{\n  "model": "opus",\n  "hooks": {\n    "Stop": [\n      {\n        "hooks": [\n          {\n            "type": "command",\n            "command": "my-stop-hook.sh"\n          }\n        ]\n      }\n    ]\n  }\n}\n' >"$T/home/.claude/settings.json"; }

test_install_sets_up_everything() {
  user_settings
  with_fakes "$REPO/install.sh" || fail "install failed: $(cat "$T/out")"
  [ -x "$T/home/.local/share/claude-no-sleep/claude-no-sleep" ] || fail "script not installed"
  [ -x "$T/home/.local/share/claude-no-sleep/uninstall.sh" ] || fail "uninstall.sh not installed"
  grep -q "^$(id -un) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1$" "$T/etc/sudoers.d/claude-no-sleep" || fail "sudoers rule wrong"
  [ "$(field "$T/home/Library/LaunchAgents/dev.claude-no-sleep.plist" ProgramArguments.1)" = "$T/home/.local/share/claude-no-sleep/claude-no-sleep" ] || fail "plist script path wrong"
  [ "$(field "$T/home/Library/LaunchAgents/dev.claude-no-sleep.plist" EnvironmentVariables.CLAUDE_CONFIG_DIR)" = "$T/home/.claude" ] || fail "plist CLAUDE_CONFIG_DIR wrong"
  grep -q "^bootstrap gui/$(id -u) $T/home/Library/LaunchAgents/dev.claude-no-sleep.plist$" "$T/launchctl_calls" || fail "agent not bootstrapped"
  [ "$(field "$T/home/.claude/settings.json" hooks.UserPromptSubmit.0.hooks.0.command)" = "/bin/bash '$T/home/.local/share/claude-no-sleep/claude-no-sleep' wake" ] || fail "hook not added"
  [ "$(field "$T/home/.claude/settings.json" hooks.Stop.0.hooks.0.command)" = my-stop-hook.sh ] || fail "user hook lost"
}

test_install_twice_gives_one_hook() {
  user_settings
  with_fakes "$REPO/install.sh"
  with_fakes "$REPO/install.sh" || fail "second install failed: $(cat "$T/out")"
  [ "$(field "$T/home/.claude/settings.json" hooks.UserPromptSubmit)" = 1 ] || fail "want one hook group"
}

test_invalid_settings_stops_before_any_change() {
  echo '{bad' >"$T/home/.claude/settings.json"
  with_fakes "$REPO/install.sh" && fail "install succeeded"
  [ ! -e "$T/home/.local/share/claude-no-sleep" ] || fail "files installed"
  [ ! -e "$T/etc/sudoers.d/claude-no-sleep" ] || fail "sudoers rule installed"
  [ "$(cat "$T/home/.claude/settings.json")" = '{bad' ] || fail "settings changed"
}

test_rejected_sudoers_rule_stops_before_any_change() {
  user_settings
  touch "$T/visudo_fails"
  with_fakes "$REPO/install.sh" && fail "install succeeded"
  [ ! -e "$T/home/.local/share/claude-no-sleep" ] || fail "files installed"
  [ ! -e "$T/etc/sudoers.d/claude-no-sleep" ] || fail "sudoers rule installed"
  [ ! -e "$T/home/.claude/settings.json.claude-no-sleep.bak" ] || fail "settings touched"
}

test_uninstall_removes_everything_and_keeps_user_settings() {
  user_settings
  cp "$T/home/.claude/settings.json" "$T/original.json"
  with_fakes "$REPO/install.sh"
  with_fakes "$T/home/.local/share/claude-no-sleep/uninstall.sh" || fail "uninstall failed: $(cat "$T/out")"
  cmp -s "$T/original.json" "$T/home/.claude/settings.json" || fail "settings differ from the original"
  [ ! -e "$T/home/.local/share/claude-no-sleep" ] || fail "install dir left"
  [ ! -e "$T/home/.local/state/claude-no-sleep" ] || fail "state dir left"
  [ ! -e "$T/home/Library/LaunchAgents/dev.claude-no-sleep.plist" ] || fail "plist left"
  [ ! -e "$T/etc/sudoers.d/claude-no-sleep" ] || fail "sudoers rule left"
  grep -q '^/usr/bin/pmset -a disablesleep 0$' "$T/sudo_calls" || fail "sleep not turned back on"
  grep -q "^bootout gui/$(id -u)/dev.claude-no-sleep$" "$T/launchctl_calls" || fail "agent not booted out"
}

test_uninstall_twice_is_harmless() {
  user_settings
  cp "$T/home/.claude/settings.json" "$T/original.json"
  with_fakes "$REPO/install.sh"
  with_fakes "$REPO/uninstall.sh"
  with_fakes "$REPO/uninstall.sh" || fail "second uninstall failed: $(cat "$T/out")"
  grep -q "could not remove" "$T/out" && fail "second uninstall could not remove the hook"
  cmp -s "$T/original.json" "$T/home/.claude/settings.json" || fail "settings differ from the original"
}

test_failed_rule_removal_keeps_the_uninstaller() {
  user_settings
  with_fakes "$REPO/install.sh"
  touch "$T/sudo_rm_fails"
  with_fakes "$T/home/.local/share/claude-no-sleep/uninstall.sh" && fail "uninstall succeeded"
  [ -e "$T/etc/sudoers.d/claude-no-sleep" ] || fail "sudoers rule removed"
  [ -e "$T/home/.local/share/claude-no-sleep/uninstall.sh" ] || fail "uninstall.sh removed"
  grep -q "not fully removed" "$T/out" || fail "no not-fully-removed message"
}

test_tampered_rule_is_removed() {
  user_settings
  touch "$T/sudo_install_tampers"
  with_fakes "$REPO/install.sh" && fail "install succeeded"
  [ ! -e "$T/etc/sudoers.d/claude-no-sleep" ] || fail "tampered rule left"
  grep -q "differs from the validated one" "$T/out" || fail "no tamper message"
}

test_second_uninstall_skips_sudo() {
  user_settings
  with_fakes "$REPO/install.sh"
  with_fakes "$REPO/uninstall.sh"
  rm -f "$T/sudo_calls"
  with_fakes "$REPO/uninstall.sh" || fail "second uninstall failed: $(cat "$T/out")"
  [ ! -s "$T/sudo_calls" ] || fail "second uninstall called sudo"
}

for CASE in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
  setup
  "$CASE"
  teardown
done

if [ "$FAILURES" = 0 ]; then echo "install: all tests passed"; else echo "install: $FAILURES failure(s)"; exit 1; fi
