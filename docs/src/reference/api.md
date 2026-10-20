# API Reference

This page lists the public APIs exported by `cl-weave`, `cl-weave/cli`, and
`cl-weave/metadata`, grouped by concept. The `cl-weave` groups match the sections
of the guide, and each group links to the page that explains how and why the
symbols are used.

`cl-weave` shadows `cl:describe`. Import it with
`(:shadowing-import-from #:cl-weave #:describe)` or qualify it as
`cl-weave:describe`; see [Quick Start](../getting-started.md) for the usual
`defpackage` form.

`cl-weave/metadata` exports `framework-metadata`, `*metadata-commands*`,
`*metadata-cli-options*`,
`metadata-cli-options`, `cli-option-usage-lines`, `cli-version` and
`write-doctor-report-json`, which are the Lisp side of the contract described in
the [Doctor Report](doctor-report.md). `framework-metadata` is also exported by
`cl-weave`. `cl-weave/cli` exports `main`, the packaged executable's entry
point, `run-all-options-from-environment`, and `run-coverage`, the programmatic
coverage entry point. Unless a package is named, the symbol inventories below
list exports from `cl-weave`.

Anything not listed on this page is internal and may change without a major
version bump. See [Versioning Policy](../project/versioning-policy.md).

## Suites and test cases

Registration macros. `describe` groups, and `it` declares a case. The suffixes
compose orthogonally: `-only` focuses, `-skip` and `-todo` mark,
`-each` drives a table, and `-run-if` and `-skip-if` gate on a runtime value.
Their conditions are evaluated while the test file registers cases. `-run-if`
registers a skipped case or suite when its condition is false; `-skip-if` does
so when its condition is true. A skipped branch emits a `:skip` event, and its
hooks and body do not execute.
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

## Execution journal and replay

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
machine-readable framework metadata. See the
[Test Execution](../guide/test-execution.md) guide for test selection and
execution.

`run`, `run-all`, `run-system`, `watch-system`, `run-reporters`,
`list-reporters`, `reporter-artifact-schemas`, `results-status`, `explain!`,
`asdf-system-files`, `framework-metadata`, `*max-workers*`

### Observing test attempts

`run-all` accepts `:on-test-attempt-complete`, a function of two arguments:
the test path as a list of strings and the assertion count for that attempt as
an integer. It calls the function after the attempt's `after-each` cleanup,
including after failed and timed-out attempts. Each retry is a separate
attempt and produces another call. Tests skipped or marked todo without being
run do not produce a call.

The callback is scoped to that `run-all` invocation and does not change suite
hooks. A serious condition signaled by the callback propagates to the caller.

```lisp
(cl-weave:run-all
 :max-workers 1
 :on-test-attempt-complete
 (lambda (path assertion-count)
   (format *trace-output* "~&~{~A~^ > ~}: ~D assertions~%"
           path assertion-count)))
```

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

### Running coverage from Lisp

`cl-weave/cli:run-coverage` accepts the same CLI token list and command
dispatch as `main`. For a test coverage run, pass `"run"` as the command:

```lisp
(cl-weave/cli:run-coverage '("run" "cl-weave/test" "--coverage"))
```

`cl-weave/test` is this repository's self-test system. Replace it with the
ASDF system that contains your tests.

Its signature is:

```lisp
(cl-weave/cli:run-coverage argv
                           &key run-options
                                around-input-loading
                                around-coverage-consumer)
```

`argv` is a list of CLI argument strings. `run-options` is a keyword plist
that overlays the options derived from `argv` and the CLI environment; when a
key appears in both, the value in `run-options` takes precedence.
For a test run, `run-coverage` returns `0` when the tests pass and `1` when
they fail. It returns `2` for CLI parsing or validation errors, writing the
CLI diagnostic to `*error-output*`, as `main` does. Help and version requests
return `0`. For other commands, success returns `0` and failure returns `1`.
This matches the CLI's existing status mapping. Other operational errors and
serious conditions signaled by either callback propagate to the caller.

`around-input-loading`, when supplied, wraps input loading when the dispatched
command reaches that step. The callback receives the default input-loading
thunk and must call it exactly once to load the requested inputs. Forwarding
the thunk's value is conventional but optional; the command dispatcher ignores
whatever value the callback returns, so it does not affect `run-coverage`'s
result. Help and version
requests, parse or validation errors, and the `doctor` command do not invoke
this callback:

```lisp
(cl-weave/cli:run-coverage
 '("run" "cl-weave/test" "--coverage")
 :around-input-loading
 (lambda (load-inputs)
   (format *trace-output* "Loading test inputs.~%")
   (funcall load-inputs)))
```

`around-coverage-consumer`, when supplied, is called with a kind and a consumer
thunk. The kind is `:report`, `:statistics`, or `:data`. Call the supplied
thunk exactly once to run that consumer, and return its value from the callback.
The `:statistics` value is passed to threshold checks, so the callback must
return the statistics thunk's value for those checks to use its plist. The
`:report` and `:data` return values are discarded after their output side
effects:

```lisp
(cl-weave/cli:run-coverage
 '("run" "cl-weave/test" "--coverage")
 :around-coverage-consumer
 (lambda (kind consume)
   (format *trace-output* "Coverage consumer: ~A~%" kind)
   (funcall consume)))
```

Consumers run only during an enabled coverage run. The `:report` consumer is
called when a coverage report directory is configured, `:statistics` when a
minimum coverage threshold is configured, and `:data` when a coverage output
path is configured. A consumer whose corresponding setting is absent is not
called.

## Dynamic-state helpers

Scoped restoration of bindings, function definitions and hash-table contents,
so a test that mutates global state cannot leak into the next one.

`with-restored-binding`, `with-restored-bindings`, `with-replaced-function`,
`with-restored-hash-table`, `with-cleared-hash-table`
