#!/bin/bash
# Tests for get.sh against a fake release in a temporary folder, read through file:// URLs.
set -u

GET_SH=$(cd "$(dirname "$0")/.." && pwd)/get.sh
TARBALL=claude-never-sleeps-darwin-universal.tar.gz
FAILURES=0

# a release whose install.sh records its arguments and its stdin instead of installing
setup() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/get-test.XXXXXX")
  mkdir -p "$T/stage/claude-never-sleeps" "$T/release" "$T/tmp"
  cat >"$T/stage/claude-never-sleeps/install.sh" <<FAKE
#!/bin/bash
echo "\$*" >"$T/ran"
cat >"$T/stdin_seen"
FAKE
  chmod +x "$T/stage/claude-never-sleeps/install.sh"
  COPYFILE_DISABLE=1 tar -czf "$T/release/$TARBALL" -C "$T/stage" claude-never-sleeps
  (cd "$T/release" && shasum -a 256 "$TARBALL" >checksums.txt)
}

teardown() { rm -rf "$T"; }

get() { CLAUDE_NEVER_SLEEPS_RELEASE_URL=file://$1 TMPDIR=$T/tmp sh <"$GET_SH" >"$T/out" 2>&1; }

fail() { echo "FAIL $CASE: $*"; FAILURES=$((FAILURES + 1)); }

test_installs_from_the_release() {
  get "$T/release" || fail "exit $?: $(cat "$T/out")"
  [ -e "$T/ran" ] || fail "install.sh did not run"
}

test_installer_stdin_is_not_the_script() {
  get "$T/release"
  [ -e "$T/stdin_seen" ] && [ ! -s "$T/stdin_seen" ] || fail "install.sh read: $(cat "$T/stdin_seen" 2>/dev/null)"
}

test_checksum_mismatch_stops_before_install() {
  printf x >>"$T/release/$TARBALL"
  get "$T/release" && fail "get.sh succeeded"
  [ ! -e "$T/ran" ] || fail "install.sh ran"
  grep -qi checksum "$T/out" || fail "output does not name the checksum: $(cat "$T/out")"
}

test_download_failure_stops() {
  mkdir "$T/empty"
  get "$T/empty" && fail "get.sh succeeded"
  [ ! -e "$T/ran" ] || fail "install.sh ran"
}

test_temp_dir_is_removed() {
  get "$T/release"
  [ -z "$(ls "$T/tmp" | grep '^claude-never-sleeps\.')" ] || fail "left: $(ls "$T/tmp")"
}

for CASE in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
  setup
  "$CASE"
  teardown
done

if [ "$FAILURES" = 0 ]; then echo "get: all tests passed"; else echo "get: $FAILURES failure(s)"; exit 1; fi
