#!/bin/sh

# Shared path resolution and profile preparation for the isolated Phase 0 editor.

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
phase0_root="$workspace_root/.phase0"
vscode_version=1.128.1
user_data_clean="$phase0_root/user-data-clean"
user_data_dev="$phase0_root/user-data-dev"
extensions_dir="$phase0_root/extensions"
shared_data_dir="$phase0_root/shared-data"
crash_reporter_dir="$phase0_root/crash-reporter"

case "$(uname -s)" in
  Darwin)
    vscode_app="$phase0_root/vscode/$vscode_version/Visual Studio Code.app"
    vscode_cli="$vscode_app/Contents/Resources/app/bin/code"
    ;;
  Linux)
    vscode_app="$phase0_root/vscode/$vscode_version/VSCode-linux"
    vscode_cli="$vscode_app/bin/code"
    ;;
  *)
    echo "Unsupported host for the Phase 0 shell launchers: $(uname -s)" >&2
    return 2 2>/dev/null || exit 2
    ;;
esac

if [ ! -x "$vscode_cli" ]; then
  echo "Isolated VS Code CLI not found: $vscode_cli" >&2
  return 1 2>/dev/null || exit 1
fi

mkdir -p \
  "$user_data_clean" \
  "$user_data_dev" \
  "$extensions_dir" \
  "$shared_data_dir" \
  "$crash_reporter_dir"

for profile_root in "$user_data_clean" "$user_data_dev"; do
  mkdir -p "$profile_root/User"
  if [ ! -f "$profile_root/User/settings.json" ]; then
    cp "$workspace_root/config/phase0-settings.json" \
      "$profile_root/User/settings.json"
  fi
done
