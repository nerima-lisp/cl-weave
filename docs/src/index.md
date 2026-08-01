# cl-weave

`cl-weave` is a modern Common Lisp testing framework inspired by Vitest and
designed around Lisp's strengths: macros, conditions, dynamic bindings, and
reproducible Nix workflows.

The project is intentionally dependency-free at the core. It should be easy to
run in CI, embed in ASDF projects, and extend from the REPL.

!!! tip "New to cl-weave?"

    Install it in one command, then write your first suite in under a minute:

    ```sh
    nix run github:nerima-lisp/cl-weave -- --help   # run without installing
    ```

    Continue with [Installation](getting-started.md) → [Quick Start](getting-started.md)
    → [DSL Guide](guide/dsl-guide.md).

## Explore the docs

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } &nbsp; **Getting Started**

    ---

    Every Nix install path, your first passing suite, and a step-by-step guide
    to adopting cl-weave in an existing ASDF project.

    [:octicons-arrow-right-24: Installation](getting-started.md) ·
    [Quick Start](getting-started.md) ·
    [Adoption](guide/adoption.md)

-   :material-book-open-variant:{ .lg .middle } &nbsp; **Writing Tests**

    ---

    Suites, cases, fixtures, focus/skip/todo, retry/timeout, concurrency, and
    compile-time table tests — the full `describe` / `it` / `expect` surface.

    [:octicons-arrow-right-24: DSL Guide](guide/dsl-guide.md) ·
    [Assertions](guide/assertions.md) ·
    [Mocking](guide/mocking.md)

-   :material-flask-outline:{ .lg .middle } &nbsp; **Advanced Testing**

    ---

    Property-based testing with shrinking, form-level mutation testing, and
    time-travel debugging over a recorded execution journal.

    [:octicons-arrow-right-24: Property Testing](guide/property-testing.md) ·
    [Mutation](guide/mutation-testing.md) ·
    [Time-Travel](guide/time-travel-debugging.md)

-   :material-cog-outline:{ .lg .middle } &nbsp; **Running & CI**

    ---

    Filtering, sharding, sequencing, bail, and watch mode; spec/JSON/TAP/JUnit
    reporters; SBCL coverage artifacts; and the machine-readable AI contract.

    [:octicons-arrow-right-24: Test Execution](guide/test-execution.md) ·
    [Reporters & CI](guide/reporters-and-ci.md) ·
    [AI Discovery](guide/ai-discovery.md)

</div>

## Status

Stable (`1.0`). The capability list below is the committed public surface, and
it is validated by the CI entrypoints documented in [Reporters and CI](guide/reporters-and-ci.md)
on Linux. Within the `1.x` series, changes stay backward-compatible under
[Semantic Versioning](project/versioning-policy.md); breaking changes ship only in a new
major version:

- `describe` / `it` hierarchical test DSL
- `expect` matcher assertions with readable failure reports
- smart S-expression assertions that capture operand values
- `with-soft-assertions` blocks that run every expectation and report all failures together
- `it-each` and `describe-each` compile-time table tests
- canonical hyphenated variants such as `it-only`, `describe-concurrent`,
  `expect-not`, `expect-resolves`, and `expect-assertions`
