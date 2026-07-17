#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/vscode-paths.sh"

reported_version=$(
  "$vscode_cli" \
    --user-data-dir "$user_data_clean" \
    --extensions-dir "$extensions_dir" \
    --shared-data-dir "$shared_data_dir" \
    --disable-extensions \
    --disable-telemetry \
    --disable-updates \
    --disable-crash-reporter \
    --crash-reporter-directory "$crash_reporter_dir" \
    --use-inmemory-secretstorage \
    --version |
    sed -n '1p'
)

if [ "$reported_version" != "$vscode_version" ]; then
  echo "Expected VS Code $vscode_version, got $reported_version" >&2
  exit 1
fi

extension_list=$(
  "$vscode_cli" \
    --user-data-dir "$user_data_clean" \
    --extensions-dir "$extensions_dir" \
    --shared-data-dir "$shared_data_dir" \
    --disable-extensions \
    --disable-telemetry \
    --disable-updates \
    --disable-crash-reporter \
    --crash-reporter-directory "$crash_reporter_dir" \
    --use-inmemory-secretstorage \
    --list-extensions \
    --show-versions
)

if [ -n "$extension_list" ]; then
  echo "The isolated extension directory is not empty:" >&2
  printf '%s\n' "$extension_list" >&2
  exit 1
fi

if find "$extensions_dir" -mindepth 1 ! -name extensions.json -print -quit | grep -q .; then
  echo "Unexpected files exist in $extensions_dir" >&2
  exit 1
fi

if [ -f "$extensions_dir/extensions.json" ]; then
  registry_contents=$(tr -d '[:space:]' <"$extensions_dir/extensions.json")
  if [ "$registry_contents" != '[]' ]; then
    echo "The isolated extension registry is not empty" >&2
    exit 1
  fi
fi

case "$(uname -s)" in
  Darwin)
    codesign --verify --deep --verbose=2 "$vscode_app" >/dev/null
    spctl --assess --type execute --verbose=2 "$vscode_app" >/dev/null
    ;;
esac

echo "PASS: isolated VS Code $reported_version; no external extensions"
