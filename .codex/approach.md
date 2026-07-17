# approach.md — FPC XUI Phase 0 foundation

> Living supervision document for codex-orc8. Update on design changes,
> routing changes, confirmed or falsified assumptions, failed checks,
> evidence changes, and resume boundaries.

**Status**: complete
**Last updated**: 2026-07-17T07:31:19+07:00
**Mode**: full codex-orc8
**Artifact location reason**: Local supervision belongs under `.codex/`; durable architecture and validation reports belong under `docs/`.

## 1. Task and Stopping Condition

- Task, restated: create a repository-local, isolated official VS Code 1.128.1 environment and implement the approved FPC XUI Phase 0 foundation: client/server LSP handshake, document synchronization and position mapping, parser feasibility evidence, benchmark baseline, dependency/license record, and repeatable validation.
- User-supplied stopping condition, if any: proceed with the approved Phase 0 plan without affecting the user's installed VS Code or loading unrelated extensions.
- Codex stopping condition: the isolated VS Code build is verified; Phase 0 source and tests exist; local authoritative checks pass; failures or unavailable cross-platform evidence are explicit; existing user files remain intact; this artifact records evidence and a clean resume point.

## 2. Workspace State

- CWD: repository root
- Git repo: yes; local `main` is being prepared for its initial publication to `git@github.com:jedt3d/fpcXUI.git`
- Branch: `main`
- Dirty files before work: untracked `.DS_Store`; untracked `docs/vscode-freepascal-language-support-plan.md`
- User changes to preserve: both pre-existing files; especially the approved design document
- Relevant constraints from instructions: no changes to `/Applications`, `~/.vscode`, `~/Library/Application Support/Code`, shell profiles, system PATH, or the user's installed VS Code; no unrelated extensions; use official stable VS Code before Insiders; open-source project dependencies; diagnose and verify before claims
- Isolation incident: at 2026-07-17T07:11:27+07:00 the workspace-local app's raw `Electron --version` entry point launched the GUI without isolation flags. It read the normal Code profile, activated installed extensions, and wrote Code cache/log/state files. The exact workspace-local processes were terminated. No user files were deleted, restored, or otherwise repaired because no trustworthy pre-run snapshot exists. All subsequent commands must use the bundled `code` CLI with explicit workspace-local `--user-data-dir`, `--extensions-dir`, and `--disable-extensions` flags.
- Shared-storage finding: a 07:22:57 dev smoke proved that VS Code 1.128 writes `~/.vscode-shared` even when `--user-data-dir` is explicit. The copied CLI parser exposes the undocumented-in-help `--shared-data-dir` option. All launch/verification scripts now require a workspace-local shared-data root plus isolated crash storage, disabled telemetry/updates, and in-memory secret storage. Repeated clean/dev smokes at 07:25-07:27 used only the workspace-local shared store; the user shared DB mtime remained 07:23:00.
- Generated or opaque files to avoid hand-editing: `.DS_Store`, downloaded VS Code application bundle, npm lockfile, compiler outputs, benchmark result JSON
- Secret-handling notes: public remote publication is authorized for the initial local snapshot; no Marketplace login, settings sync, tokens, signing credentials, or other credentials may be committed

## 3. Decomposition

| ID | Sub-task | Input | Output contract | Verified by | Depends on |
|---|---|---|---|---|---|
| A | Isolated editor | Official VS Code 1.128.1 macOS Universal endpoint | Workspace-local signed app, separate user-data/extension dirs, empty installed-extension list; incident disclosed | version, codesign, spctl, empty-list checks, launch smoke, user-profile incident audit | none |
| B | Pascal LSP server | FPC 3.2.2, FCL JSON | Native stdio server supporting lifecycle, cancellation, document sync, ping, and structured stderr logging | FPC compile, FPCUnit/unit fixtures, raw LSP smoke | A only for UI smoke |
| C | TypeScript client | VS Code stable API, language client | Thin client launching local server; no direct language semantics | TypeScript compile, unit tests, Extension Host smoke | B |
| D | Text mapping | LSP incremental changes and UTF-16 positions | Versioned document store with UTF-8/UTF-16 round-trip tests | deterministic property/fixture tests | B |
| E | Parser spike | Pascal corpus and `fcl-passrc` | Measured capability comparison and parser-strategy ADR; minimal tolerant parser proof | corpus fixtures, throughput benchmark, malformed-input tests | D |
| F | Reproducibility | All above | pinned dependencies, SBOM/license notes, scripts, CI matrix, environment manifest | validation script and clean build | A-E |
| G | Integration | Completed sub-results | one coherent Phase 0 tree and evidence ledger | full validation, VS Code clean/dev smoke, regression scan | A-F |

