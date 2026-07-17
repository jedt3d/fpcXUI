# ADR: Phase 0 parser strategy

- Status: accepted for Phase 0
- Date: 2026-07-17
- Scope: interactive syntax foundation only

## Decision

Build the interactive FreePascal syntax engine as an independent, lossless,
error-tolerant parser. Keep FPC 3.2.2 `fcl-passrc` as a measured comparison
and possible source of grammar knowledge, but do not use it as the live editor
parser.

The Phase 0 proof in `server/src/syntax/fpcx_syntax.pas` is not the Phase 1
grammar. It establishes these contracts:

- every input byte belongs to exactly one token, including whitespace,
  line endings, comments, directives-as-comments, and malformed lexemes;
- token and flat syntax-node spans use zero-based, half-open UTF-8 byte ranges;
- incomplete strings/comments and unmatched `begin`/`end` return stable error
  codes and recovery nodes instead of throwing;
- a likely missing statement semicolon inserts a zero-width missing-token node
  and continues parsing later statements;
- parsing the same bytes produces the same tokens, diagnostics, and nodes.

The separate text proof in `server/src/text/fpcx_text.pas` converts between
those UTF-8 byte spans and LSP UTF-16 positions. It explicitly rejects byte
positions inside a UTF-8 scalar, LSP positions inside an astral surrogate
pair, and byte positions between CR and LF.

## Why

An editor parser must keep working while the document is temporarily invalid.
It must also retain comments and exact spans for diagnostics, selection,
formatting, and future refactoring. A declaration-oriented parser that stops
at the first error cannot satisfy those interactive requirements without a
second source model and a recovery layer. The local probe confirms that this
is an observed limitation in the installed `fcl-passrc`, not an assumption.

## Measured evidence

### Environment

- macOS 26.5.2 (25F84), arm64
- Free Pascal 3.2.2
- compiler optimization for benchmarks: `-O2`
- measurements are local wall-clock samples from `GetTickCount64`; they are
  feasibility evidence, not Kotlin/IntelliJ parity results

### Correctness and recovery

Commands:

```sh
fpc -B -Fu./server/src/text \
  -FU/private/tmp/fpcxui-text-build \
  -FE/private/tmp/fpcxui-bin tests/text/test_text.pas
/private/tmp/fpcxui-bin/test_text

fpc -B -Fu./server/src/syntax \
  -FU/private/tmp/fpcxui-parser-build \
  -FE/private/tmp/fpcxui-bin tests/parser/test_parser.pas
/private/tmp/fpcxui-bin/test_parser tests/corpus
```

Observed result:

```text
PASS test_text assertions=83
PASS test_parser assertions=1687
```

The independent proof returned a result and losslessly reconstructed all nine
corpus inputs. The corpus covers LF/CRLF tokenization, directives, a generic,
a type helper, missing semicolon, unmatched and unexpected `end`, incomplete
expression, unterminated string, and unterminated comment.

The installed `fcl-passrc` probe was compiled and run with:

```sh
fpc -B -O2 \
  -FU/private/tmp/fpcxui-parser-build \
  -FE/private/tmp/fpcxui-bin tests/parser/probe_fcl_passrc.pas

/private/tmp/fpcxui-bin/probe_fcl_passrc \
  tests/corpus/valid_basic.pas \
  tests/corpus/valid_features.pas \
  tests/corpus/missing_semicolon.pas \
  tests/corpus/unmatched_begin.pas \
  tests/corpus/unexpected_end.pas \
  tests/corpus/unterminated_string.pas \
  tests/corpus/unterminated_comment.pas \
  tests/corpus/incomplete_expression.pas \
  tests/corpus/directives_and_include.inc
```

Observed outcomes:

| Input | `fcl-passrc` 3.2.2 outcome |
|---|---|
| `valid_basic.pas` | parsed |
| `valid_features.pas` | stopped at `type helper for Integer` |
| `missing_semicolon.pas` | stopped at the second `Value` |
| `unmatched_begin.pas` | stopped at EOF expecting `end` |
| `unexpected_end.pas` | stopped at the extra `end` |
| `unterminated_string.pas` | stopped at the open string |
| `unterminated_comment.pas` | stopped at EOF expecting `end` |
| `incomplete_expression.pas` | stopped at `end` expecting an identifier |
| standalone include fragment | stopped at its first statement |

