#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$workspace_root"

if [ "${1:-}" = "--with-editor" ]; then
  ./tools/verify-vscode.sh
  ./tools/smoke-vscode.sh clean
  ./tools/smoke-vscode.sh dev
fi

npm --prefix extension run check
npm --prefix extension test
python3 tools/pascal_checks.py
./tests/parser/benchmark.sh 20 1000
git diff --check
git diff --cached --check

echo "PASS: Phase 0 validation"