## 4. Routing and Tool Plan

| Sub-task | Route | Effort | Driving factors | Human checkpoint? |
|---|---|---|---|---|
| A | direct Codex execution | high | user-environment isolation, newly separate shared storage, and signature verification require local context | no; user approved plan |
| B | subagent high effort | high | bounded Pascal module with independent compile/test boundary | no |
| C | subagent medium effort | medium | bounded TypeScript client with compile/test boundary | no |
| D/E | subagent high effort | high | subtle encoding/parser correctness; independently testable | no |
| F/G | direct Codex execution | high | integration, dependency pinning, scripts, evidence, and residual-risk judgment | no |

- Shell commands expected: `curl`, `ditto`, `codesign`, `spctl`, workspace-local VS Code CLI, `npm`, `fpc`, validation scripts
- Test commands expected: npm compile/test, Pascal compile/test executables, raw JSON-RPC smoke, approach lint, workspace validation
- Browser/runtime checks expected: isolated VS Code clean launch and Extension Development Host smoke; no browser needed
- Web research required: already completed for the current official version and documented Microsoft endpoints; primary official sources only for any refresh
- MCP/apps/connectors required: none
- Long-running sessions to track: VS Code smoke process only; terminate after validation

## 5. Design Decisions and Alternatives

| Decision | Why | Rejected alternative | Why rejected |
|---|---|---|---|
| Use official macOS Universal stable binary 1.128.1 | exact approved host, fast and reproducible | build full Code OSS source | high dependency/disk cost adds no Phase 0 language-server value |
| Store editor under `.phase0/` | prevents interaction with installed app/profile | copy into `/Applications` | violates isolation constraint |
| Separate clean and dev user-data roots | clean baseline remains independently provable | one shared profile | development state would contaminate baseline |
| Empty extension dir plus `--disable-extensions` | proves no installed third-party extensions | reuse `~/.vscode/extensions` | would load or expose user extensions |
| Load FPC XUI only through `--extensionDevelopmentPath` | validates the product without installing it | install VSIX | mutates isolated baseline and is unnecessary in Phase 0 |
| Direct FPC implementation with FCL JSON | validates intended production language/runtime | TypeScript server prototype | would postpone Pascal transport risk rather than retire it |
| Keep integration in root context | broad context and evidence must remain coherent | delegate final merge | violates routing rubric for integration work |

Riskiest assumption and cheap probe: `--disable-extensions` still permits the explicit development extension in the Extension Development Host. Probe with a disposable dev user-data root and activation marker; if false, use the official `@vscode/test-electron` harness, which supplies the development path while disabling installed extensions.

Failure pre-mortem: likely failures are VS Code archive/signature mismatch, Node 26 incompatibility with pinned test tooling, LSP framing corruption from stdout logs, UTF-16 errors on surrogate pairs, parser spike silently accepting only declarations, and inability to claim Windows/Linux execution without a remote CI runner.

## 6. Confidence Map

### 6a. High Confidence

- macOS arm64, Git 2.54.0, Node 26.0.0, npm 11.12.1, and FPC 3.2.2 are locally available.
- Official VS Code CLI isolation flags and the 1.128.1 download endpoint were verified from Microsoft documentation.
- The public source remote exists with only an initial MIT license; the user authorized replacing that branch with the reviewed local snapshot while preserving the license.

### 6b. Lower Confidence

