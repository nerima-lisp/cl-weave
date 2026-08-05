# Development

Everything here runs through Nix, which is the supported toolchain. The
supported release target is SBCL on `x86_64-linux`; see
[Runtime Support](../reference/runtime-support.md) for the capability and portability
boundaries.

## Commands

```sh
nix develop          # devShell: SBCL, coreutils, jq, libxml2, paredit-cli
nix flake check      # tests + formatting + docs, the same gate CI uses
nix run .#test       # the self-test suite through run-tests.lisp
nix run . -- --help  # the packaged CLI
nix build .#docs     # this site, with mkdocs --strict
nix fmt              # format Nix sources (treefmt)
```

Running `direnv allow` loads the devShell automatically.

## Running the suite

The full suite is `checks.default`, which runs the packaged CLI against the
`cl-weave/test` system:

```sh
nix run . -- run cl-weave/test
```

For a focused run during development, filter by a path substring:

```sh
nix run . -- run cl-weave/test --filter 'path substring'
```

`run-tests.lisp` at the repository root is the implementation-level entry
point. Every nerima-lisp package exposes the same file, so tooling never has to
know how a given package loads its suite:

```sh
sbcl --script run-tests.lisp
```

It loads `cl-weave/test` and calls `run-all` directly rather than going through
`asdf:test-system`, because the suite itself performs `test-op` on
`cl-weave/test` to exercise the ASDF integration's failure path, and ASDF
rejects that operation appearing twice in one plan.
`asdf:test-system "cl-weave"` remains supported for downstream consumers.

## What `nix flake check` covers

`nix flake check` evaluates each `checks.*` attribute as its own derivation, in
parallel and with build caching. Granularity belongs here rather than in extra
CI jobs.

| Check | What it proves |
|---|---|
| `default` | The whole self-test suite passes through the packaged CLI. |
| `formatting` | Every tracked Nix file is formatted (treefmt + nixfmt). |
| `docs` | This site builds under `mkdocs --strict`, so no link is broken and no page is missing from the nav. |
| `filtered-smoke` | A filtered run fails rather than passes when it matches no tests. |
| `*-artifact`, `cli-json-results` | Each reporter emits an artifact matching its frozen schema. |
| `coverage-artifact` | The coverage run produces a report and clears its gates. |
| `paredit-lint` | Every S-expression source parses structurally. |

Add a check here rather than a job in `ci.yml`. A CI job is justified only for
work the Nix sandbox cannot do: network access, a real PTY, artifact upload, or
a different runner OS.

## Coverage

```sh
nix run . -- run cl-weave/test \
  --coverage \
  --coverage-output cl-weave.coverage \
  --coverage-report-directory cl-weave-coverage-report/ \
  --coverage-system cl-weave
```

See [Reporters and CI](../guide/reporters-and-ci.md) for the reporter formats and the
coverage gate options.

## Benchmarks

`benchmarks/` holds the micro-benchmark harness for the runner hot paths. See
[Benchmarking](../guide/benchmarking.md) for the `benchmark` and `measure` helpers and
the timing statistics they report.

## Structural edits

