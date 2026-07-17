# Phase 0 completion report

**Date:** 2026-07-17

**Local status:** Complete on macOS arm64

**Cross-platform status:** CI matrix defined; remote runners not executed

**Kotlin parity status:** Open-source comparison revisions pinned; feature
comparison intentionally not measured before equivalent features exist

## Outcome

Phase 0 now provides a working VS Code-to-native-FreePascal LSP vertical slice,
an isolated official VS Code 1.128.1 host, correct incremental text handling,
and evidence for the Phase 1 parser direction. It does not yet provide end-user
autocomplete, navigation, diagnostics, or refactoring.

| Area | Delivered |
|---|---|
| Isolated editor | Official signed/notarized VS Code 1.128.1 under ignored `.phase0/`; clean/dev user roots; empty external extension registry; repository-local shared/crash state; repeatable launch and smoke scripts |
| VS Code client | `.pas`, `.pp`, `.inc`, `.lpr` language registration; file/untitled selectors; stdio language-client lifecycle; trust-aware absolute custom server setting; development/packaged platform resolution |
| Pascal server | Byte-safe LSP framing; lifecycle; JSON-RPC errors; cancellation receipt; ping; document open/change/close; protocol-only stdout |
| Text engine | URI-keyed, versioned UTF-8 documents; UTF-16 position mapping; atomic full/ranged change batches; LF/CRLF and astral Unicode; stale/invalid edit rollback |
| Parser spike | Lossless token stream, trivia, byte spans, recovery nodes, deterministic errors, incomplete-code fixtures, and measured `fcl-passrc` comparison |
| Reproducibility | Exact npm lockfile, dependency/license record, benchmark manifest, local validation harness, and Linux/macOS/Windows CI definition |

## Local evidence

The authoritative command is:

```sh
./tools/validate.sh --with-editor
```

It passed all of the following:

- VS Code version `1.128.1`, commit
  `5264f2156cbcd7aea5fd004d29eaa10209155d66`, arm64.
- Download SHA-256
  `6bb7b71393e1ae1f831add4e0e0a3d74675e70092f64d978d3ce37d6594be48a`.
- Deep code-signature verification and Gatekeeper notarization assessment.
- Empty external extension list and empty extension registry (`[]`).
- Clean-host smoke with only default built-in extensions.
- Development Extension Host activation through a non-installed development
  path; FPC XUI client reached `running` and the native server started.
- TypeScript strict compile and 8/8 client path tests.
- Native protocol/dispatcher suite and raw stdout-purity smoke.
- Text engine: 83 assertions.
- Parser/recovery engine: 1,687 assertions over nine fixtures.
- Runtime-checking Pascal protocol build with zero leaked blocks.
- Exact production npm graph audit with zero reported vulnerabilities.
- Short parser sample: independent proof 18.45 MiB/s and `fcl-passrc`
  16.06 MiB/s. The three-trial feasibility medians are 22.48 and
  16.49 MiB/s respectively; these are not parity claims.

The workflow in `.github/workflows/phase0.yml` defines Ubuntu, macOS, and
Windows Pascal jobs plus the TypeScript job. There is no remote workflow result
yet, so Windows/Linux behavior is not claimed as verified.

## Isolation incident

The original requirement that the user's existing VS Code state remain wholly
untouched was breached during setup and cannot be reported as satisfied.

1. At 07:11:27, a raw copied-app `Electron --version` diagnostic was
   interpreted as a GUI launch. It read the normal Code profile, activated
   installed extensions, and wrote normal cache/log/state files.
2. At 07:22:57, a launch with separate `--user-data-dir` and
   `--extensions-dir` exposed VS Code 1.128's additional home-level
   `~/.vscode-shared` store and updated it.
3. Both copied-app process trees were terminated. No user state was deleted or
   restored because no trustworthy pre-run snapshot existed; attempting a
   rollback could have destroyed legitimate concurrent state.
4. Every repository launcher now also requires `--shared-data-dir` below
   `.phase0/`, plus isolated crash storage, disabled telemetry/updates/crash
   reporting, and in-memory secret storage.
5. Repeated clean/dev smokes after the fix wrote the repository-local shared
   DB. The user's `~/.vscode-shared` DB and backup retained their 07:23:00
   modification times, no new normal-Code log directory appeared, and no
   workspace-local VS Code process remained.

See `docs/adr/vscode-isolation.md` for the full decision and containment rule.

## Day-to-day commands

```sh
# Reuse or acquire the pinned official macOS host
./tools/bootstrap-vscode-macos.sh

# Verify signature, version, isolated storage, and external-extension state
./tools/verify-vscode.sh

# Open the pristine host (default built-ins only)
./tools/launch-clean-vscode.sh

# Open the development host with FPC XUI loaded from source, not installed
./server/build.sh
npm --prefix extension run compile
./tools/launch-dev-vscode.sh

# Source checks without launching the editor
./tools/validate.sh

# Full local Phase 0 regression, including isolated GUI smokes
./tools/validate.sh --with-editor
```

## What to expect in Phase 1

Phase 1 changes the vertical slice into a usable syntax-level editor. Expected
deliverables are:

- packaged platform server selection, logs/settings hardening, VSIX assembly;
- TextMate grammar and snippets for immediate visual editing quality;
- complete lexer and directive/preprocessor state;
- immutable green syntax tree and red navigation projections;
- tolerant FreePascal grammar with stable recovery nodes and an explicit full
  AST/CST inspection command;
- incremental relex/reparse with full-parse equivalence tests;
- syntax diagnostics, folding ranges, selection ranges, and document symbols;
- cached line map plus a piece table/rope so edits do not rescan/copy the full
  document;
- performance telemetry in the test harness, with 100k-LOC edit-to-syntax p95
  at or below 150 ms.

Phase 1 is complete only when incomplete-code fixtures never crash, incremental
parse output equals a clean full parse, platform CI is green, and the syntax
latency budget passes. Semantic completion, go-to-definition, references, and
safe refactoring remain later phases because they require the project model,
symbol index, and type system.

## Explicitly deferred

- Actual Windows/Linux runner evidence.
- Full Kotlin/IntelliJ comparative measurements; the matching feature set does
  not exist yet.
- Complete Pascal grammar, directive evaluation, green/red incremental tree,
  project model, semantic engine, autocomplete, navigation, and refactoring.
- Marketplace publication, VSIX signing, or installation into any user profile.
