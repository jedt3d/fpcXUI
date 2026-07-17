# Phase 0 dependency and license record

**Recorded:** 2026-07-17
**Policy:** production and test dependencies must be open source and pinned.

## Runtime and build dependencies

| Component | Pinned version | Use | License | Distribution decision |
|---|---:|---|---|---|
| FPC | 3.2.2 | Compiler and build tool | GPL-2.0-or-later | Build tool; not bundled |
| FPC RTL and FCL JSON units | 3.2.2 | Native server runtime and JSON implementation | Modified LGPL with FPC static-linking exception | May be linked into the server; retain the FPC license/exception notice in release notices |
| `vscode-languageclient` | 9.0.1 | VS Code LSP client | MIT | Ship in compiled extension bundle |
| `vscode-languageserver-protocol` | 3.17.5 | LSP types/protocol dependency | MIT | Transitive runtime dependency |
| `vscode-jsonrpc` | 8.2.0 | JSON-RPC transport dependency | MIT | Transitive runtime dependency |
| `vscode-languageserver-types` | 3.17.5 | LSP value types | MIT | Transitive runtime dependency |
| `minimatch` | 5.1.9 | Client transitive dependency | ISC | Transitive runtime dependency |
| `brace-expansion` | 2.1.2 | Client transitive dependency | MIT | Transitive runtime dependency |
| `balanced-match` | 1.0.2 | Client transitive dependency | MIT | Transitive runtime dependency |
| `semver` | 7.8.5 | Client transitive dependency | ISC | Transitive runtime dependency |

The exact dependency graph and integrity hashes are locked in
`extension/package-lock.json`. `npm audit --omit=dev` reported zero known
vulnerabilities at record time.

## Development-only dependencies

| Component | Pinned version | License |
|---|---:|---|
| TypeScript | 5.9.3 | Apache-2.0 |
| `@types/node` | 22.20.1 | MIT |
| `undici-types` | 6.21.0 | MIT |
| `@types/vscode` | 1.125.0 | MIT |

The latest published `@types/vscode` package available during Phase 0 is
1.125.0; no 1.128.0 package exists. The extension targets VS Code 1.128 and
uses no API introduced after 1.125, so this older type floor is deliberate.

## Hosts and comparison tools

| Component | Pin | License/use boundary |
|---|---|---|
| Official VS Code | 1.128.1, commit `5264f2156cbcd7aea5fd004d29eaa10209155d66` | Official Microsoft binary used only as the ignored local test host; it is not redistributed by this project |
| IntelliJ IDEA Community source | 2025.3, tag/build `idea/253.28294.334` | Apache-2.0 `intellij-community` source archive, benchmark-only source build |
| Kotlin IDE plugin | compatible build identity `253.28294.325-IJ` | Build the Community Kotlin plugin from open source; the Marketplace identity is retained only as the compatibility pin and its binary is not accepted as a project dependency |
| IntelliJ IDE Starter | Same `253.28294.334` platform branch | Apache-2.0, proposed benchmark automation only |

The JetBrains comparison source revisions are pinned but are not project
dependencies and are not shipped. Any later benchmark binary must be produced
from the recorded open-source revisions with its build manifest retained. The
Kotlin comparative suite remains separate from the FPC XUI build and from the
clean VS Code extension directory.

## Release requirement

Before any VSIX is distributed, generate a CycloneDX SBOM from the lockfile,
include the complete MIT/ISC/Apache notices for bundled JavaScript packages,
include the FPC RTL/FCL modified-LGPL exception notice for each native server,
and verify the packaged dependency graph again. Phase 0 records the decisions;
it does not publish a binary release.
