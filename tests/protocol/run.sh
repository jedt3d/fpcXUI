#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_root="$workspace_root/tests/protocol"
unit_dir="$test_root/build/units"
bin_dir="$test_root/bin"
fpc_bin=${FPCXUI_FPC:-fpc}

mkdir -p "$unit_dir" "$bin_dir"

"$workspace_root/server/build.sh" >/dev/null

"$fpc_bin" \
  -B \
  -Mobjfpc \
  -Sh \
  -O1 \
  -g \
  -gl \
  -Fu"$workspace_root/server/src" \
  -Fu"$workspace_root/server/src/text" \
  -FU"$unit_dir" \
  -FE"$bin_dir" \
  -otest_protocol \
  "$test_root/test_protocol.lpr"

"$bin_dir/test_protocol"
"$test_root/raw_smoke.sh"
