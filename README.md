# FPC XUI

FPC XUI is an open-source VS Code language-support project for FreePascal. The
repository is at Phase 0: the TypeScript client, native Pascal LSP transport,
versioned text engine, parser feasibility proof, and isolated editor harness are
implemented. End-user language intelligence begins in Phase 1.

## Validate

Prerequisites: FPC 3.2.2, Node.js 22 or newer, npm, and Python 3.

```sh
npm ci --prefix extension
./tools/validate.sh
```

On the prepared macOS workspace, include the isolated VS Code host and
Extension Host smokes:

```sh
./tools/validate.sh --with-editor
```

See:

- `docs/phase0-report.md` for delivered behavior, evidence, known limits, and
  Phase 1 expectations.
- `docs/vscode-freepascal-language-support-plan.md` for the complete roadmap.
- `docs/adr/parser-strategy.md` for parser feasibility evidence.
- `docs/adr/vscode-isolation.md` for the clean-host rules and incident record.
- `docs/dependencies.md` for pinned dependencies and license decisions.
