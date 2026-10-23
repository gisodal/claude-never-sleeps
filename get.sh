#!/bin/sh
# Downloads the latest claude-never-sleeps release, checks its SHA-256 and runs its install.sh.
# Run it with: curl -fsSL https://github.com/gisodal/claude-never-sleeps/releases/latest/download/get.sh | sh

RELEASE_URL=${CLAUDE_NEVER_SLEEPS_RELEASE_URL:-https://github.com/gisodal/claude-never-sleeps/releases/latest/download}
TARBALL=claude-never-sleeps-darwin-universal.tar.gz

die() {
  echo "claude-never-sleeps: $*" >&2
  exit 1
}

download() {
  curl -fsSL -o "$2" "$RELEASE_URL/$1" || die "could not download $RELEASE_URL/$1"
}

verify_checksum() {
  (cd "$1" && grep "  $TARBALL\$" checksums.txt | shasum -a 256 -c - >/dev/null 2>&1) ||
    die "the checksum of $TARBALL does not match checksums.txt; nothing installed"
}

# the body runs from main on the last line, so sh has read the whole script before install.sh starts
main() {
  [ "$(uname -s)" = Darwin ] || die "macOS only"
  dir=$(mktemp -d "${TMPDIR:-/tmp}/claude-never-sleeps.XXXXXX") || die "could not make a temporary folder"
  trap 'rm -rf "$dir"' EXIT
  download "$TARBALL" "$dir/$TARBALL"
  download checksums.txt "$dir/checksums.txt"
  verify_checksum "$dir"
  tar -xzf "$dir/$TARBALL" -C "$dir" || die "could not extract $TARBALL"
  # stdin is the script when piped from curl; the installer asks sudo for the password on the terminal
  /bin/bash "$dir/claude-never-sleeps/install.sh" </dev/null
}

main "$@"
