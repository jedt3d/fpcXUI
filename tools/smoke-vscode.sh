#!/bin/sh
set -eu

mode=${1:-dev}
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/vscode-paths.sh"

case "$mode" in
  clean)
    smoke_user_data=$user_data_clean
    development_args=
    ;;
  dev)
    smoke_user_data=$user_data_dev
    development_args="--extensionDevelopmentPath=$workspace_root/extension"
    ;;
  *)
    echo "Usage: $0 [clean|dev]" >&2
    exit 2
    ;;
esac

main_pid=
cleanup() {
  if [ -n "$main_pid" ] && kill -0 "$main_pid" 2>/dev/null; then
    kill -TERM "$main_pid"
    wait_count=0
    while kill -0 "$main_pid" 2>/dev/null && [ "$wait_count" -lt 10 ]; do
      sleep 1
      wait_count=$((wait_count + 1))
    done
  fi
}
trap cleanup EXIT HUP INT TERM

"$vscode_cli" \
  --user-data-dir "$smoke_user_data" \
  --extensions-dir "$extensions_dir" \
  --shared-data-dir "$shared_data_dir" \
  --disable-extensions \
  --disable-telemetry \
  --disable-updates \
  --disable-crash-reporter \
  --crash-reporter-directory "$crash_reporter_dir" \
  --use-inmemory-secretstorage \
  ${development_args:+"$development_args"} \
  --skip-add-to-recently-opened \
  --skip-release-notes \
  --new-window \
  "$workspace_root/tests/corpus/valid_basic.pas"

wait_count=0
while [ "$wait_count" -lt 20 ]; do
  main_pid=$(
    ps -axo pid=,command= |
      awk -v app="$vscode_app/Contents/MacOS/Code" \
          -v data="--user-data-dir $smoke_user_data" \
          'index($0, app) && index($0, data) { print $1; exit }'
  )
  latest_log=$(find "$smoke_user_data/logs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)
  if [ -n "$main_pid" ] && [ -n "$latest_log" ] && [ -f "$latest_log/main.log" ]; then
    if grep -Fq "$shared_data_dir/sharedStorage/state.vscdb" "$latest_log/main.log"; then
      if [ "$mode" = clean ]; then
        if [ -f "$latest_log/window1/exthost/exthost.log" ]; then
          if grep -Fq 'fpc-xui' "$latest_log/window1/exthost/exthost.log"; then
            echo "Clean host unexpectedly loaded the development extension" >&2
            exit 1
          fi
          echo "PASS: clean VS Code host used isolated storage and default extensions only"
          exit 0
        fi
      else
        fpc_log=$(find "$latest_log" -type f -name '*FPC XUI.log' -print -quit)
        if [ -n "$fpc_log" ] && grep -Fq 'FPC XUI language client started.' "$fpc_log"; then
          echo "PASS: development Extension Host activated FPC XUI and its server"
          exit 0
        fi
      fi
    fi
  fi
  sleep 1
  wait_count=$((wait_count + 1))
done

echo "VS Code $mode smoke did not reach its ready marker" >&2
exit 1
