#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

case "$(uname -s)" in
  Darwin) target_os=darwin ;;
  Linux) target_os=linux ;;
  *) echo "Unsupported smoke-test host" >&2; exit 2 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) target_arch=arm64 ;;
  x86_64|amd64) target_arch=x64 ;;
  *) echo "Unsupported smoke-test architecture" >&2; exit 2 ;;
esac

server="$workspace_root/server/bin/$target_os-$target_arch/fpcxui-ls"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/fpcxui-protocol.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

emit_frame() {
  payload=$1
  byte_count=$(printf '%s' "$payload" | wc -c | tr -d ' ')
  printf 'Content-Length: %s\r\n\r\n%s' "$byte_count" "$payload"
}

emit_valid_session() {
  emit_frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
  emit_frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'
  emit_frame '{"jsonrpc":"2.0","id":2,"method":"fpc/ping","params":{}}'
  emit_frame '{"jsonrpc":"2.0","id":3,"method":"shutdown"}'
  emit_frame '{"jsonrpc":"2.0","method":"exit"}'
}

emit_valid_session | "$server" >"$scratch/stdout" 2>"$scratch/stderr"

response_count=$(LC_ALL=C grep -o 'Content-Length:' "$scratch/stdout" | wc -l | tr -d ' ')
test "$response_count" = 3
LC_ALL=C grep -q '"pong":true' "$scratch/stdout"
LC_ALL=C grep -q '"result":null' "$scratch/stdout"
test ! -s "$scratch/stderr"

if printf 'Content-Length: nope\r\n\r\n{}' | "$server" \
    >"$scratch/bad-stdout" 2>"$scratch/bad-stderr"; then
  echo 'Malformed Content-Length unexpectedly succeeded' >&2
  exit 1
fi
test ! -s "$scratch/bad-stdout"
LC_ALL=C grep -q 'fatal: Invalid Content-Length header' "$scratch/bad-stderr"

echo 'PASS: raw stdio lifecycle and stdout-purity smoke test'
