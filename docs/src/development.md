# Development

Everything here runs through Nix, which is the supported toolchain. The
supported release target is SBCL on `x86_64-linux`; see
[Runtime Support](runtime-support.md) for the capability and portability
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

See [Reporters and CI](reporters-and-ci.md) for the reporter formats and the
coverage gate options.

## Benchmarks

`benchmarks/` holds the micro-benchmark harness for the runner hot paths. See
[Benchmarking](benchmarking.md) for the `benchmark` and `measure` helpers and
the timing statistics they report.

## Structural edits

The devShell provides
[`paredit-cli`](https://github.com/takeokunn/paredit-cli) for structural
S-expression edits. The `paredit-lint` flake check parses every source file, so
an unbalanced form fails `nix flake check` rather than surfacing as a confusing
compile error.

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
