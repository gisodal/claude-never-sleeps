#!/bin/bash
# Builds the release assets: a tarball with a universal, ad-hoc signed binary and the install files, get.sh and checksums.txt.
set -euo pipefail

VERSION=${1:?usage: build-release.sh VERSION [OUT_DIR]}
OUT_DIR=${2:-dist}
REPO_DIR=$(cd "$(dirname "$0")" && pwd)
TARBALL=claude-never-sleeps-darwin-universal.tar.gz

build_universal_binary() {
  local binary=$1 arch
  for arch in arm64 amd64; do
    (cd "$REPO_DIR" && CGO_ENABLED=0 GOOS=darwin GOARCH=$arch go build -trimpath -ldflags "-s -w -X main.version=$VERSION" -o "$BUILD/$arch" .)
  done
  lipo -create -output "$binary" "$BUILD/amd64" "$BUILD/arm64"
  # Apple silicon runs no unsigned code, and lipo output needs a fresh signature
  codesign --force --sign - "$binary"
}

stage_install_files() {
  local folder=$1
  mkdir -p "$folder/bin" "$folder/lib" "$folder/launchd"
  build_universal_binary "$folder/bin/claude-never-sleeps"
  cp "$REPO_DIR/install.sh" "$REPO_DIR/uninstall.sh" "$REPO_DIR/README.md" "$REPO_DIR/LICENSE" "$folder/"
  cp "$REPO_DIR/lib/paths.sh" "$REPO_DIR/lib/settings-hook.js" "$folder/lib/"
  cp "$REPO_DIR/launchd/claude-never-sleeps.plist.template" "$folder/launchd/"
}

write_release_assets() {
  local assets=("$TARBALL")
  mkdir -p "$OUT_DIR"
  # COPYFILE_DISABLE keeps macOS ._ metadata files out of the tarball
  COPYFILE_DISABLE=1 tar -czf "$OUT_DIR/$TARBALL" -C "$BUILD" claude-never-sleeps
  if [ -e "$REPO_DIR/get.sh" ]; then
    cp "$REPO_DIR/get.sh" "$OUT_DIR/"
    assets+=(get.sh)
  fi
  (cd "$OUT_DIR" && shasum -a 256 "${assets[@]}" >checksums.txt)
}

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/claude-never-sleeps-build.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT
stage_install_files "$BUILD/claude-never-sleeps"
write_release_assets