This probe uses `TPasSrcAnalysis.GetAllIdentifiers` to force parsing and catches
the public exception. It demonstrates fail-fast behavior; it does not claim
that every `fcl-passrc` API or mode has identical coverage.

### Throughput spike

Both benchmark programs generate the same 91,929-byte program containing
2,000 assignment statements and parse it 200 times per trial. Commands:

```sh
fpc -B -O2 -Fu./server/src/syntax \
  -FU/private/tmp/fpcxui-parser-build \
  -FE/private/tmp/fpcxui-bin tests/parser/benchmark_parser.pas
/private/tmp/fpcxui-bin/benchmark_parser 200 2000

/private/tmp/fpcxui-bin/probe_fcl_passrc --benchmark 200 2000
```

| Engine | Trial 1 | Trial 2 | Trial 3 | Median |
|---|---:|---:|---:|---:|
| independent proof | 21.59 MiB/s | 22.48 MiB/s | 22.71 MiB/s | 22.48 MiB/s |
| `fcl-passrc` 3.2.2 | 16.59 MiB/s | 16.49 MiB/s | 16.19 MiB/s | 16.49 MiB/s |

This is not an equal-feature performance comparison. The independent proof
creates tokens, recovery diagnostics, and a small flat node list in memory.
The `fcl-passrc` probe reopens a temporary file and creates its richer tree on
every iteration. The result shows that the independent direction is not
obviously too slow at Phase 0 scale; it does not establish a release budget.

## Rejected alternatives

### Use `fcl-passrc` directly for interactive parsing

Rejected for the editor path because the measured API aborts on the first
malformed construct, does not provide the required lossless token model, and
rejected one representative modern construct accepted by the intended FPC
language surface. It remains useful as open-source reference material and a
comparison target.

### Use the FPC compiler parser in-process

Rejected by the approved architecture. Compiler internals have global state,
are not a stable library API, and do not provide the lossless incremental
editor tree required here. FPC remains a separate compiler oracle later.

### Treat the Phase 0 proof as the production grammar

Rejected. Its line-break semicolon recovery is deliberately heuristic and its
block model recognizes only `begin`/`end`. Expanding this file ad hoc would
create an unmaintainable parser.

## Known limitations

- No full Pascal grammar, precedence parser, declaration tree, or semantic AST.
- No conditional-compilation state; compiler directives are retained as
  comment trivia but are not evaluated.
- No incremental lexing, subtree reuse, green/red tree, or stable node IDs.
- Missing-semicolon recovery uses a conservative line-break heuristic and can
  miss valid recovery opportunities or flag unusual multiline formatting.
- Non-ASCII identifier bytes are retained but Unicode identifier validity is
  not classified by this proof.
- The text store rescans lines and copies the string for each edit. A line map
  and piece table/rope are Phase 1 performance work.
- Tests and measurements were executed only on local macOS arm64. Windows and
  Linux results require the repository CI matrix.
- The benchmark excludes peak RSS, cancellation, incremental-edit latency,
  cold cache, and the Kotlin/IntelliJ comparison required by later milestones.

## Phase 1 consequences

1. Preserve the byte-span, trivia, deterministic-error, and no-throw corpus
   contracts as regression tests.
2. Replace the flat block proof with a table-driven or recursive-descent
   FreePascal grammar that produces immutable green nodes and projected red
   nodes.
3. Add directive state and inactive-branch representation without deleting
   source tokens.
4. Add bounded recovery sets and missing/skipped nodes at grammar boundaries.
5. Add incremental relex/reparse and assert that incremental output equals a
   clean full parse.
6. Upgrade the text store to cached line starts and an incremental text
   structure before applying the 100k-line latency gate.

## Revisit criteria

Revisit this decision only if a measured open-source parser demonstrates all
of the following on the same corpus: lossless trivia and spans, recovery that
continues after multiple errors, incomplete-code stability, modern FPC syntax,
incremental reparsing, and licensing compatible with distribution. Parse
success on complete files alone is insufficient.
