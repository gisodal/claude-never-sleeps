#!/bin/bash
# Tests for bin/claude-never-sleeps with fake pmset and osascript and real sleep processes as sessions; no sudo needed.
set -u

BIN=${1:-$(cd "$(dirname "$0")/.." && pwd)/bin/claude-never-sleeps}
FAILURES=0

setup() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/claude-never-sleeps-test.XXXXXX")
  mkdir -p "$T/sessions" "$T/state" "$T/bin"
  echo 0 >"$T/sleep_disabled"
  cat >"$T/bin/pmset" <<FAKE
#!/bin/bash
if [ "\$1" = -g ]; then
  echo 'System-wide power settings:'
  [ -e "$T/no_sleep_disabled_line" ] || printf ' SleepDisabled\t\t%s\n' "\$(cat "$T/sleep_disabled")"
  exit 0
fi
[ -e "$T/pmset_fails" ] && exit 1
echo "\$*" >>"$T/pmset_calls"
echo "\$3" >"$T/sleep_disabled"
FAKE
  cat >"$T/bin/osascript" <<FAKE
#!/bin/bash
echo "\$*" >>"$T/notifications"
FAKE
  chmod +x "$T/bin/"*
}

teardown() {
  local pid
  [ -e "$T/pids" ] && for pid in $(cat "$T/pids"); do
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  done
  rm -rf "$T"
}

run() {
  CLAUDE_NEVER_SLEEPS_SESSIONS_DIR=$T/sessions CLAUDE_NEVER_SLEEPS_STATE_DIR=$T/state CLAUDE_NEVER_SLEEPS_PMSET=$T/bin/pmset \
    CLAUDE_NEVER_SLEEPS_SUDO= CLAUDE_NEVER_SLEEPS_OSASCRIPT=$T/bin/osascript "$BIN" "$@"
}

real_start() { LC_ALL=C TZ=UTC ps -o lstart= -p "$1"; }

write_session() { printf '{"pid":%s,"status":"%s","procStart":"%s","kind":"interactive"}\n' "$1" "$2" "$3" >"$T/sessions/$1.json"; }

# session STATUS [PROC_START]: a registry file for a live sleep process; sets SESSION_PID
session() {
  sleep 300 >/dev/null 2>&1 &
  SESSION_PID=$!
  echo "$SESSION_PID" >>"$T/pids"
  write_session "$SESSION_PID" "$1" "${2:-$(real_start "$SESSION_PID")}"
}

idle_long_ago() { touch -t 202601010000 "$T/state/idle-since"; }

fail() { echo "FAIL $CASE: $*"; FAILURES=$((FAILURES + 1)); }

expect_sleep_disabled() {
  local got
  got=$(cat "$T/sleep_disabled")
  [ "$got" = "$1" ] || fail "SleepDisabled is $got, want $1"
}

notification_count() { if [ -e "$T/notifications" ]; then wc -l <"$T/notifications" | tr -d ' '; else echo 0; fi; }

test_busy_session_disables_sleep() { session busy; run poll; expect_sleep_disabled 1; }

test_background_shell_disables_sleep() { session shell; run poll; expect_sleep_disabled 1; }

test_idle_session_enables_sleep() { echo 1 >"$T/sleep_disabled"; session idle; idle_long_ago; run poll; expect_sleep_disabled 0; }

test_one_working_session_is_enough() { session idle; session busy; run poll; expect_sleep_disabled 1; }

test_no_sessions_dir_enables_sleep() {
  local err
  echo 1 >"$T/sleep_disabled"
  rm -rf "$T/sessions"
  idle_long_ago
  err=$(run poll 2>&1)
  expect_sleep_disabled 0
  [ -z "$err" ] || fail "stderr: $err"
}

test_dead_session_does_not_count() {
  echo 1 >"$T/sleep_disabled"
  session busy
  kill "$SESSION_PID"
  wait "$SESSION_PID" 2>/dev/null
  idle_long_ago
  run poll
  expect_sleep_disabled 0
}

test_reused_pid_does_not_count() {
  echo 1 >"$T/sleep_disabled"
  session busy "Tue Oct 13 06:00:00 2026"
  idle_long_ago
  run poll
  expect_sleep_disabled 0
}

test_padded_ps_start_time_matches() {
  local start
  session busy
  start=$(real_start "$SESSION_PID")
  write_session "$SESSION_PID" busy "  ${start// /  }   "
  run poll
  expect_sleep_disabled 1
}

test_file_without_proc_start_does_not_count() {
  echo 1 >"$T/sleep_disabled"
  printf '{"pid":%s,"status":"busy"}\n' $$ >"$T/sessions/$$.json"
  idle_long_ago
  run poll
  expect_sleep_disabled 0
}

test_incomplete_session_file_notifies_once_and_does_not_count() {
  echo 1 >"$T/sleep_disabled"
  printf '{"pid":%s,"status":"busy"}\n' $$ >"$T/sessions/$$.json"
  idle_long_ago
  run poll
  run poll
  expect_sleep_disabled 0
  [ "$(notification_count)" = 1 ] || fail "$(notification_count) notifications, want 1"
  grep -q 'session file without pid, status or procStart, counted as idle' "$T/notifications" || fail "no message"
}

test_wake_prints_nothing_and_exits_0() {
  local out
  out=$(run wake)
  [ $? = 0 ] && [ -z "$out" ] || fail "exit or stdout: $out"
  touch "$T/pmset_fails"
  echo 0 >"$T/sleep_disabled"
  out=$(run wake)
  [ $? = 0 ] && [ -z "$out" ] || fail "with failing pmset: exit or stdout: $out"
}

test_wake_survives_a_poll_that_still_reads_idle() { session idle; idle_long_ago; run wake; run poll; expect_sleep_disabled 1; }