- `it-property` deterministic property tests with shrinking
- form-level mutation testing with macro-defined operators
- `it-isolated` subprocess tests for FFI and crash boundaries
- `before-all` / `after-all`, `before-each` / `after-each`, and CPS `around-each` dynamic fixtures
- `describe-skip` / `it-skip` skipped suites and cases
- `describe-skip-if` / `it-skip-if` and `run-if` conditional registration
- `describe-only` / `it-only` focused runs
- `describe-todo` / `it-todo` todo suites and cases
- Vitest-style test name filtering for focused local and CI runs
- Vitest-style test discovery list mode for AI agents and CI tooling
- declarative logic-query engine (`logic-program`, `logic-run`, `test-plan-where`, `journal-where`) for querying the test plan and time-travel journal as Prolog-style facts
- AI-friendly CLI metadata for typed/enumerated options, artifact schemas with field maps, capability matrix, package exports, policy documents, matchers, mutations, and MOP architecture assertions
- source file metadata in structured reporters and test plans
- Vitest-style deterministic sequence ordering for flaky-test reproduction
- time-travel execution journal recording an assertion/mock-call/hook/shrink-step/note timeline per attempt, surfaced in the spec and JSON reporters
- deterministic per-test random replay with recorded seeds and single-test `replay-test`
- interactive time-travel breakpoints: `*journal-breakpoint*` signals `journal-breakpoint-hit` at a chosen frame, dropping into a live debugger or a programmatic `handler-bind` hook
- CLOS-extensible journal frame kinds: `record-journal-frame` records your own frame kind, `journal-frame-line-for-kind` is an eql-specialized generic function for rendering it
- reloadable timelines: `journal-frame-from-plist` rebuilds `journal-frame` objects from a saved `sexp` results artifact, so a CI-captured timeline can be `read` back and analyzed offline with `explain-journal` / `journal-diff` / `journal-where`
- Vitest-style `:bail` execution control for fast-fail CI runs
- Vitest-style per-test `:retry` and `:timeout-ms` controls
- Vitest-style `it-concurrent` / `describe-concurrent` parallel execution modes
- Vitest-style `it-fails` expected-failure cases
- Vitest-style length, instance, inline snapshot, and external snapshot matchers
- CI-friendly thunk runtime and allocation assertions
- SBCL `sb-cover` reset/save integration for CI coverage artifacts
- Vitest-style mock functions with call history assertions
- ASDF system definitions
- ASDF-aware system runner and watch mode
- spec, S-expression, JSON, JSONL, TAP, GitHub Actions, and JUnit XML reporters
- non-zero process exit on failure for CI
- safe dynamic global function mocking with `with-mocked-functions`

## Guide Map

- [DSL Guide](guide/dsl-guide.md) — suites, cases, fixtures, skipping, focus/todo,
  retry/timeout, concurrency, and table tests.
- [Assertions and Matchers](guide/assertions.md) — `expect`, built-in and custom
  matchers, performance, and numeric assertions.
- [Property Testing](guide/property-testing.md) — `it-property` and the built-in
  generator library.
- [Mutation Testing](guide/mutation-testing.md) — mutation operators and CI score
  gates.
- [Mocking](guide/mocking.md) — mock functions, spies, and call-history matchers.
- [Benchmarking](guide/benchmarking.md) — the `benchmark` / `measure` micro-benchmark
  helper and its timing statistics.
- [Time-Travel Debugging](guide/time-travel-debugging.md) — the execution journal,
  deterministic replay, single-test replay, and interactive breakpoints.
- [Test Execution](guide/test-execution.md) — filtering, sharding, sequencing,
  listing, declarative plan queries, bail, subprocess isolation, and watch mode.
- [Logic Programming](guide/logic-programming.md) — the unification/backtracking
  query engine behind declarative test-plan queries.
- [Reporters and CI](guide/reporters-and-ci.md) — reporter formats, coverage, and
  the GitHub Actions pipeline.
- [AI Discovery](guide/ai-discovery.md) — the machine-readable metadata contract
  for agents and generators.

## Reference Map

- [API Reference](reference/api.md) — every exported symbol, grouped by concept.
- [AI Contract](reference/ai-contract.md) — the frozen artifact and metadata schemas.
- [Runtime Support](reference/runtime-support.md) — supported implementations and
  platforms.
