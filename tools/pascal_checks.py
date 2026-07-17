#!/usr/bin/env python3
"""Cross-platform Phase 0 Pascal build, test, and protocol smoke harness."""

from __future__ import annotations

import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
BUILD_ROOT = ROOT / ".phase0" / "build" / "pascal-checks"
FPC = os.environ.get("FPCXUI_FPC", "fpc")
EXTRA_UNIT_PATHS = [
    Path(entry)
    for entry in os.environ.get("FPCXUI_FPC_UNIT_PATHS", "").split(os.pathsep)
    if entry
]


def target_name() -> tuple[str, str]:
    system = platform.system()
    machine = platform.machine().lower()
    os_name = {"Darwin": "darwin", "Linux": "linux", "Windows": "win32"}.get(system)
    arch = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "x64", "amd64": "x64"}.get(machine)
    if os_name is None or arch is None:
        raise RuntimeError(f"unsupported test host: {system} {machine}")
    return os_name, arch


def executable(name: str) -> Path:
    return BUILD_ROOT / (name + (".exe" if os.name == "nt" else ""))


def compile_program(source: Path, name: str, unit_paths: list[Path]) -> Path:
    unit_dir = BUILD_ROOT / "units" / name
    unit_dir.mkdir(parents=True, exist_ok=True)
    output = executable(name)
    command = [
        FPC,
        "-B",
        "-Mobjfpc",
        "-Sh",
        "-O1",
        "-g",
        "-gl",
        *(f"-Fu{path}" for path in EXTRA_UNIT_PATHS),
        *(f"-Fu{path}" for path in unit_paths),
        f"-FU{unit_dir}",
        f"-FE{BUILD_ROOT}",
        f"-o{output.name}",
        str(source),
    ]
    subprocess.run(command, cwd=ROOT, check=True)
    if not output.is_file():
        raise RuntimeError(f"FPC did not create {output}")
    return output


def run_checked(command: list[str]) -> str:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    sys.stdout.write(completed.stdout)
    return completed.stdout


def frame(payload: bytes) -> bytes:
    return b"Content-Length: " + str(len(payload)).encode("ascii") + b"\r\n\r\n" + payload


def protocol_smoke(server: Path) -> None:
    messages = [
        b'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
        b'{"jsonrpc":"2.0","method":"initialized","params":{}}',
        (
            b'{"jsonrpc":"2.0","method":"textDocument/didOpen","params":'
            b'{"textDocument":{"uri":"file:///smoke.pas","languageId":"freepascal",'
            b'"version":1,"text":"begin\\n  WriteLn(\\\"ok\\\");\\nend.\\n"}}}'
        ),
        b'{"jsonrpc":"2.0","id":2,"method":"fpc/ping","params":{}}',
        b'{"jsonrpc":"2.0","id":3,"method":"shutdown"}',
        b'{"jsonrpc":"2.0","method":"exit"}',
    ]
    completed = subprocess.run(
        [str(server)],
        cwd=ROOT,
        input=b"".join(frame(message) for message in messages),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"valid LSP session exited {completed.returncode}: {completed.stderr!r}")
    if completed.stderr:
        raise RuntimeError(f"valid LSP session wrote stderr: {completed.stderr!r}")
    if completed.stdout.count(b"Content-Length:") != 3:
        raise RuntimeError(f"expected three framed responses: {completed.stdout!r}")
    if b'"pong":true' not in completed.stdout or b'"result":null' not in completed.stdout:
        raise RuntimeError(f"missing ping or shutdown result: {completed.stdout!r}")

    malformed = subprocess.run(
        [str(server)],
        cwd=ROOT,
        input=b"Content-Length: nope\r\n\r\n{}",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if malformed.returncode == 0 or malformed.stdout:
        raise RuntimeError("malformed Content-Length was not rejected cleanly")
    if b"Invalid Content-Length header" not in malformed.stderr:
        raise RuntimeError(f"missing malformed-header diagnostic: {malformed.stderr!r}")
    print("PASS: cross-platform raw protocol smoke")


def main() -> int:
    os_name, arch = target_name()
    print(f"target={os_name}-{arch}")
    if shutil.which(FPC) is None:
        raise RuntimeError(f"Free Pascal compiler not found: {FPC}")
    BUILD_ROOT.mkdir(parents=True, exist_ok=True)

    source_units = [ROOT / "server" / "src", ROOT / "server" / "src" / "text"]
    server = compile_program(ROOT / "server" / "fpcxui_ls.lpr", "fpcxui-ls", source_units)
    protocol_test = compile_program(
        ROOT / "tests" / "protocol" / "test_protocol.lpr",
        "test_protocol",
        source_units,
    )
    text_test = compile_program(
        ROOT / "tests" / "text" / "test_text.pas",
        "test_text",
        [ROOT / "server" / "src" / "text"],
    )
    parser_test = compile_program(
        ROOT / "tests" / "parser" / "test_parser.pas",
        "test_parser",
        [ROOT / "server" / "src" / "syntax"],
    )
    parser_benchmark = compile_program(
        ROOT / "tests" / "parser" / "benchmark_parser.pas",
        "benchmark_parser",
        [ROOT / "server" / "src" / "syntax"],
    )

    run_checked([str(protocol_test)])
    run_checked([str(text_test)])
    run_checked([str(parser_test), str(ROOT / "tests" / "corpus")])
    run_checked([str(parser_benchmark), "20", "1000"])
    protocol_smoke(server)
    print("PASS: Phase 0 Pascal checks")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