test_old_wake_stamp_expires() {
  echo 1 >"$T/sleep_disabled"
  session idle
  touch -t 202601010000 "$T/state/wake"
  idle_long_ago
  run poll
  expect_sleep_disabled 0
}

test_auto_waits_for_the_idle_grace() {
  session idle
  run keep-awake
  expect_sleep_disabled 1
  run auto
  expect_sleep_disabled 1
  idle_long_ago
  run poll
  expect_sleep_disabled 0
}

test_short_idle_gap_keeps_sleep_off() {
  echo 1 >"$T/sleep_disabled"
  session idle
  run poll
  expect_sleep_disabled 1
  [ -e "$T/state/idle-since" ] || fail "no idle-since stamp"
  idle_long_ago
  run poll
  expect_sleep_disabled 0
}

test_work_clears_the_idle_stamp() {
  run poll
  [ -e "$T/state/idle-since" ] || fail "no idle-since stamp after an idle poll"
  session busy
  run poll
  [ ! -e "$T/state/idle-since" ] || fail "idle-since left after work"
}

test_status_names_the_mode() {
  local out
  out=$(run status)
  grep -q '^mode: auto (sessions decide)$' <<<"$out" || fail "no auto mode line in: $out"
  run keep-awake
  out=$(run status)
  grep -q "^mode: keep awake (until 'claude-never-sleeps auto')$" <<<"$out" || fail "no keep awake mode line in: $out"
}

test_no_write_when_value_already_matches() {
  echo 1 >"$T/sleep_disabled"
  session busy
  run poll
  [ ! -e "$T/pmset_calls" ] || fail "pmset written: $(cat "$T/pmset_calls")"
}

test_changes_are_logged_once() {
  session busy
  run poll
  run poll
  [ "$(grep -c 'disablesleep 1 (working)' "$T/state/log")" = 1 ] || fail "want one log line"
}

test_failed_write_is_logged() {
  touch "$T/pmset_fails"
  session busy
  run poll || fail "exit $?"
  run poll || fail "exit $?"
  [ "$(grep -c 'disablesleep 1 failed' "$T/state/log")" = 1 ] || fail "want one failure line"
  rm "$T/pmset_fails"
  run poll
  grep -q 'disablesleep 1 (' "$T/state/log" || fail "no success line after recovery"
}

test_unknown_status_counts_as_idle_and_notifies_once() {
  echo 1 >"$T/sleep_disabled"
  session waiting
  idle_long_ago
  run poll
  run poll
  expect_sleep_disabled 0
  [ "$(notification_count)" = 1 ] || fail "$(notification_count) notifications, want 1"
}

test_extra_fields_and_key_files_are_ignored() {
  session busy
  printf '{"pid":%s,"status":"busy","procStart":"%s","kind":"interactive","entrypoint":"cli","cwd":"/tmp"}\n' \
    "$SESSION_PID" "$(real_start "$SESSION_PID")" >"$T/sessions/$SESSION_PID.json"
  : >"$T/sessions/$SESSION_PID.abc.key"
  run poll
  expect_sleep_disabled 1
  [ ! -e "$T/notifications" ] || fail "notified: $(cat "$T/notifications")"
}

test_missing_sleep_disabled_line_reads_as_0() {
  touch "$T/no_sleep_disabled_line"
  session idle
  idle_long_ago
  run poll
  run poll
  [ ! -e "$T/pmset_calls" ] || fail "pmset written: $(cat "$T/pmset_calls")"
  [ ! -e "$T/state/log" ] || fail "logged: $(cat "$T/state/log")"
}

test_status_never_notifies() {
  session waiting
  run status >/dev/null
  [ ! -e "$T/notifications" ] || fail "notified: $(cat "$T/notifications")"
  [ -z "$(ls "$T/state" | grep '^seen-')" ] || fail "seen file written"
}

test_notification_message_with_quotes() {
  session 'wait\"ing'
  run poll
  [ "$(notification_count)" = 1 ] || fail "$(notification_count) notifications, want 1"
  grep -qF -- "-e end run unknown session status 'wait\"ing', counted as idle" "$T/notifications" || fail "message not in argv: $(cat "$T/notifications")"
  [ "$(ls "$T/state" | grep '^seen-')" = seen-status-wait_ing ] || fail "seen files: $(ls "$T/state")"
}

test_status_lists_sessions() {
  local out busy idle
  session busy
  busy=$SESSION_PID
  session idle
  idle=$SESSION_PID
  printf '{"pid":%s}\n' $$ >"$T/sessions/broken.json"
  out=$(run status)
  grep -q '^SleepDisabled: 0$' <<<"$out" || fail "no SleepDisabled line in: $out"
  grep -q "^session $busy: status busy, keeps the Mac awake: yes$" <<<"$out" || fail "no busy line in: $out"
  grep -q "^session $idle: status idle, keeps the Mac awake: no$" <<<"$out" || fail "no idle line in: $out"
  grep -q '^session broken: incomplete file, keeps the Mac awake: no$' <<<"$out" || fail "no incomplete line in: $out"
}

test_version_prints_dev() {
  local out
  out=$(run version)
  [ $? = 0 ] && [ "$out" = dev ] || fail "exit or stdout: $out"
}

test_unknown_mode_exits_1_not_2() {
  local rc
  run bogus 2>/dev/null
  rc=$?
  [ "$rc" = 1 ] || fail "exit $rc, want 1"
}

for CASE in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
  setup
  "$CASE"
  teardown
done

if [ "$FAILURES" = 0 ]; then echo "claude-never-sleeps: all tests passed"; else echo "claude-never-sleeps: $FAILURES failure(s)"; exit 1; fi
