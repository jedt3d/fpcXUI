#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
build_root=$(mktemp -d "${TMPDIR:-/tmp}/fpcxui-parser.XXXXXX")

fpc -B -Cr -Co -Ci -Ct \
  -Fu"$repo_root/server/src/syntax" \
  -FU"$build_root" \
  -FE"$build_root" \
  "$script_dir/test_parser.pas"

"$build_root/test_parser" "$repo_root/tests/corpus"
echo "build_dir=$build_root"
