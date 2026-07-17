# FPC XUI Phase 0 language server

This directory contains the native Free Pascal JSON-RPC/LSP server skeleton.
It uses only the FPC RTL and FCL (`fpjson`/`jsonparser`) and communicates over
standard input/output. Standard output is reserved exclusively for framed LSP
messages; diagnostics are written to standard error.

## Build

On macOS or Linux with FPC 3.2.2:

```sh
./server/build.sh
```

On Apple Silicon the executable is written to:

```text
server/bin/darwin-arm64/fpcxui-ls
```

Set `FPCXUI_FPC` to select a specific compiler executable. The build script
does not install packages or modify the system toolchain.

## Phase 0 protocol surface

- `initialize`, `initialized`, `shutdown`, `exit`
- `$/cancelRequest`
- `textDocument/didOpen`, `textDocument/didChange`, `textDocument/didClose`
- `fpc/ping`

Document notifications are validated and applied to a URI-keyed store of
versioned UTF-8 documents. Incremental ranges use zero-based LSP UTF-16
positions. A `didChange` batch is applied once and commits atomically only when
its version and every full or ranged edit are valid.
