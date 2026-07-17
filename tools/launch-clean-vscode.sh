#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/vscode-paths.sh"

exec "$vscode_cli" \
  --user-data-dir "$user_data_clean" \
  --extensions-dir "$extensions_dir" \
  --shared-data-dir "$shared_data_dir" \
  --disable-extensions \
  --disable-telemetry \
  --disable-updates \
  --disable-crash-reporter \
  --crash-reporter-directory "$crash_reporter_dir" \
  --use-inmemory-secretstorage \
  --skip-add-to-recently-opened \
  --skip-release-notes \
  --new-window \
  "$workspace_root"