- [Doctor Report](reference/doctor-report.md) — the `doctor` health checks.
- [Development](project/development.md) — build, test, coverage and formatting commands.
- [GitHub Releases](https://github.com/nerima-lisp/cl-weave/releases) — the
  release history.

## Nix Workflow

The [flake.nix](https://github.com/nerima-lisp/cl-weave/blob/main/flake.nix) at
the repository root packages `cl-weave` as a Nix flake:

- `nix develop` — a devShell with SBCL and GNU coreutils, and
  [`paredit-cli`](https://github.com/takeokunn/paredit-cli) for structural
  S-expression edits.
- `nix run . -- <command>` — the packaged CLI (`run`, `list`, `watch`,
  `doctor`, `metadata`, `version`, `help`).
- `nix run .#test` — the self-test suite through `run-tests.lisp`.
- `nix flake check` — every CI entrypoint (test suite, reporters, coverage
  gate, AI metadata, CLI smoke tests, `paredit-lint` structural parse check,
  the treefmt formatting gate, and the docs build) as reproducible derivations.
- `nix build .#docs` — builds this documentation site with MkDocs (Material)
  in `--strict` mode, so broken links fail the build.
- `nix fmt` — formats Nix sources with treefmt (nixfmt).

Running `direnv allow` loads the devShell automatically.

## Support

Use [Support Policy](project/support-policy.md) for the canonical support
boundaries.

Use [Issue Reporting Guide](project/issue-reporting.md) for reproducible bugs
and behavior questions.

Use [private GitHub security advisories](https://github.com/nerima-lisp/cl-weave/security/advisories/new)
for vulnerability reporting. Do not put exploit details in a public issue.

## Project Operations

- Adoption guide: [docs/src/guide/adoption.md](guide/adoption.md)
- AI contract: [docs/src/reference/ai-contract.md](reference/ai-contract.md)
- Issue reporting guide: [docs/src/project/issue-reporting.md](project/issue-reporting.md)
- Pull request guidance: [docs/src/project/pull-request-template.md](project/pull-request-template.md)
- Pull request form: [.github/pull_request_template.md](https://github.com/nerima-lisp/cl-weave/blob/main/.github/pull_request_template.md)
- Pull request queue: <https://github.com/nerima-lisp/cl-weave/pulls>
- Bug report form: [.github/ISSUE_TEMPLATE/bug_report.md](https://github.com/nerima-lisp/cl-weave/blob/main/.github/ISSUE_TEMPLATE/bug_report.md)
- Feature request form: [.github/ISSUE_TEMPLATE/feature_request.md](https://github.com/nerima-lisp/cl-weave/blob/main/.github/ISSUE_TEMPLATE/feature_request.md)
- Issue template routing: [.github/ISSUE_TEMPLATE/config.yml](https://github.com/nerima-lisp/cl-weave/blob/main/.github/ISSUE_TEMPLATE/config.yml)
- Community health contract: [docs/src/project/community-health.md](project/community-health.md)
- Code ownership: [.github/CODEOWNERS](https://github.com/nerima-lisp/cl-weave/blob/main/.github/CODEOWNERS)
- Governance: [docs/src/project/governance.md](project/governance.md)
- Maintenance policy: [docs/src/project/maintenance-policy.md](project/maintenance-policy.md)
- Distribution policy: [docs/src/project/distribution-policy.md](project/distribution-policy.md)
- Support policy: [docs/src/project/support-policy.md](project/support-policy.md)
- Runtime support: [docs/src/reference/runtime-support.md](reference/runtime-support.md)
- Release process: [docs/src/project/release-process.md](project/release-process.md)
- Versioning policy: [docs/src/project/versioning-policy.md](project/versioning-policy.md)
- Project scope: [docs/src/project/project-scope.md](project/project-scope.md)
- Triage policy: [docs/src/project/triage-policy.md](project/triage-policy.md)
- Security reporting: <https://github.com/nerima-lisp/cl-weave/security/advisories/new>
- Issue tracker: <https://github.com/nerima-lisp/cl-weave/issues>
- Release notes: <https://github.com/nerima-lisp/cl-weave/releases>

Runtime metadata mirrors these operations surfaces through `policyDocuments`,
`referenceDocuments`, `supportChannels`, `communityHealth`,
`securityContacts`, `lifecycle`, `runtimeSupport`, and `releaseProcess` for
agent-side OSS operations discovery.

## License

MIT. See [LICENSE](https://github.com/nerima-lisp/cl-weave/blob/main/LICENSE).
