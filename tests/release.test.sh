#!/bin/bash
# Tests for build-release.sh: one release build in a temporary folder, read by every test.
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
FAILURES=0
TARBALL=claude-never-sleeps-darwin-universal.tar.gz

DIST=$(mktemp -d "${TMPDIR:-/tmp}/release-test.XXXXXX")
trap 'rm -rf "$DIST"' EXIT
"$REPO/build-release.sh" v0.0.0-test "$DIST/dist" >"$DIST/build.out" 2>&1 || { echo "release: build failed: $(cat "$DIST/build.out")"; exit 1; }

setup() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/release-test.XXXXXX")
  tar -xzf "$DIST/dist/$TARBALL" -C "$T"
}
teardown() { rm -rf "$T"; }
fail() { echo "FAIL $CASE: $*"; FAILURES=$((FAILURES + 1)); }

test_release_binary_is_universal_signed_and_runs() {
  local binary=$T/claude-never-sleeps/bin/claude-never-sleeps
  [ "$(lipo -archs "$binary")" = "x86_64 arm64" ] || fail "archs: $(lipo -archs "$binary")"
  codesign --verify "$binary" || fail "signature does not verify"
  [ "$("$binary" version)" = v0.0.0-test ] || fail "version: $("$binary" version)"
}

test_release_tarball_holds_the_install_files() {
  local want got
  want=$(printf 'claude-never-sleeps/%s\n' LICENSE README.md bin/claude-never-sleeps install.sh launchd/claude-never-sleeps.plist.template lib/paths.sh lib/settings-hook.js uninstall.sh | sort)
  got=$(tar -tzf "$DIST/dist/$TARBALL" | grep -v '/$' | sort)
  [ "$got" = "$want" ] || fail "tarball holds: $got"
}

test_checksums_verify() {
  (cd "$DIST/dist" && shasum -a 256 -c checksums.txt >/dev/null) || fail "checksums do not verify: $(cat "$DIST/dist/checksums.txt")"
}

for CASE in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
  setup
  "$CASE"
  teardown
done

if [ "$FAILURES" = 0 ]; then echo "release: all tests passed"; else echo "release: $FAILURES failure(s)"; exit 1; fi