- Cross-platform compilation may expose Windows handle/line-ending behavior not reproducible locally.
- FPC 3.2.2 `fcl-passrc` recovery/body coverage must be measured rather than assumed.
- Latest npm packages may not yet advertise Node 26 support even if they run correctly.

### 6c. Guesses

- The official Universal archive will fit comfortably within the available 138 GiB and extract without requiring installation.
- A compact tolerant-parser proof can establish strategy without attempting the full Phase 1 grammar.

## 7. Task-Specific Correctness Checks

- VS Code executable reports exactly 1.128.1 and passes `codesign` plus Gatekeeper assessment.
- Clean and dev CLI queries report no installed extension IDs; extension directory is empty.
- Clean/dev process arguments and main logs resolve user, extension, shared, and crash state below `.phase0/`; no workspace-local VS Code process remains after smoke.
- After the recorded isolation incident, every remaining editor command uses explicit workspace-local data and extension roots; validation must prove those arguments are present in repository launch scripts. The original no-write constraint can no longer be claimed for the execution as a whole.
- LSP handles fragmented headers/bodies, lifecycle ordering, cancellation, malformed messages, and never writes protocol-invalid stdout.
- Incremental edits reject stale versions and round-trip UTF-16 positions including astral Unicode, CRLF, and line ends.
- Full and incremental document results agree for fixtures.
- Parser spike processes complete and incomplete Pascal without crashes and records unsupported constructs honestly.
- TypeScript and Pascal builds are reproducible from clean local output directories.
- Validation includes two edge cases per accepted unit and a final regression scan.
- Cross-platform CI configuration is syntactically valid; actual remote results are not claimed unless obtained.

## 8. Evidence Ledger

| Time | Check | Command/tool | Result | Notes |
|---|---|---|---|---|
| 2026-07-17T07:06:53+07:00 | workspace orientation | `git status`, tool versions, disk check | pass | unborn main; 138 GiB available; prerequisites present |
| 2026-07-17T07:06:53+07:00 | memory lookup | `rg fpcxui MEMORY.md` | no relevant hit | execution is based on current repo and approved plan |
| 2026-07-17T07:13:18+07:00 | public repository safety check | remote tree inspection, ignore review, credential-pattern scan | pass | remote contains only MIT license; local build/runtime artifacts remain ignored; no credential values found in publishable files |
| 2026-07-17T07:11:27+07:00 | editor isolation | raw app executable invoked with `--version` | fail | launched GUI without isolation flags; accessed existing Code profile and activated installed extensions; exact workspace-local process tree terminated |
| 2026-07-17T07:16:00+07:00 | incident containment | process-path audit and recent-file audit | contained | no remaining process from `.phase0/vscode/1.128.1`; user Code writes recorded; no destructive rollback attempted |
| 2026-07-17T07:20:00+07:00 | official editor validation | SHA-256, bundled CLI, `codesign --deep`, `spctl`, extension list | pass | 1.128.1 commit `5264f2156cbcd7aea5fd004d29eaa10209155d66`; notarized; no external extensions |
| 2026-07-17T07:22:57+07:00 | dev Extension Host smoke | explicit user/extension roots | partial | FPC XUI client and server activated, but main log exposed home-level `~/.vscode-shared`; smoke terminated normally |
| 2026-07-17T07:25:15+07:00 | corrected dev Extension Host smoke | added `--shared-data-dir` and containment flags | pass | shared DB created below `.phase0`; FPC XUI client reached running; graceful termination had no deactivation error after client fix |
| 2026-07-17T07:26:00+07:00 | corrected clean host smoke | isolated CLI and empty external store | pass | only default built-in extensions activated; no development extension; process terminated |
| 2026-07-17T07:27:00+07:00 | repeatable clean/dev smoke scripts | `tools/smoke-vscode.sh clean`, `dev` | pass | both ready markers passed; no workspace-local editor processes remained |
| 2026-07-17T07:17:00+07:00 | TypeScript client | npm check, compile, 8 unit tests, production audit | pass | exact lockfile; zero production vulnerabilities |
| 2026-07-17T07:21:00+07:00 | Pascal protocol/text/parser | cross-platform harness | pass | protocol passed; text 83 assertions; parser 1,687 assertions; raw stdout-purity smoke passed |
| 2026-07-17T07:22:00+07:00 | parser feasibility | independent parser and `fcl-passrc` probe | pass | independent proof tolerant/lossless; `fcl-passrc` failed fast on incomplete corpus; 23.43 vs 14.95 MiB/s short local sample |
| 2026-07-17T07:31:19+07:00 | initial public snapshot gate | `./tools/validate.sh`, ignored-index audit, credential-pattern scan | pass | complete local validation passed; generated binaries, caches, credentials, and Phase 0 runtime remain excluded |

