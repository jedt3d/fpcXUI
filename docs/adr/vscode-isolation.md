# ADR 0001: Isolate the Phase 0 VS Code host

**Status:** Accepted, with execution incidents recorded below
**Date:** 2026-07-17

## Decision

Use the official VS Code 1.128.1 macOS Universal application from Microsoft's
stable update service. Keep the download, application, profiles, logs, caches,
and extension directory below the repository's ignored `.phase0/` directory.
Do not copy the app into `/Applications` and do not install the FPC XUI
extension into any profile.

Every editor command must go through the bundled `code` CLI and include all of:

```text
--user-data-dir <repository>/.phase0/user-data-{clean|dev}
--extensions-dir <repository>/.phase0/extensions
--shared-data-dir <repository>/.phase0/shared-data
--disable-extensions
```

VS Code 1.128 introduces a home-level shared-data directory independent of
`--user-data-dir`. Its bundled CLI parser supports `--shared-data-dir`, although
the option is not printed in `code --help`; omitting it is therefore not an
isolated launch. Launchers also disable telemetry, updates, crash reporting,
and persistent secret storage.

`config/phase0-settings.json` is copied into each new isolated profile and
disables extension updates/checks, experiments, telemetry, and built-in AI
features. Existing isolated settings are not overwritten.

The clean launcher opens only the default VS Code feature set. The development
launcher additionally passes `--extensionDevelopmentPath` for this repository's
FPC XUI extension; it still does not install the extension.

## Verification

- Download SHA-256:
  `6bb7b71393e1ae1f831add4e0e0a3d74675e70092f64d978d3ce37d6594be48a`
- Bundled CLI reports `1.128.1`, commit
  `5264f2156cbcd7aea5fd004d29eaa10209155d66`, `arm64`.
- Gatekeeper reports `accepted`, source `Notarized Developer ID`.
- `codesign --verify --deep` reports the copied application valid on disk and
  satisfying its designated requirement.
- The explicit isolated CLI reports no external extensions. The isolated
  extension directory contains only VS Code's empty `extensions.json` registry.

Strict `codesign --strict` is not used as the acceptance gate because macOS
File Provider immediately attaches empty `com.apple.FinderInfo` metadata to the
copy under `Documents`. Non-strict deep verification validates the signed code,
and Gatekeeper independently accepts the application.

## Incident and containment

At 2026-07-17 07:11:27 +07:00, a diagnostic invoked the copied application's
raw `Electron` executable with `--version` but without isolation flags. Electron
interpreted that as a GUI launch, read the user's normal Code profile, activated
installed extensions, and wrote normal cache, log, and state files under the
user's Code support directories. The exact process tree whose executable path
was below this repository's `.phase0/vscode/1.128.1` directory was terminated.

No user file was deleted or restored: no reliable pre-run snapshot existed, so
attempting a rollback would risk destroying legitimate concurrent editor state.
This means the original zero-impact constraint was breached once and cannot be
claimed for this execution. The scripts above make the required isolation flags
mandatory for every repeatable subsequent launch.

During the first explicitly separated development-profile smoke at 07:22:57,
the log revealed that VS Code's newer shared storage still resolved to
`~/.vscode-shared` because `--user-data-dir` does not cover it. That smoke
exited normally after about two seconds. This discovery produced the mandatory
`--shared-data-dir` rule above; all later smoke evidence must show the
repository-local shared-storage path.
