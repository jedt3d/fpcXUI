#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
build_root=$(mktemp -d "${TMPDIR:-/tmp}/fpcxui-parser-bench.XXXXXX")
iterations=${1:-200}
statements=${2:-2000}

fpc -B -O2 \
  -Fu"$repo_root/server/src/syntax" \
  -FU"$build_root" \
  -FE"$build_root" \
  "$script_dir/benchmark_parser.pas"

fpc -B -O2 \
  -FU"$build_root" \
  -FE"$build_root" \
  "$script_dir/probe_fcl_passrc.pas"

"$build_root/benchmark_parser" "$iterations" "$statements"
"$build_root/probe_fcl_passrc" --benchmark "$iterations" "$statements"
echo "build_dir=$build_root"
