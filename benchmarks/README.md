# Phase 0 benchmark baseline

Phase 0 establishes reproducible engine microbenchmarks and pins the later
Kotlin/IntelliJ comparison. It does not claim feature parity: autocomplete,
navigation, diagnostics, and refactoring do not exist yet, so an end-to-end
comparison of those operations would be meaningless.

The authoritative pins and absolute latency budgets are in
`baseline-manifest.json`. Parser and text-engine benchmarks write raw results
below ignored `.phase0/artifacts/`; CI should retain those files as artifacts.

Comparative execution starts once the corresponding FPC XUI feature is usable:

1. Generate structurally matched Pascal and Kotlin workspaces.
2. Start the isolated VS Code host and pinned IntelliJ Community build with no
   non-default extensions.
3. Run identical edit and query scripts after declared warmups.
4. Record at least 30 cold and 100 warm samples with monotonic timestamps.
5. Report median, p95, p99, bootstrap interval, CPU, peak/steady RSS, and cache
   size. Never blend real-corpus and synthetic-project results.
6. Fail a feature gate if its FPC XUI p95 exceeds either the pinned Kotlin p95
   or the absolute budget, whichever is stricter.
