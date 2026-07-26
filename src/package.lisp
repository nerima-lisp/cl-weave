(defpackage #:cl-weave/metadata
  (:use #:cl)
  (:documentation
   "Static description of the framework itself: the command list, the CLI option
table, the capability matrix, the quality gates and the documents the project
publishes. Nothing here runs a test. It exists so that `cl-weave metadata` and
`cl-weave doctor` can answer \"what can this framework do\" from one table
instead of from prose that drifts, and so the self tests can hold README, CI
and the flake to that same table. Depends on no other cl-weave package, which
is what lets both #:cl-weave and #:cl-weave/cli import from it.")
  (:export
   #:framework-metadata
   #:*metadata-commands*
   #:*metadata-cli-options*
   #:metadata-cli-options
   #:cli-option-usage-lines
   #:cli-version
   #:write-doctor-report-json))

(defpackage #:cl-weave
  (:use #:cl)
  (:documentation
   "The testing framework proper, and the only package a test file needs. It
owns the whole path a test travels: the DSL that registers suites and cases,
the matcher and expectation engine, fixtures, mocks, snapshots, property and
mutation testing, the runner with its retry, timeout, sharding, concurrency
and coverage behaviour, the reporters, and watch mode. The CLI is deliberately
not here -- #:cl-weave/cli is a caller of this package, so everything the
command line can do stays reachable from a REPL.")
  ;; DESCRIBE is shadowed because cl-weave:describe is the suite-defining DSL
  ;; form, not CL's object inspector. A test file therefore never sees
  ;; cl:describe; call it as cl:describe if the inspector is what is wanted.
  (:shadow #:describe)
  (:import-from #:cl-weave/metadata
   #:framework-metadata)
  (:export
   #:framework-metadata
   #:*test-context*
   #:around-each
   #:after-all
   #:after-each
   #:assert-mutation-score
   #:assertion-failure
   #:before-all
   #:before-each
   #:benchmark
   #:benchmark-result
   #:benchmark-result-iterations
   #:benchmark-result-samples
   #:benchmark-result-warmup
   #:clear-tests
   #:collect-test-plan
   #:collect-mutations
   #:continue-test
   #:coverage-support-available-p
   #:coverage-statistics
   #:coverage-unavailable
   #:coverage-unavailable-reason
   #:defmutation-operator
   #:describe
   #:describe-concurrent
   #:describe-each
   #:describe-only
   #:describe-only-each
   #:describe-run-if
   #:describe-sequential
   #:describe-skip
   #:describe-skip-each
   #:describe-skip-if
   #:describe-todo
   #:describe-todo-each
   #:defmatcher
   #:extend-expect
   #:explain!
   #:expect
   #:expect-assertions
   #:expect-extend
   #:expect-has-assertions
   #:expect-not
   #:expect-poll
   #:expect-rejects
   #:expect-resolves
   #:expected-failure-missed
   #:expected-failure-missed-reason
   #:fail
   #:finishes
   #:gen-boolean
   #:gen-character
   #:gen-integer
   #:gen-keyword
   #:gen-list
   #:gen-map
   #:gen-member
   #:gen-one-of
   #:gen-recursive
   #:gen-form
   #:gen-sexp
   #:gen-state-machine
   #:gen-string
   #:gen-such-that
   #:gen-symbol
   #:gen-tuple
   #:gen-vector
   #:hook-failure
   #:hook-failure-causes
   #:hook-failure-phase
   #:*isolated-timeout-seconds*
   #:isolated-result
   #:isolated-result-elapsed-ms
   #:isolated-result-exit-code
   #:isolated-result-home-path
   #:isolated-result-script-path
   #:isolated-result-status
   #:isolated-result-stderr
   #:isolated-result-stderr-path
   #:isolated-result-stdout
   #:isolated-result-stdout-path
   #:isolated-result-timed-out-p
   #:*journal-enabled*
   #:journal-note
   #:journal-diff
   #:explain-journal-diff
   #:journal-frame-line
   #:journal-frame-line-for-kind
   #:record-journal-frame
   #:journal-frame-from-plist
   #:journal-frames-from-plists
   #:explain-journal
   #:with-execution-journal
   #:journal-frame
   #:journal-frame-p
   #:journal-frame-index
   #:journal-frame-kind
   #:journal-frame-form
   #:journal-frame-matcher
   #:journal-frame-actual
   #:journal-frame-expected
   #:journal-frame-pass
   #:journal-frame-elapsed-internal-time
   #:*journal-breakpoint*
   #:journal-breakpoint-hit
   #:journal-breakpoint-hit-frame
   #:*test-random-seed*
   #:replay-test
   #:it
   #:it-concurrent
   #:it-concurrent-each
   #:it-each
   #:it-fails
   #:it-fails-each
   #:it-fuzz
   #:it-isolated
   #:it-property
   #:it-only
   #:it-only-each
   #:it-run-if
   #:it-sequential
   #:it-sequential-each
   #:it-skip
   #:it-skip-each
   #:it-skip-if
   #:it-todo
   #:it-todo-each
   #:list-tests
   #:logic-program
   #:logic-query
   #:logic-search-exhausted
   #:logic-search-exhausted-limit
   #:logic-search-exhausted-partial-results
   #:logic-search-exhausted-pending
   #:logic-search-exhausted-steps
   #:increase-limit
   #:return-partial-results
   #:logic-run
   #:logic-variable-p
   #:logic-where
   #:journal-facts
   #:journal-where
   #:query-journal
   #:list-matchers
   #:list-mutation-operators
   #:matcher
   #:matcher-description
   #:matcher-metadata
   #:matcher-name
   #:maximum-ms
   #:mean-ms
   #:measure
   #:median-ms
   #:minimum-ms
   #:mutation
   #:mutation-form
   #:mutation-id
   #:mutation-operator
   #:mutation-operator-description
   #:mutation-operator-metadata
   #:mutation-operator-name
   #:mutation-original
   #:mutation-path
   #:mutation-replacement
   #:mutation-result
   #:mutation-result-condition
   #:mutation-result-mutation
   #:mutation-result-status
   #:mutation-score-failure
   #:mutation-score-failure-min-score
   #:mutation-score-failure-summary
   #:mutation-score-passes-p
   #:mutation-summary
   #:*property-seed*
   #:*property-shrink-max-steps*
   #:*property-test-count*
   #:property-shrink-limit
   #:property-shrink-limit-max-steps
   #:property-shrink-limit-steps
   #:property-shrink-limit-values
   #:accept-current
   #:property-shrinker-error
   #:property-shrinker-error-cause
   #:property-shrinker-error-generator
   #:property-shrinker-error-value
   #:retry-shrinker
   #:same-property-failure-p
   #:skip-shrinking
   #:*snapshot-directory*
   #:*snapshot-file-name*
   #:*update-snapshots*
   #:snapshot-entries
   #:snapshot-value
   #:with-snapshot-updates
   #:with-continuation-result
   #:with-continuation-values
   #:with-soft-assertions
   #:with-cleared-hash-table
   #:clear-all-mocks
   #:clear-mock
   #:make-mock-function
   #:mock-function-p
   #:mock-implementation
   #:mock-return-value
   #:mock-return-values
   #:reset-all-mocks
   #:reset-mock
   #:restore-all-mocks
   #:reporter-artifact-schemas
   #:run-reporters
   #:list-reporters
   #:skip
   #:mock-restore
   #:spy-on
   #:mock-calls
   #:mock-results
   #:*test-sequence-order*
   #:*test-sequence-seed*
   #:*test-name-filter*
   #:*default-retry*
   #:*default-timeout-ms*
   #:asdf-system-files
   #:report-mutations-json
   #:report-mutations-sexp
   #:results-status
   #:root-suite
   #:run
   #:run-all
   #:run-isolated
   #:run-mutations
   #:run-system
   #:signals
   #:query-test-plan
   #:reset-coverage
   #:save-coverage
   #:retry-test
   #:skip-test
   #:test-plan-entry
   #:test-plan-entry-focused
   #:test-plan-entry-location
   #:test-plan-entry-tags
   #:test-plan-entry-path
   #:test-plan-entry-reason
   #:test-plan-entry-retry
   #:test-plan-entry-status
   #:test-plan-entry-timeout-ms
   #:test-plan-entry-concurrent
   #:test-plan-facts
   #:test-plan-where
   #:test-failure
   #:test-timeout
   #:test-timeout-ms
   #:*max-workers*
   #:watch-system
   #:with-mocked-functions
   #:with-replaced-function
   #:with-restored-binding
   #:with-restored-bindings
   #:with-restored-hash-table #:dispose-mock #:mock-disposed-error #:mock-disposed-error-mock #:active-spy-disposal-error #:active-spy-disposal-error-mock #:active-spy-disposal-error-symbol))

(defpackage #:cl-weave/cli
  (:use #:cl)
  (:documentation
   "The `cl-weave` executable: argument parsing, environment defaults, the run,
list, watch, doctor, metadata, version and help commands, and the process exit
status they produce. It is a thin translation layer -- every command resolves
to calls into #:cl-weave and #:cl-weave/metadata -- so a behaviour that only
the CLI can reach would be a bug. Exports only #:main; the command internals
stay unexported because their shape is not something downstream should pin.")
  (:import-from #:cl-weave/metadata
   #:*metadata-commands*
   #:*metadata-cli-options*
   #:metadata-cli-options
   #:cli-option-usage-lines
   #:cli-version
   #:write-doctor-report-json)
  (:export
   #:main))
