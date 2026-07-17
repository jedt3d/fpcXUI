#!/bin/sh
set -eu

server_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

case "$(uname -s)" in
  Darwin) target_os=darwin ;;
  Linux) target_os=linux ;;
  *)
    echo "Unsupported host for build.sh: $(uname -s)" >&2
    exit 2
    ;;
esac

case "$(uname -m)" in
  arm64|aarch64) target_arch=arm64 ;;
  x86_64|amd64) target_arch=x64 ;;
  *)
    echo "Unsupported architecture for build.sh: $(uname -m)" >&2
    exit 2
    ;;
esac

target="$target_os-$target_arch"
unit_dir="$server_root/build/$target/units"
bin_dir="$server_root/bin/$target"
fpc_bin=${FPCXUI_FPC:-fpc}

mkdir -p "$unit_dir" "$bin_dir"

"$fpc_bin" \
  -B \
  -Mobjfpc \
  -Sh \
  -O1 \
  -g \
  -gl \
  -Fu"$server_root/src" \
  -Fu"$server_root/src/text" \
  -FU"$unit_dir" \
  -FE"$bin_dir" \
  -ofpcxui-ls \
  "$server_root/fpcxui_ls.lpr"

echo "$bin_dir/fpcxui-ls"