## 9. Files Touched

| File | Why | Status |
|---|---|---|
| `.codex/approach.md` | live orchestration/evidence | edited |
| `.DS_Store` | pre-existing opaque user file | unchanged-user-work |
| `docs/vscode-freepascal-language-support-plan.md` | approved architecture | unchanged-user-work |
| `.phase0/**` | isolated downloaded/generated runtime and evidence | in-progress |
| `extension/**` | TypeScript client | in-progress |
| `server/**` | Pascal language server | in-progress |
| `tests/**` | protocol/text/parser fixtures | in-progress |
| `tools/**` | repeatable launch/validation scripts | planned |
| `.github/workflows/**` | cross-platform CI definition | edited; remote execution unavailable |
| `benchmarks/**` | pinned comparison manifest and benchmark protocol | edited |
| `docs/adr/**` | parser and editor-isolation decisions | edited |
| `docs/dependencies.md` | license and dependency decision record | edited |

## 10. Self-Assessed Probability

~70% — calibrated guess, not a guarantee.

Reasoning:

- Evidence pushing confidence up: all local tool prerequisites exist; architecture and isolation plan are approved; boundaries are independently testable.
- Unknowns pushing confidence down: the no-impact isolation constraint was breached once, fresh Pascal protocol implementation, encoding edge cases, Node 26 compatibility, and unavailable remote Windows/Linux execution.
- What would change this estimate: local clean/dev VS Code smoke plus complete test suite raises it; parser or cross-platform compile failures lower it.

## 11. Residual Risks and Human Review

- Actual Windows/Linux CI still needs a configured remote workflow and successful runner results before cross-platform claims are made.
- Kotlin/IntelliJ comparison can be prepared locally but downloading/running another IDE is secondary to the approved pristine VS Code and LSP feasibility gate; any deferral must be explicit.
- The existing VS Code profile was affected by one accidental workspace-local GUI launch. The impact is limited to observed cache/log/state writes, but precise semantic state changes cannot be reconstructed without a before snapshot.

## 12. Resume Point

- Last completed step: completed document-store integration, passed the full local validation, wrote the Phase 0 report, and prepared the initial public snapshot
- Next safe step: publish the validated snapshot, inspect remote CI results, and use the approved roadmap to plan Phase 1
- Known blockers: none for local Phase 0; actual cross-platform CI results remain unavailable
- Commands to rerun: `./tools/validate.sh --with-editor`
- Unverified assumptions: Windows and Linux behavior until the remote CI matrix completes successfully

## 13. Changelog

- 2026-07-17T07:06:53+07:00 — created after workspace orientation
- 2026-07-17T07:07:10+07:00 — recorded decomposition, routing, correctness gates, and the no-remote cross-platform constraint
- 2026-07-17T07:13:18+07:00 — recorded the authorized public remote, publication safety review, and remaining CI evidence boundary
- 2026-07-17T07:20:00+07:00 — recorded the failed initial isolation check, process containment, observed user-profile writes, revised validation rule, and reduced confidence
- 2026-07-17T07:27:00+07:00 — recorded the separate VS Code shared-storage discovery, mandatory shared-data isolation, corrected clean/dev smoke evidence, client deactivation fix, and passing implementation checks
- 2026-07-17T07:31:19+07:00 — recorded the validated public snapshot and replacement `jedt3d/fpcXUI` remote
