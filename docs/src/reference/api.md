# API Reference

Every symbol exported by the `cl-weave` package, grouped by concept. The groups
match the sections of the guide, and each group links to the page that explains
how and why the symbols are used.

`cl-weave` shadows `cl:describe`. Import it with
`(:shadowing-import-from #:cl-weave #:describe)` or qualify it as
`cl-weave:describe`; see [Quick Start](../getting-started.md) for the usual
`defpackage` form.

Two further packages are public. `cl-weave/metadata` exports
`framework-metadata`, `*metadata-commands*`, `*metadata-cli-options*`,
`metadata-cli-options`, `cli-option-usage-lines`, `cli-version` and
`write-doctor-report-json`, which are the Lisp side of the contract described in
[AI Discovery](../guide/ai-discovery.md) and [AI Contract](ai-contract.md).
`cl-weave/cli` exports `main`, the entry point of the packaged executable.

Anything not listed on this page is internal and may change without a major
version bump. See [Versioning Policy](../project/versioning-policy.md).

## Suites and test cases

Registration macros. `describe` groups, `it` (and `test`) declares a case, and
the suffixes compose orthogonally: `-only` focuses, `-skip` and `-todo` mark,
`-each` drives a table, `-if` and `-run-if` gate on a runtime value,
`-concurrent` and `-sequential` set the execution mode, `-fails` expects a
failure, `-isolated` runs in a subprocess, `-property` and `-fuzz` generate
inputs. See [DSL Guide](../guide/dsl-guide.md).

`describe`, `describe-concurrent`, `describe-each`, `describe-only`,
`describe-only-each`, `describe-run-if`, `describe-sequential`,
`describe-skip`, `describe-skip-each`, `describe-skip-if`, `describe-todo`,
`describe-todo-each`, `it`, `it-concurrent`, `it-concurrent-each`, `it-each`,
`it-fails`, `it-fails-each`, `it-fuzz`, `it-isolated`, `it-only`,
`it-only-each`, `it-property`, `it-run-if`, `it-sequential`,
`it-sequential-each`, `it-skip`, `it-skip-each`, `it-skip-if`, `it-todo`,
`it-todo-each`, `fail`, `skip`, `root-suite`, `clear-tests`

## Hooks and fixtures

Setup and teardown around a suite or a case, plus the per-test context object.
`after-each` and `after-all` run under `unwind-protect`, so they fire even when
the body times out. See [DSL Guide](../guide/dsl-guide.md).

`before-all`, `before-each`, `around-each`, `after-each`, `after-all`,
`*test-context*`

## Expectations and matchers

`expect` and `expect-not` drive the matcher protocol; `signals` and `finishes`
assert on conditions; `defmatcher` and `expect-extend`/`extend-expect` add
custom matchers; `with-soft-assertions` aggregates failures instead of aborting
on the first. See [Assertions and Matchers](../guide/assertions.md).

`expect`, `expect-not`, `expect-assertions`, `expect-has-assertions`,
`expect-poll`, `expect-rejects`, `expect-resolves`, `expect-extend`,
`extend-expect`, `defmatcher`, `signals`, `finishes`, `with-soft-assertions`,
`list-matchers`, `matcher`, `matcher-name`, `matcher-description`,
`matcher-metadata`, `assertion-failure`, `test-failure`,
`expected-failure-missed`, `expected-failure-missed-reason`

## Snapshots

Inline and external snapshot storage and the update switch. See
[Assertions and Matchers](../guide/assertions.md).

`snapshot-value`, `snapshot-entries`, `with-snapshot-updates`,
`*snapshot-directory*`, `*snapshot-file-name*`, `*update-snapshots*`

## Mocks and spies

Mock function construction, call and result history, implementation and return
value control, disposal and restoration, and the conditions raised when a
disposed mock or an active spy is misused. See [Mocking](../guide/mocking.md).

`make-mock-function`, `mock-function-p`, `spy-on`, `with-mocked-functions`,
`mock-calls`, `mock-results`, `mock-implementation`, `mock-return-value`,
`mock-return-values`, `mock-restore`, `clear-mock`, `clear-all-mocks`,
`reset-mock`, `reset-all-mocks`, `restore-all-mocks`, `dispose-mock`,
`mock-disposed-error`, `mock-disposed-error-mock`, `active-spy-disposal-error`,
`active-spy-disposal-error-mock`, `active-spy-disposal-error-symbol`

## Property-based testing and fuzzing

Generators, the shrinking protocol and its restarts, and the dynamic variables
that control trial count, seed and shrink budget. Integer shrinking moves toward
the in-range value closest to zero. See [Property Testing](../guide/property-testing.md).

`gen-boolean`, `gen-character`, `gen-form`, `gen-integer`, `gen-keyword`,
`gen-list`, `gen-map`, `gen-member`, `gen-one-of`, `gen-recursive`, `gen-sexp`,
`gen-state-machine`, `gen-string`, `gen-such-that`, `gen-symbol`, `gen-tuple`,
`gen-vector`, `*property-seed*`, `*property-test-count*`,
`*property-shrink-max-steps*`, `property-shrink-limit`,
`property-shrink-limit-steps`, `property-shrink-limit-max-steps`,
`property-shrink-limit-values`, `property-shrinker-error`,
`property-shrinker-error-cause`, `property-shrinker-error-generator`,
`property-shrinker-error-value`, `same-property-failure-p`, `accept-current`,
`retry-shrinker`, `skip-shrinking`

## Mutation testing

Form-level mutation collection, the operator protocol, run results, the score
gate, and the JSON and S-expression mutation reporters. See
[Mutation Testing](../guide/mutation-testing.md).

