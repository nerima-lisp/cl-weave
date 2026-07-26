# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and as of `1.0.0` this project adheres to
[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

<!--
Heading format is fixed across the org:

    ## [X.Y.Z] - YYYY-MM-DD

The version is bracketed, the separator is an ASCII hyphen (not an em dash),
and the date is ISO 8601. release.yml extracts the section matching the pushed
tag as the GitHub Release body, so a heading that deviates makes the release
fail. Keep `## [Unreleased]` at the top at all times.

Use only these subsection names, and omit the ones that are empty:
Added / Changed / Deprecated / Removed / Fixed / Security

Sections for 0.1.0 through 1.0.0 were reconstructed from the commit history of
each tag range. There is no 0.3.0 section because no v0.3.0 tag was ever cut.
-->

## [Unreleased]

### Changed

- Adopted the nerima-lisp package standard: the test system is now
  `cl-weave/test` with its sources under `t/`, the composite CI action is
  `.github/actions/nix-setup`, and `run-tests.lisp` at the repository root is
  the Lisp-level test entry point.
- The `nix flake check` suite exposes `checks.default`, `checks.formatting`
  (treefmt) and `checks.docs`. `nix fmt` is driven by treefmt.
- The `ci.yml` job is named `check`, and the advertised
  `continuousIntegration.jobName` metadata follows it.
- nixpkgs now tracks `nixos-unstable`.
- Adopted the nerima-lisp coding standard. Test files are named after the
  source file they cover (`t/journal-test.lisp` for `src/journal.lisp`, and
  `<source>-<aspect>-test.lisp` where several files cover one source); shared
  fixtures and assertion helpers carry the `helpers-` prefix. Every source
  line now fits in 100 columns, no source file exceeds 500 lines, and each of
  the three packages documents what it owns.
- `src/model.lisp` was split into `model.lisp` (records and conditions),
  `model-registry.lisp` (the global suite tree) and `model-registration.lisp`
  (registration argument handling); the shrink-candidate equality classifier
  moved from `src/property-generators.lisp` to
  `src/property-generators-equality.lisp`. No behaviour changed.
- `flake.nix` declares only the two verified systems, `x86_64-linux` and
  `aarch64-darwin` (ADR-0078).

### Added

- `defmatcher` and `expect-extend` accept a leading `(:description "a" "b")`
  form in place of a description string, joining the parts at macroexpansion
  time. Common Lisp has no string continuation, so this is the only way to
  write a description longer than one line without changing its value.

## [1.0.1] - 2026-07-26

### Changed

- Snapshot assertions reuse the loaded snapshot document within a test run and
  write a changed document once at run completion, reducing repeated snapshot
  file reads while preserving matching and update behavior.
- Release publishing now requires a stable SemVer tag whose ASDF version
  matches and whose commit is reachable from the repository default branch.

## [1.0.0] - 2026-07-25

### Changed

- Declared the project stable: adopted Semantic Versioning 2.0.0 and moved the
  lifecycle and release-stage metadata from `pre-1.0` to `stable`, with paired
  contract tests and rewritten versioning, maintenance and release docs.
- Canonicalized the moved repository references from `takeokunn/cl-weave` to
  `nerima-lisp/cl-weave` across docs, metadata and packaging. The old
  `takeokunn.github.io/cl-weave` Pages URL 404s after the org move, so the
  badges and links now point at the live `nerima-lisp.github.io/cl-weave`
  site.
- `--seed` advertises its machine-readable value kind as `:positive-integer`
  rather than `:integer`, which is what its parser has always enforced.
- Bumped the pinned GitHub Actions: `actions/checkout` 4.3.1 to 7.0.1,
  `actions/upload-artifact` 4.6.2 to 7.0.1, `actions/configure-pages` 5.0.0 to
  6.0.0, `actions/upload-pages-artifact` 4.0.0 to 5.0.0, and
  `actions/deploy-pages` 4.0.5 to 5.0.0.

### Fixed

- Concurrent workers now run with the same condition-propagation semantics as
  sequential execution. `*runner-propagate-conditions*` is bound to `nil`
  during collection but was missing from the captured dynamic environment, so
  worker threads (which start with a fresh dynamic environment) reverted to the
  global default of `t`.
- A timeout that fires inside a `before-each` or `after-each` hook is reported
  as a test timeout instead of a spurious hook failure carrying a leaked
  internal condition. The hook collector caught every `serious-condition`,
  including SBCL's `sb-ext:timeout` interrupt.
- `--flag=VALUE` accepts a value that begins with dashes again, for example
  `--filter=--foo`. The separated form still rejects a following option token.
- `doctor` returns a failing exit status when a health check fails; it
  previously always exited 0, so CI could not gate on `cl-weave doctor SYSTEM`.
- Ordered comparison matchers (`:to-be-greater-than`, `:to-be-less-than` and
  friends, and `:to-be-close-to`) treat NaN as a clean non-match. A NaN is
  `realp`, so it reached the ordered predicates where SBCL's default `:invalid`
  floating-point trap turned a should-fail assertion into an errored test.
- Integer shrinking moves toward the in-range value closest to zero. For a
  negative range the raw `min` bound is the most extreme value, so a greedy
  shrink could accept a larger magnitude than the input it started from.
  Sequence generators now also reject a negative `:min-length` instead of
  silently clamping it.
- The JSON and JSONL reporters serialize a list of plists as an array of
  objects instead of collapsing it into a single object with duplicate keys.
  `json-alist-p` treated the default smart-assertion operand report as an
  alist, dropping data on the frozen artifact contract. The S-expression
  reporter also binds `*print-circle*` so a circular journaled value cannot
  hang it.

## [0.11.0] - 2026-07-25

### Added

- Time-travel debugging. An opt-in execution journal records each attempt's
  assertion, mock, hook, note and shrink timeline with zero overhead when
  disabled; the JSON and S-expression reporters emit a `timeline` field.
- Offline journal tooling: `explain-journal`, `journal-diff`,
  `explain-journal-diff`, `journal-where` logic queries, and a
  serialize/deserialize round trip between `journal-frame` and a plist.
- CLOS-extensible frame kinds through `journal-frame-line-for-kind`, plus a
  public `record-journal-frame` so custom kinds do not require patching
  cl-weave.
- Interactive breakpoints through `*journal-breakpoint*`, which signals at a
  frame index or predicate and falls through to the debugger with the live
  dynamic extent intact.
- Deterministic replay. `*test-random-seed*` seeds the random state per test
  path so runs reproduce regardless of ordering or sharding, with single-test
  `replay-test` and a shrink-step timeline for property tests.
- Soft assertions: `with-soft-assertions` aggregates failures through a
  condition sink instead of aborting on the first one.
- `--journal` and `--random-seed` on `run` and `watch`, advertised through the
  framework metadata so usage and contract tests follow automatically.
- `release.yml`: a `v*.*.*` tag push verifies the tag against `cl-weave.asd`
  `:version`, builds the check artifacts, and publishes a GitHub Release.
- `dependabot.yml` covering both the workflows and the composite action, so the
  pinned action SHAs and their version comments stay current.

### Changed

- Documentation migrated from mdBook to MkDocs Material. `book.toml` and
  `SUMMARY.md` are replaced by `docs/mkdocs.yml`, with theme assets and
  admonition-based formatting across the guide pages.
- Nix installation and Cachix pull/push gating extracted into a reusable
  composite action that the CI and docs workflows both delegate to, so the
  token logic has one source of truth. The push token stays gated on
  non-`pull_request` at the workflow boundary, because a local `./` action is
  resolved from the pull request head.
- `ci.yml` is matrix-ready: a single-entry `strategy.matrix` templates the
  system, so adding a platform is a one-line change.
- Reduced consing and stack pressure on the runner hot paths. `results-status`
  walks the run-result tree iteratively with explicit work and cycle detection
  rather than normalizing and then calling `every`, so a status check no longer
  allocates a full normalized copy. Comparable non-consing and iterative
  rewrites landed across `model`, `runner-attempts`, `runner-selection`,
  `runner-collection`, `runner-planning`, `runner-concurrency` and
  `matcher-runtime`.

## [0.10.0] - 2026-07-24

### Added

- `benchmarks/`, a performance harness for the runner's collection, selection
  and hook machinery.

### Changed

- Fast paths and reduced allocation in the machinery that runs for every test.
  `runner-collection` gained a strict-empty-batch fast path so a suite with no
  hooks, filters, focus/skip/todo markers or special execution modes emits its
  events directly. `runner-selection` hashes each child's kind and name
  incrementally onto a precomputed suite prefix hash instead of allocating a
  label string per child. `runner-hooks` computes suite lineage once per test.
- Split the largest source and test files into single-responsibility modules
  without changing behavior: `property-generators` into `-primitives` and
  `-shrinking`, `watch` into `watch-discovery`, `watch-scope` and
  `watch-suite-diff`, `runner-coverage` out of `runner-api`, and the
  monolithic `asdf-integration`, `expect-core` and `mocking` suites into
  focused files.
- The S-expression reporter emits its single form on one line, because it binds
  `*print-pretty*` to `nil`. The AI contract now states this explicitly.

### Fixed

- Cleanup hooks always run. `after-each` runs under `unwind-protect` and suite
  `after-all` hooks run through an idempotent `run-after-hooks`, and the
  collectors catch `serious-condition`, so an SBCL platform timeout (signalled
  as a bare `serious-condition`, not an `error`) still reaches cleanup.
- `--bail` only consumes a following token when that token parses as a valid
  bail value; otherwise it is treated as flag-only. `--bail=N` is accepted.
- Isolated runs read files with `uiop:read-file-string`, because `file-length`
  is a byte count rather than a character count for multibyte content.
  Temporary file and directory creation is deferred into the `unwind-protect`
  body.
- `gen-such-that` validates that its predicate is a function.
- `watch` reuses a single read buffer across file signatures.

## [0.9.0] - 2026-07-23

### Added

- `it-fuzz`, a fuzz-testing driver built on `it-property`. It reuses the
  generator and shrinking machinery but treats the body as a fuzz probe rather
  than a boolean predicate: a trial passes by running without signalling an
  `error`, and each trial runs under a per-trial timeout budget that is skipped
  rather than failed on expiry, since a slow trial is not evidence of a bug. A
  crashing trial's inputs are minimized the same way a failing property's are.

### Fixed

- Nine documented inaccuracies, found by auditing the docs against the 0.8.0
  source: a corrupted and quadruplicated JSON example plus a fictitious merged
  `artifactSchemas` entry in the AI contract, the missing `tags` field in the
  Test Plan Contract examples, an Isolated Process Contract section that
  described the deferred hardening rewrite as if it had shipped, the
  undocumented `runtime` doctor check, and invented `--test-name-pattern` and
  `--output-file` flags corrected to the real `--filter` and `--output`.

## [0.8.0] - 2026-07-19

### Changed

- Runtime hardening against pathological input: bounded caps on retry, timeout,
  worker count, candidate count and precision.
- Recursive algorithms rewritten as iterative, cycle-safe ones across the logic
  engine, run-result normalization, shrinking, and the tag and dependency
  normalizers.
- Quadratic algorithms rewritten as linear or hash-based ones for mock call
  recording, snapshot diffing, watch change detection, and test selection and
  collection.
- Thread and process concurrency safety: registry locks, a worker pool with a
  bounded default, and atomic snapshot writes.

### Fixed

- A large test expansion covering all of the above.

### Removed

- The rewritten subprocess-isolation subsystem was reverted before release and
  deferred to its own change. Under `sb-cover` instrumentation on
  `x86_64-linux` it corrupted the SBCL image with a cascade of recursive lock
  errors, although it passed on darwin. `src/isolation.lisp` and its tests are
  the 0.7.0 versions; every other hardening change is retained.

## [0.7.0] - 2026-07-19

### Added

- Top-level `CHANGELOG.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`,
  `SECURITY.md` and `SUPPORT.md` that link to the canonical `docs/src/`
  policies rather than duplicating them, plus a documentation badge and a
  Contributing section in the README.

### Changed

- The release, versioning and maintenance docs point at GitHub Releases and
  `CHANGELOG.md`.
- Clarified that the timeout prefix on the documented commands is an optional
  outer guard.
- `tmp/` and `.worktrees/` are ignored.

### Fixed

- JUnit XML output no longer emits characters that are invalid in XML 1.0.
  `xml-escaped-string` replaced only C0 control characters and passed
  everything else through, so surrogate code points (`#xD800`-`#xDFFF`) and the
  non-characters `#xFFFE` and `#xFFFF` leaked into the report and made it
  unparseable. Output is now restricted to the XML 1.0 `Char` production and
  anything outside it is substituted with `?`.

### Security

- Every GitHub Action is pinned to a full-length commit SHA instead of a
  mutable tag: `checkout`, `install-nix-action`, `cachix-action`,
  `upload-artifact`, `configure-pages`, `upload-pages-artifact` and
  `deploy-pages`.

## [0.6.0] - 2026-07-13

### Added

- Configurable coverage gates.
- `--fail-with-no-tests` on the filtered CI smoke gates, in the workflow, the
  flake checks and the quality-gate metadata, so a filter that matches zero
  tests fails instead of passing silently.

### Changed

- The Perl `alarm` timeout shim was replaced with GNU `timeout` across the CI
  workflow, the flake checks and every documented command. The devShell and
  check environments now carry `coreutils` instead of `perl`.
- The runtime-support platforms, CI integration systems, artifact bundle and
  the README and installation wording advertise `x86_64-linux` only, matching
  the CI reality.

### Removed

- The darwin runner from GitHub Actions. CI runs on `ubuntu-latest` only.

## [0.5.0] - 2026-07-12

### Added

- Native test tag filtering.
- Dependency-aware watch selection, so a file change reruns only the affected
  suites.
- Coverage artifacts uploaded from CI.
- `root-suite` is exported.

### Changed

- The README was reduced from roughly 1400 lines: its DSL, matcher and CLI
  reference content moved into `docs/src/` and is published as a GitHub Pages
  site, with a `docs` flake package and a publish workflow. The CLI's
  machine-readable documentation contract follows the new paths.
- Memory-intensive flake checks are serialized in CI.

### Fixed

- CLI coverage compilation.

## [0.4.0] - 2026-07-12

### Added

- Canonical ASDF test integration, so `asdf:test-system` is the supported entry
  point and `clear-tests` runs as part of `run-system`.

### Changed

- Shared helpers extracted behind data-driven macro families, deduplicating
  repeated patterns in `model` (registration macros and record initarg
  helpers), `registration` (`define-registration-family` for the
  `describe`/`it` variants), `cli-options` (generated spec accessors),
  `cli-metadata-core` and `cli-metadata-json-schema` (plist accessor and JSON
  writer generators), `logic` (`define-logic-query-family`), and
  `property-generators` (shared bounded-sequence construction).
- Vulnerability reports route to private GitHub security advisories across the
  README, the docs, the issue chooser and `securityContacts`.
- The metadata `schemaVersion` moved to 23 after the citation block and its
  JSON schema writers were dropped.

### Removed

- The script-based test runners.
- The in-repository governance documents (`CHANGELOG.md`, `CITATION.cff`,
  `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SECURITY.md`) and their entries in
  `policyDocuments` and `referenceDocuments`.
- The unused `describe-concurrent-each` and `describe-sequential-each` macros
  and the `call-hooks/k` helper.

## [0.2.0] - 2026-07-12

### Added

- Direct tests for the public `run`, `list-tests` and suite-designator APIs, for
  designator caching and rejection, for every run and list reporter, for
  `explain!`, for result normalization and for the matcher argument validation
  error paths. The coverage ratchet baseline rises to 87%.
- The `coverage-gate-unit` quality gate and a matching CI step covering the
  coverage gate's own unit tests.
- `paredit-cli` in the devShell and a repository-wide `paredit-lint` flake
  check for structural S-expression validation.
- A `formatter` flake output (`nixfmt`), so `nix fmt` formats `flake.nix`.
- An `overlays.default` flake output, so a downstream flake can consume
  `cl-weave` as `pkgs.cl-weave` without re-deriving the package.
- Package `meta` (description, homepage, license, platforms) on the flake's
  `cl-weave` derivation.
- A `.envrc`, so `direnv allow` loads the devShell automatically.
- `docs/README.md` as a documentation index.

### Changed

- Suites and test cases print readably, showing the record name plus child count
  or focus flag, so failure output and the REPL identify model objects without
  inspecting slots.

### Removed

- The legacy `assert-*` and `is-*` compatibility aliases, in favour of the
  canonical `expect`, `expect-not`, `signals` and `finishes` surface. Replace
  any legacy alias with the corresponding canonical expectation macro.

### Fixed

- The runner's failure path. A failing or erroring test previously crashed the
  whole run with an unbound-variable error instead of being recorded as a
  `:fail` or `:error` event: the escape continuation macro bound the
  continuation with `flet` while every caller invoked it through `funcall`.
- `after-each` cleanup also runs when a test attempt times out.
- Interactive `retry-test` records an exhausted retry budget as an `:error`
  event instead of aborting an enclosing runner.
- Coverage instrumentation. `sb-cover` only records coverage for code compiled
  with `compile-file`, and loading sources under the `:compile` evaluator mode
  produced an empty report that made the 100% gate unfalsifiable. Coverage runs
  now compile each product source to a temporary fasl, and the threshold is the
  measured 85% ratchet baseline.
- Registration syntax errors involving circular literals. Simple-error
  formatting is deferred to print time, so binding `*print-circle*` around
  `error` did not help; the message is now rendered eagerly.
- Coverage cleanup notifications no longer replace the primary unwind: the
  failure is signalled as a plain condition while a control transfer is in
  flight, rather than as an `error` subtype that enclosing handlers capture.
- The test runner registers the project systems with ASDF again, so ASDF-backed
  tests (system file collection, watch reloads, `cl-weave version`) work without
  an external `CL_SOURCE_REGISTRY`.
- Sequence shrinkers guard against foreign values, because `gen-one-of` offers
  every alternative's shrinker each candidate value.
- The metadata and CLI package split. The CLI package referenced metadata data
  through `declaim special` placeholders, leaving `*metadata-commands*` and
  friends permanently unbound at runtime.
- `docs/runtime-support.md` described an ASDF-loading timeout as an open blocker
  after it had already been fixed.

## [0.1.0] - 2026-07-11

First tagged release. `cl-weave` is a Vitest-inspired Common Lisp testing
framework with a dependency-free core, structured machine-readable reporters,
and AI-agent-oriented runtime metadata. The public surface for this release is
the documented DSL, matcher set, runner API, CLI commands, reporter shapes and
machine-readable metadata.

### Added

- The Vitest-style test DSL: `describe` and `it`/`test` suites and cases,
  `expect` matcher assertions, smart S-expression assertions, table tests,
  focus, skip, todo, retry, timeout, bail, sharding, sequence ordering,
  filtering, concurrent execution modes, and expected failures.
- Property-based testing with deterministic shrinking, form-level mutation
  testing with CI score gates, subprocess isolation for FFI and crash
  boundaries, inline and external snapshot matchers, mock functions with
  call-history matchers, and CPS continuation helpers.
- Spec, S-expression, JSON, JSONL/NDJSON, TAP, GitHub Actions and JUnit XML
  reporters with stable, versioned artifact schemas.
- The `cl-weave` CLI with `run`, `list`, `watch`, `doctor`, `metadata`,
  `version` and `help` commands, Vitest-shaped option aliases, and
  environment-variable equivalents for CI automation.
- AI-friendly runtime metadata: typed CLI options with finite choices, artifact
  schemas with field maps, a capability matrix, package exports, matchers,
  mutation operators, MOP architecture assertions, distribution channels and
  lifecycle contracts.
- ASDF system definitions, an ASDF-aware system runner, and watch mode with
  dependency-aware rerun narrowing.
- Nix flake packaging with reproducible CI entry points.