The devShell provides
[`paredit-cli`](https://github.com/nerima-lisp/paredit-cli) for structural
S-expression edits, and its use is mandatory: any structural change to
`src/*.lisp` or `t/*.lisp` -- renaming a scoped symbol, moving a definition,
extracting or inlining a form, reshaping a binding list, a conditional, or a
call -- goes through `paredit`, never through hand-editing parentheses. The
`paredit-lint` flake check parses every source file, so an unbalanced form
fails `nix flake check` rather than surfacing as a confusing compile error.

`paredit inspect duplicates` and `paredit inspect unused-definitions` are
worth running over `src/*.lisp` (add `t/*.lisp` to the latter to rule out
symbols a test file references but no `src/` file does) before merging a
change that touches more than one file: they catch copy-pasted definitions
and internal helpers nothing calls anymore. Neither tool understands a
symbol's package export status or usage in a downstream consumer, so treat
their output as candidates, not a worklist -- check `src/package.lisp`'s
`:export` list and grep the whole tree before removing or merging anything
they flag.

`paredit-lint`'s platform-guard detection is text-level, not
macroexpansion-aware: it recognizes a feature-dispatch pair such as
`#+sbcl`/`#-sbcl` or `#+sb-thread`/`#-sb-thread` only when both reader
conditionals are literally present at the call site (see the
`#+sb-thread`/`#-sb-thread` split in `run-concurrent-test-cases`,
`src/runner-concurrency.lisp`, and the `#+sbcl` blocks in
`src/platform-sbcl.lisp`). Do not hide one half of such a pair behind a macro
argument or a helper function -- even where a `define-conditional-lock-macro`
style macro could parameterize it -- because the linter would then see only
one branch and cannot verify the other implementation still has a path
through the code.

## Source organization

Three conventions keep individual files from growing into an unreadable mix
of constants, control flow, and callback plumbing as the codebase grows:

- **`*-data.lisp` companion files.** When a file's `defvar`/`defparameter`/
  `defconstant`/plain `defstruct` forms outgrow a handful of lines, move them
  to a same-named `*-data.lisp` file loaded immediately before it in
  `cl-weave.asd` (`runner-control-data.lisp` before `runner-control.lisp`,
  `mocks-data.lisp` before `mocks.lisp`, and so on for the `cli-metadata-*`
  and `cli-options-data`/`reporter-schema-data` pairs). Apply this only where
  it genuinely separates unrelated concerns -- a single small `defstruct`
  tightly coupled to the one function that uses it, or a file with no
  top-level data forms at all, is better left alone.
- **`define-X-macro` consolidation.** When the same defmacro or defun shape
  recurs with only a name and a couple of symbols differing (see
  `define-conditional-lock-macro` in `platform-sbcl.lisp`, or
  `define-runner-option-parser`/`define-passthrough-option-parser` in
  `cli-options.lisp`), extract a macro-generating macro rather than hand-copy
  the pattern again. Verify a macro-generating macro at the value it actually
  produces, not just that it compiles: a `sublis`/nested-backquote mistake
  can macroexpand cleanly to code that never substitutes the caller's
  argument, and that only shows up in a runtime check that exercises the
  generated macro's actual effect.
- **`/k` continuation-passing helpers.** A function named `name/k` takes its
  continuation as an explicit trailing argument or arguments instead of
  returning a value, and calls one of them rather than returning normally --
  for example `call-with-snapshot-comparison/k` in `src/snapshots.lisp`,
  which takes `on-match` and `on-mismatch` and funcalls whichever branch the
  comparison resolves to, or `run-test-attempt/k` in
  `src/runner-attempts.lisp` and `call-with-platform-timeout/k` in
  `src/platform-protocol.lisp`, which take a single `continue`. Prefer the
  paired `on-X`/`on-Y` naming (mirroring `on-match`/`on-mismatch`) when a
  helper has a small fixed number of outcomes each needing different
  handling at the call site, and a single `continue` when there is one
  success path and failure propagates as a condition instead. The `/k`
  suffix is the signal to a reader that the function does not return a
  useful value on its own -- calling it and ignoring the result is a bug,
  not a style choice.

## Contributing

Keep a pull request focused on one problem, add or update tests for behavior
changes, and state the commands you ran and any validation that could not run.

Public API, CLI, reporter or policy changes must update the machine-readable
metadata and the affected pages in the same pull request; the contract tests in
`t/cli-metadata-*.lisp` enforce most of that coupling. Discuss substantial API,
reporter, metadata or runtime changes in an issue before implementing them, and
read the [project scope](project-scope.md) and
[support policy](support-policy.md) first.

Do not report security vulnerabilities in a public issue. Use
[private GitHub security advisories](https://github.com/nerima-lisp/cl-weave/security/advisories/new).

The org-wide contributor guide and code of conduct live in the
[nerima-lisp/.github](https://github.com/nerima-lisp/.github) repository, and the
review and merge expectations for this project are in
[Governance](governance.md#review-and-merge-expectations).
