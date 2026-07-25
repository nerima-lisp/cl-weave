(in-package #:cl-weave/metadata)

(defparameter *metadata-cli-options*
  '((:name "--system"
     :commands ("run" "list" "watch" "metadata")
     :argument "SYSTEM"
     :value-kind :asdf-system
     :choices nil
     :environment ("CL_WEAVE_SYSTEM")
     :description "ASDF system to load before command execution")
    (:name "--load"
     :commands ("run" "list" "watch" "metadata")
     :argument "FILE"
     :value-kind :file
     :choices nil
     :environment nil
     :description "Lisp file to load before command execution")
   (:name "--reporter"
     :commands ("run" "list" "watch" "doctor" "metadata")
     :argument "REPORTER"
     :value-kind :reporter
     :choices :run-reporters
     :command-choices :reporter-command-choices
     :environment ("CL_WEAVE_REPORTER")
     :description "Reporter name for run, list, watch, doctor, or metadata output")
   (:name "--filter"
     :commands ("run" "list" "watch")
     :argument "TEXT"
     :value-kind :test-name-pattern
     :choices nil
     :environment ("CL_WEAVE_TEST_FILTER")
     :description "Run or list tests whose Vitest-style path contains TEXT")
   (:name "--output"
     :commands ("run" "list" "watch" "doctor" "metadata")
     :argument "FILE"
     :value-kind :file
     :choices nil
     :environment ("CL_WEAVE_OUTPUT_FILE")
     :description "Write reporter output to FILE")
    (:name "--list"
     :commands ("run" "list")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_LIST")
     :description "Discover tests without executing test bodies")
    (:name "--watch"
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_WATCH")
     :description "Rerun an ASDF system when source files change")
    (:name "--once"
     :commands ("watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_WATCH_ONCE")
     :description "Run watch mode once without waiting for file changes")
   (:name "--watch-interval"
     :commands ("watch")
     :argument "SECONDS"
     :value-kind :seconds
     :choices nil
     :environment ("CL_WEAVE_WATCH_INTERVAL")
     :description "Polling interval for watch mode")
    (:name "--bail"
     :commands ("run" "watch")
     :argument "N|true|false"
     :value-kind :boolean-or-positive-integer
     :choices nil
     :environment ("CL_WEAVE_BAIL")
     :description "Stop after the first failure, N failures, or disable fast-fail")
    (:name "--retry"
     :commands ("run" "list" "watch")
     :argument "INTEGER"
     :value-kind :non-negative-integer
     :choices nil
     :environment ("CL_WEAVE_RETRY")
     :description "Retry failing tests INTEGER extra times")
   (:name "--test-timeout-ms"
     :commands ("run" "list" "watch")
     :argument "MS"
     :value-kind :milliseconds
     :choices nil
     :environment ("CL_WEAVE_TEST_TIMEOUT" "CL_WEAVE_TEST_TIMEOUT_MS")
     :description "Default per-attempt timeout in milliseconds")
   (:name "--max-workers"
     :commands ("run" "watch")
     :argument "INTEGER"
     :value-kind :positive-integer
     :choices nil
     :environment ("CL_WEAVE_MAX_WORKERS")
     :description "Limit concurrently executing tests to INTEGER workers")
    (:name "--shard"
     :commands ("run" "list" "watch")
     :argument "INDEX/COUNT"
     :value-kind :shard
     :choices nil
     :environment ("CL_WEAVE_SHARD")
     :description "Select a deterministic CI shard")
    (:name "--sequence"
     :commands ("run" "list" "watch")
     :argument "ORDER"
     :value-kind :sequence-order
     :choices ("random")
     :environment ("CL_WEAVE_SEQUENCE")
     :description "Randomize execution order")
    (:name "--seed"
     :commands ("run" "list" "watch")
     :argument "INTEGER"
     :value-kind :integer
     :choices nil
     :environment ("CL_WEAVE_SEQUENCE_SEED")
     :description "Deterministic random sequence seed")
    (:name "--journal"
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment nil
     :description "Record an execution journal timeline for each test attempt")
    (:name "--random-seed"
     :commands ("run" "watch")
     :argument "INTEGER"
     :value-kind :non-negative-integer
     :choices nil
     :environment nil
     :description "Seed CL:RANDOM per test for deterministic, replayable runs")
    (:name "--coverage"
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_COVERAGE")
     :description "Wrap execution with SBCL sb-cover")
   (:name "--coverage-output"
     :commands ("run" "watch")
     :argument "FILE"
     :value-kind :file
     :choices nil
     :environment ("CL_WEAVE_COVERAGE_FILE")
     :description "Save SBCL coverage state to FILE")
   (:name "--coverage-report-directory"
     :commands ("run" "watch")
     :argument "DIRECTORY"
     :value-kind :directory
     :choices nil
     :environment ("CL_WEAVE_COVERAGE_REPORT_DIRECTORY")
     :description "Generate an SBCL HTML coverage report in DIRECTORY")
   (:name "--coverage-include"
     :commands ("run" "watch")
     :argument "PATH"
     :value-kind :file
     :choices nil
     :environment nil
     :description "Include an exact source file or directory in coverage reporting")
   (:name "--coverage-exclude"
     :commands ("run" "watch")
     :argument "PATH"
     :value-kind :file
     :choices nil
     :environment nil
     :description "Exclude an exact source file or directory from coverage reporting")
   (:name "--coverage-system"
     :commands ("run" "watch")
     :argument "SYSTEM"
     :value-kind :asdf-system
     :choices nil
     :environment nil
     :description "Include source files owned by an ASDF system in coverage reporting")
   (:name "--coverage-min-expression"
     :commands ("run" "watch")
     :argument "PERCENT"
     :value-kind :percentage
     :choices nil
     :environment nil
     :description "Fail when expression coverage is below PERCENT")
   (:name "--coverage-min-branch"
     :commands ("run" "watch")
     :argument "PERCENT"
     :value-kind :percentage
     :choices nil
     :environment nil
     :description "Fail when branch coverage is below PERCENT")
   (:name "--pass-with-no-tests"
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_PASS_WITH_NO_TESTS")
     :description "Pass when filters select no tests")
   (:name "--fail-with-no-tests"
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment nil
     :description "Fail when filters select no tests")
   (:name "--snapshot-dir"
     :commands ("run" "watch")
     :argument "DIR"
     :value-kind :directory
     :choices nil
     :environment ("CL_WEAVE_SNAPSHOT_DIR")
     :description "External snapshot directory")
   (:name "--snapshot-file"
     :commands ("run" "watch")
     :argument "FILE"
     :value-kind :file
     :choices nil
     :environment ("CL_WEAVE_SNAPSHOT_FILE")
     :description "External snapshot file name")
   (:name "--update-snapshots"
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_UPDATE_SNAPSHOTS")
     :description "Update external snapshots during this run")
    (:name "--version"
     :commands ("version")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment nil
     :description "Print the cl-weave version")
    (:name "--help"
     :commands ("help")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment nil
     :description "Print command usage")))
