#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
phase0_root="$workspace_root/.phase0"
version=1.128.1
expected_sha256=6bb7b71393e1ae1f831add4e0e0a3d74675e70092f64d978d3ce37d6594be48a
download="$phase0_root/downloads/VSCode-$version-universal.dmg"
install_root="$phase0_root/vscode/$version"
app="$install_root/Visual Studio Code.app"
url="https://update.code.visualstudio.com/$version/darwin-universal-dmg/stable"

if [ "$(uname -s)" != Darwin ]; then
  echo "This bootstrap script is for macOS only" >&2
  exit 2
fi

mkdir -p "$phase0_root/downloads" "$install_root"

if [ ! -f "$download" ]; then
  curl --fail --location --progress-bar --output "$download" "$url"
fi

actual_sha256=$(shasum -a 256 "$download" | awk '{ print $1 }')
if [ "$actual_sha256" != "$expected_sha256" ]; then
  echo "VS Code DMG SHA-256 mismatch" >&2
  echo "Expected: $expected_sha256" >&2
  echo "Actual:   $actual_sha256" >&2
  exit 1
fi

if [ ! -d "$app" ]; then
  mount_dir=$(mktemp -d "$phase0_root/mount.XXXXXX")
  mounted=false
  cleanup() {
    if [ "$mounted" = true ]; then
      hdiutil detach "$mount_dir" >/dev/null || true
    fi
    rmdir "$mount_dir" 2>/dev/null || true
  }
  trap cleanup EXIT HUP INT TERM

  hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$download" >/dev/null
  mounted=true
  ditto "$mount_dir/Visual Studio Code.app" "$app"
  hdiutil detach "$mount_dir" >/dev/null
  mounted=false
  rmdir "$mount_dir"
  trap - EXIT HUP INT TERM
fi

"$workspace_root/tools/verify-vscode.sh"
