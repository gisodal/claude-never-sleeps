#!/bin/bash
# Tests for bin/claude-no-sleep with fake pmset, ps and osascript; no sudo needed.
set -u

SCRIPT=${1:-$(cd "$(dirname "$0")/.." && pwd)/bin/claude-no-sleep}
FAILURES=0
START="Mon Oct 12 17:39:44 2026"

setup() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/claude-no-sleep-test.XXXXXX")
  mkdir -p "$T/sessions" "$T/state" "$T/procs" "$T/bin"
  echo 0 >"$T/sleep_disabled"
  cat >"$T/bin/pmset" <<FAKE
#!/bin/bash
if [ "\$1" = -g ]; then printf 'System-wide power settings:\n SleepDisabled\t\t%s\n' "\$(cat "$T/sleep_disabled")"; exit 0; fi
[ -e "$T/pmset_fails" ] && exit 1
echo "\$*" >>"$T/pmset_calls"
echo "\$3" >"$T/sleep_disabled"
FAKE
  cat >"$T/bin/ps" <<FAKE
#!/bin/bash
[ -e "$T/procs/\$4" ] || exit 1
cat "$T/procs/\$4"
FAKE
  cat >"$T/bin/osascript" <<FAKE
#!/bin/bash
echo "\$*" >>"$T/notifications"
FAKE
  chmod +x "$T/bin/"*
}

teardown() { rm -rf "$T"; }

run() {
  CLAUDE_NO_SLEEP_SESSIONS_DIR=$T/sessions CLAUDE_NO_SLEEP_STATE_DIR=$T/state CLAUDE_NO_SLEEP_PMSET=$T/bin/pmset \
    CLAUDE_NO_SLEEP_SUDO= CLAUDE_NO_SLEEP_PS=$T/bin/ps CLAUDE_NO_SLEEP_OSASCRIPT=$T/bin/osascript /bin/bash "$SCRIPT" "$@"
}

# session PID STATUS [PROC_START]: a registry file plus a live fake process that started at PROC_START
session() {
  local start=${3:-$START}
  printf '{"pid":%s,"status":"%s","procStart":"%s","kind":"interactive"}\n' "$1" "$2" "$start" >"$T/sessions/$1.json"
  echo "$start" >"$T/procs/$1"
}

fail() { echo "FAIL $CASE: $*"; FAILURES=$((FAILURES + 1)); }

expect_sleep_disabled() {
  local got
  got=$(cat "$T/sleep_disabled")
  [ "$got" = "$1" ] || fail "SleepDisabled is $got, want $1"
}

test_busy_session_disables_sleep() { session 101 busy; run poll; expect_sleep_disabled 1; }

test_background_shell_disables_sleep() { session 101 shell; run poll; expect_sleep_disabled 1; }

test_idle_session_enables_sleep() { echo 1 >"$T/sleep_disabled"; session 101 idle; run poll; expect_sleep_disabled 0; }

test_one_working_session_is_enough() { session 101 idle; session 102 busy; run poll; expect_sleep_disabled 1; }

test_no_sessions_dir_enables_sleep() {
  local err
  echo 1 >"$T/sleep_disabled"
  rm -rf "$T/sessions"
  err=$(run poll 2>&1)
  expect_sleep_disabled 0
  [ -z "$err" ] || fail "stderr: $err"
}

test_dead_session_does_not_count() {
  echo 1 >"$T/sleep_disabled"
  session 101 busy
  rm "$T/procs/101"
  run poll
  expect_sleep_disabled 0
}

test_reused_pid_does_not_count() {
  echo 1 >"$T/sleep_disabled"
  session 101 busy
  echo "Tue Oct 13 06:00:00 2026" >"$T/procs/101"
  run poll
  expect_sleep_disabled 0
}

test_padded_ps_start_time_matches() {
  session 101 busy "Fri Oct  9 21:14:49 2026"
  echo "Fri Oct  9 21:14:49 2026   " >"$T/procs/101"
  run poll
  expect_sleep_disabled 1
}

test_file_without_proc_start_does_not_count() {
  echo 1 >"$T/sleep_disabled"
  printf '{"pid":101,"status":"busy"}\n' >"$T/sessions/101.json"
  echo "$START" >"$T/procs/101"
  run poll
  expect_sleep_disabled 0
}

test_wake_survives_a_poll_that_still_reads_idle() { session 101 idle; run wake; run poll; expect_sleep_disabled 1; }

test_old_wake_stamp_expires() {
  echo 1 >"$T/sleep_disabled"
  session 101 idle
  touch -t 202601010000 "$T/state/wake"
  run poll
  expect_sleep_disabled 0
}

test_manual_override_beats_idle() {
  session 101 idle
  run manual-on
  run poll
  expect_sleep_disabled 1
  run manual-off
  expect_sleep_disabled 0
}

test_no_write_when_value_already_matches() {
  echo 1 >"$T/sleep_disabled"
  session 101 busy
  run poll
  [ ! -e "$T/pmset_calls" ] || fail "pmset written: $(cat "$T/pmset_calls")"
}

test_changes_are_logged_once() {
  session 101 busy
  run poll
  run poll
  [ "$(grep -c 'disablesleep 1 (working)' "$T/state/log")" = 1 ] || fail "want one log line"
}

test_failed_write_is_logged() {
  touch "$T/pmset_fails"
  session 101 busy
  run poll || fail "exit $?"
  grep -q 'disablesleep 1 failed' "$T/state/log" || fail "no failure line in log"
}

test_unknown_status_counts_as_idle_and_notifies_once() {
  local count=0
  echo 1 >"$T/sleep_disabled"
  session 101 waiting
  run poll
  run poll
  expect_sleep_disabled 0
  [ -e "$T/notifications" ] && count=$(wc -l <"$T/notifications" | tr -d ' ')
  [ "$count" = 1 ] || fail "$count notifications, want 1"
}

test_status_lists_sessions() {
  local out
  session 101 busy
  session 102 idle
  out=$(run status)
  grep -q '^SleepDisabled: 0$' <<<"$out" || fail "no SleepDisabled line in: $out"
  grep -q '^session 101: status busy, keeps the Mac awake: yes$' <<<"$out" || fail "no busy line in: $out"
  grep -q '^session 102: status idle, keeps the Mac awake: no$' <<<"$out" || fail "no idle line in: $out"
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

if [ "$FAILURES" = 0 ]; then echo "claude-no-sleep: all tests passed"; else echo "claude-no-sleep: $FAILURES failure(s)"; exit 1; fi
