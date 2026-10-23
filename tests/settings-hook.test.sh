#!/bin/bash
# Tests for lib/settings-hook.js on temporary settings files.
set -u

JS=$(cd "$(dirname "$0")/.." && pwd)/lib/settings-hook.js
HOOK="/bin/bash '/opt/example/claude-never-sleeps/claude-never-sleeps' wake"
FAILURES=0

setup() { T=$(mktemp -d "${TMPDIR:-/tmp}/settings-hook-test.XXXXXX"); }
teardown() { rm -rf "$T"; }
hook() { /usr/bin/osascript -l JavaScript "$JS" "$@" >/dev/null 2>&1; }
field() { /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null; }
fail() { echo "FAIL $CASE: $*"; FAILURES=$((FAILURES + 1)); }

# settings in the layout JSON.stringify(settings, null, 2) writes, so a byte compare works
user_settings() {
  cat >"$T/settings.json" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "my-own-hook.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "my-stop-hook.sh"
          }
        ]
      }
    ]
  }
}
JSON
  cp "$T/settings.json" "$T/original.json"
}

test_add_keeps_other_hooks_and_keys() {
  user_settings
  hook add "$T/settings.json" "$HOOK" || fail "add failed"
  [ "$(field "$T/settings.json" model)" = opus ] || fail "model lost"
  [ "$(field "$T/settings.json" hooks.Stop.0.hooks.0.command)" = my-stop-hook.sh ] || fail "Stop hook lost"
  [ "$(field "$T/settings.json" hooks.UserPromptSubmit.0.hooks.0.command)" = my-own-hook.sh ] || fail "own prompt hook lost"
  [ "$(field "$T/settings.json" hooks.UserPromptSubmit.1.hooks.0.command)" = "$HOOK" ] || fail "hook not added"
}

test_add_twice_gives_one_hook() {
  user_settings
  hook add "$T/settings.json" "$HOOK"
  hook add "$T/settings.json" "$HOOK"
  [ "$(field "$T/settings.json" hooks.UserPromptSubmit)" = 2 ] || fail "want 2 groups, got $(field "$T/settings.json" hooks.UserPromptSubmit)"
}

test_remove_gives_back_the_original_bytes() {
  user_settings
  hook add "$T/settings.json" "$HOOK"
  hook remove "$T/settings.json" || fail "remove failed"
  cmp -s "$T/original.json" "$T/settings.json" || fail "file differs from the original"
}

test_add_to_missing_file_then_remove_leaves_empty_object() {
  hook add "$T/settings.json" "$HOOK" || fail "add failed"
  [ "$(field "$T/settings.json" hooks.UserPromptSubmit.0.hooks.0.command)" = "$HOOK" ] || fail "hook not added"
  hook remove "$T/settings.json"
  [ "$(cat "$T/settings.json")" = "{}" ] || fail "want {}, got $(cat "$T/settings.json")"
}

test_remove_keeps_a_neighbour_in_the_same_group() {
  printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"mine.sh"},{"type":"command","command":"%s"}]}]}}\n' "$HOOK" >"$T/settings.json"
  hook remove "$T/settings.json"
  [ "$(field "$T/settings.json" hooks.UserPromptSubmit.0.hooks)" = 1 ] || fail "want one hook left"
  [ "$(field "$T/settings.json" hooks.UserPromptSubmit.0.hooks.0.command)" = mine.sh ] || fail "neighbour lost"
}

test_invalid_json_fails_and_is_not_changed() {
  echo '{bad' >"$T/settings.json"
  hook add "$T/settings.json" "$HOOK" && fail "add succeeded on invalid JSON"
  hook check "$T/settings.json" && fail "check succeeded on invalid JSON"
  [ "$(cat "$T/settings.json")" = '{bad' ] || fail "file changed"
}

test_unreadable_file_is_left_alone() {
  user_settings
  chmod 000 "$T/settings.json"
  hook add "$T/settings.json" "$HOOK" && fail "add succeeded on unreadable file"
  chmod 644 "$T/settings.json"
  cmp -s "$T/original.json" "$T/settings.json" || fail "file changed"
}

test_symlinked_settings_stays_a_symlink() {
  mkdir "$T/dotfiles"
  user_settings
  mv "$T/settings.json" "$T/dotfiles/settings.json"
  ln -s "$T/dotfiles/settings.json" "$T/settings.json"
  hook add "$T/settings.json" "$HOOK" || fail "add failed"
  [ -L "$T/settings.json" ] || fail "symlink replaced"
  [ "$(field "$T/dotfiles/settings.json" hooks.UserPromptSubmit.1.hooks.0.command)" = "$HOOK" ] || fail "hook not in target"
  hook remove "$T/settings.json" || fail "remove failed"
  [ -L "$T/settings.json" ] || fail "symlink replaced on remove"
  cmp -s "$T/original.json" "$T/dotfiles/settings.json" || fail "target differs from the original"
}

test_remove_without_our_hook_leaves_the_bytes() {
  printf '{\n    "model": "opus"\n}\n' >"$T/settings.json"
  cp "$T/settings.json" "$T/original.json"
  hook remove "$T/settings.json" || fail "remove failed"
  cmp -s "$T/original.json" "$T/settings.json" || fail "file changed"
}

test_remove_on_a_missing_file_creates_nothing() {
  hook remove "$T/settings.json" || fail "remove failed"
  [ ! -e "$T/settings.json" ] || fail "file created"
}

for CASE in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
  setup
  "$CASE"
  teardown
done

if [ "$FAILURES" = 0 ]; then echo "settings-hook: all tests passed"; else echo "settings-hook: $FAILURES failure(s)"; exit 1; fi