`collect-mutations`, `run-mutations`, `defmutation-operator`,
`list-mutation-operators`, `mutation`, `mutation-id`, `mutation-form`,
`mutation-original`, `mutation-replacement`, `mutation-path`,
`mutation-operator`, `mutation-operator-name`,
`mutation-operator-description`, `mutation-operator-metadata`,
`mutation-result`, `mutation-result-mutation`, `mutation-result-status`,
`mutation-result-condition`, `mutation-summary`, `mutation-score-passes-p`,
`assert-mutation-score`, `mutation-score-failure`,
`mutation-score-failure-min-score`, `mutation-score-failure-summary`,
`report-mutations-json`, `report-mutations-sexp`

## Benchmarking

The micro-benchmark helper and the timing statistics it records. See
[Benchmarking](../guide/benchmarking.md).

`benchmark`, `measure`, `benchmark-result`, `benchmark-result-iterations`,
`benchmark-result-samples`, `benchmark-result-warmup`, `mean-ms`, `median-ms`,
`minimum-ms`, `maximum-ms`

## Subprocess isolation

Running a form in a separate SBCL process and inspecting its exit status,
streams, on-disk artifacts and timeout state. See
[Test Execution](../guide/test-execution.md).

`run-isolated`, `isolated-result`, `isolated-result-status`,
`isolated-result-exit-code`, `isolated-result-stdout`,
`isolated-result-stderr`, `isolated-result-stdout-path`,
`isolated-result-stderr-path`, `isolated-result-script-path`,
`isolated-result-home-path`, `isolated-result-elapsed-ms`,
`isolated-result-timed-out-p`, `*isolated-timeout-seconds*`

## Execution journal, replay and soft assertions

The opt-in timeline of assertions, mocks, hooks, notes and shrink steps; its
frame accessors and plist round trip; the CLOS hook for custom frame kinds;
interactive breakpoints; and deterministic replay. See
[Time-Travel Debugging](../guide/time-travel-debugging.md).

`with-execution-journal`, `*journal-enabled*`, `record-journal-frame`,
`journal-note`, `journal-frame`, `journal-frame-p`, `journal-frame-index`,
`journal-frame-kind`, `journal-frame-form`, `journal-frame-matcher`,
`journal-frame-expected`, `journal-frame-actual`, `journal-frame-pass`,
`journal-frame-elapsed-internal-time`, `journal-frame-line`,
`journal-frame-line-for-kind`, `journal-frame-from-plist`,
`journal-frames-from-plists`, `explain-journal`, `journal-diff`,
`explain-journal-diff`, `journal-where`, `journal-facts`, `query-journal`,
`*journal-breakpoint*`, `journal-breakpoint-hit`,
`journal-breakpoint-hit-frame`, `replay-test`, `*test-random-seed*`

## Logic queries

The unification and backtracking engine, its query macros, and the restarts
offered when a search exhausts its step limit. See
[Logic Programming](../guide/logic-programming.md).

`logic-program`, `logic-query`, `logic-run`, `logic-where`,
`logic-variable-p`, `logic-search-exhausted`, `logic-search-exhausted-limit`,
`logic-search-exhausted-steps`, `logic-search-exhausted-pending`,
`logic-search-exhausted-partial-results`, `increase-limit`,
`return-partial-results`

## Test plans and selection

Collecting the plan without running it, querying it declaratively, and the
dynamic variables that filter and order selection. See
[Test Execution](../guide/test-execution.md).

`collect-test-plan`, `query-test-plan`, `list-tests`, `test-plan-where`,
`test-plan-facts`, `test-plan-entry`, `test-plan-entry-path`,
`test-plan-entry-status`, `test-plan-entry-reason`, `test-plan-entry-tags`,
`test-plan-entry-location`, `test-plan-entry-focused`,
`test-plan-entry-concurrent`, `test-plan-entry-retry`,
`test-plan-entry-timeout-ms`, `*test-name-filter*`, `*test-sequence-order*`,
`*test-sequence-seed*`

## Running and reporting

Entry points for running a suite, a system or a watch loop, the reporter
inventory and artifact schemas, result status normalization, and the
machine-readable framework metadata. See
[Reporters and CI](../guide/reporters-and-ci.md) and [AI Discovery](../guide/ai-discovery.md).

`run`, `run-all`, `run-system`, `watch-system`, `run-reporters`,
`list-reporters`, `reporter-artifact-schemas`, `results-status`, `explain!`,
`asdf-system-files`, `framework-metadata`, `*max-workers*`

## Retries, timeouts and control flow

Retry and timeout defaults, the interactive restarts offered from a failing
test, the conditions raised on timeout and hook failure, and the continuation
helpers. See [DSL Guide](../guide/dsl-guide.md).

`*default-retry*`, `*default-timeout-ms*`, `retry-test`, `continue-test`,
`skip-test`, `test-timeout`, `test-timeout-ms`, `hook-failure`,
`hook-failure-phase`, `hook-failure-causes`, `with-continuation-result`,
`with-continuation-values`

## Coverage

The `sb-cover` integration, its statistics, and the condition raised when
coverage is unavailable on the running implementation. See
[Reporters and CI](../guide/reporters-and-ci.md).

`coverage-statistics`, `coverage-support-available-p`, `reset-coverage`,
`save-coverage`, `coverage-unavailable`, `coverage-unavailable-reason`

## Dynamic-state helpers

Scoped restoration of bindings, function definitions and hash-table contents,
so a test that mutates global state cannot leak into the next one.

`with-restored-binding`, `with-restored-bindings`, `with-replaced-function`,
`with-restored-hash-table`, `with-cleared-hash-table`
