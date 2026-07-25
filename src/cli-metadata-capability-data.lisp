(in-package #:cl-weave/metadata)

(defparameter *metadata-capabilities*
  '("vitest-dsl"
    "describe-it-dsl"
    "expect-matchers"
    "smart-s-expression-assertions"
    "fixtures-and-restarts"
    "fixtures"
    "around-each-continuations"
    "mocks-and-spies"
    "mock-functions"
    "snapshots"
    "property-and-mutation"
    "property-tests"
    "mutation-testing"
    "structured-reporting"
    "subprocess-isolation"
    "coverage"
    "watch-and-parallelism"
    "watch"
    "sharding"
    "isolation-and-cps"
    "artifact-schemas"
    "sequence-ordering"
    "retry"
    "timeout"
    "mop-architecture-assertions"
    "logic-test-plan"
    "ai-discovery-metadata"
    "public-package-exports"
    "cps-continuation-helpers"
    "time-travel-debugging"
    "deterministic-replay"
    "soft-assertions"
    "interactive-breakpoints"
    "journal-logic-queries"))

(defparameter *metadata-capability-matrix*
  '((:name "vitest-dsl"
     :status "implemented"
     :summary "Vitest-style describe/it DSL with only, skip, todo, each, fails, conditional, concurrent, sequential, property, and isolated variants."
     :public-apis ("describe" "it" "describe-each" "it-each"
                   "it-concurrent" "it-property" "it-isolated")
     :quality-gates ("flake-check" "filtered-smoke" "plan-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "describe-it-dsl"
     :status "implemented"
     :summary "Core describe/it forms and each-style variants define the primary suite authoring surface."
     :public-apis ("describe" "it" "describe-each" "it-each")
     :quality-gates ("flake-check" "filtered-smoke" "plan-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "expect-matchers"
     :status "implemented"
     :summary "Vitest-style expect API with numeric, collection, string, condition, macro, snapshot, mock, performance, and MOP architecture matchers."
     :public-apis ("expect" "expect-not" "expect-resolves" "expect-rejects"
                   "expect-assertions" "expect-has-assertions" "matcher-metadata")
     :quality-gates ("flake-check" "cli-json-results")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "smart-s-expression-assertions"
     :status "implemented"
     :summary "The canonical assertion DSL covers plain values, signals, completion, multiple values, and type checks through matcher chains."
     :public-apis ("expect" "expect-not" "signals" "finishes")
     :quality-gates ("flake-check" "cli-json-results")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "fixtures-and-restarts"
     :status "implemented"
     :summary "before/after/around fixtures and interactive restarts for continue, skip, and retry test recovery."
     :public-apis ("before-all" "after-all" "before-each" "after-each"
                   "around-each")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "fixtures"
     :status "implemented"
     :summary "before-all, after-all, before-each, and after-each hooks provide reusable fixture setup and teardown."
     :public-apis ("before-all" "after-all" "before-each" "after-each")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "around-each-continuations"
     :status "implemented"
     :summary "around-each hooks and continuation helpers support CPS-style wrapping around test bodies and async-style flows."
     :public-apis ("around-each" "with-continuation-result"
                   "with-continuation-values")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "mocks-and-spies"
     :status "implemented"
     :summary "Mock functions and spies with call/result metadata and restoration helpers."
     :public-apis ("make-mock-function" "spy-on" "dispose-mock" "clear-all-mocks" "mock-calls" "mock-results")
     :quality-gates ("flake-check" "cli-json-results")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "mock-functions"
     :status "implemented"
     :summary "Raw mock primitives expose direct control over stub behavior, restoration, and recorded calls or results."
     :public-apis ("make-mock-function" "clear-mock" "reset-mock" "dispose-mock" "mock-restore" "mock-calls" "mock-results")
     :quality-gates ("flake-check" "cli-json-results")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "snapshots"
     :status "implemented"
     :summary "Snapshot helpers support update mode, stored entry inspection, and explicit value snapshot assertions."
     :public-apis ("with-snapshot-updates" "snapshot-entries"
                   "snapshot-value")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "property-and-mutation"
     :status "implemented"
     :summary "Property checks and mutation testing metadata for stronger behavioral confidence than example tests alone."
     :public-apis ("it-property" "gen-integer" "gen-string"
                   "run-mutations" "list-mutation-operators")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "property-tests"
     :status "implemented"
     :summary "Property-test APIs expose generators and quantified assertions for broader input coverage than example-based suites."
     :public-apis ("it-property" "gen-integer" "gen-string"
                   "gen-list" "gen-map" "gen-vector"
                   "gen-state-machine")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "mutation-testing"
     :status "implemented"
     :summary "Mutation-test APIs surface operator inventory, mutation runs, and score thresholds."
     :public-apis ("run-mutations" "list-mutation-operators"
                   "assert-mutation-score")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "structured-reporting"
     :status "implemented"
     :summary "Spec, SEXP, JSON, JSONL, TAP, GitHub annotation, JUnit, plan, and coverage artifacts with machine-readable schemas."
     :public-apis ("run" "list-tests" "reporter-artifact-schemas"
                   "framework-metadata")
     :quality-gates ("json-results-artifact" "jsonl-events-artifact"
                     "tap-artifact" "junit-artifact" "plan-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "subprocess-isolation"
     :status "implemented"
     :summary "Subprocess isolation APIs protect the main runner from crashes, FFI failures, and process-boundary hazards."
     :public-apis ("it-isolated" "run-isolated")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "coverage"
     :status "implemented"
     :summary "Coverage helpers expose runtime capability checks, state reset, populated HTML report generation, optional sidecar persistence, and suite execution entrypoints."
     :public-apis ("run-all" "reset-coverage" "save-coverage"
                   "coverage-support-available-p")
     :quality-gates ("flake-check" "coverage-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "watch-and-parallelism"
     :status "implemented"
     :summary "Watch-once automation, filtering, sharding, deterministic sequence controls, and bounded adjacent concurrent batches."
     :public-apis ("run" "run-all" "list-tests")
     :quality-gates ("watch-once-artifact" "filtered-smoke" "flake-check")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "watch"
     :status "implemented"
     :summary "System-scoped run and watch entrypoints provide CLI-friendly iteration loops for local development."
     :public-apis ("watch-system" "run-system")
     :quality-gates ("watch-once-artifact" "flake-check")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "sharding"
     :status "implemented"
     :summary "Shard-aware run and listing entrypoints support partitioned execution without abandoning deterministic plan generation."
     :public-apis ("run" "run-all" "list-tests" "run-system"
                   "watch-system")
     :quality-gates ("plan-artifact" "watch-once-artifact" "flake-check")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "isolation-and-cps"
     :status "implemented"
     :summary "Subprocess isolation for crash/FFI boundaries and thunk-based CPS helpers for async-style test flows."
     :public-apis ("it-isolated" "expect-poll")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "artifact-schemas"
     :status "implemented"
     :summary "Artifact schema metadata defines machine-readable contracts for AI metadata, JSON results, JSONL events, and plan outputs."
     :public-apis ("reporter-artifact-schemas" "framework-metadata")
     :quality-gates ("ai-metadata-artifact" "json-results-artifact"
                     "jsonl-events-artifact" "plan-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "sequence-ordering"
     :status "implemented"
     :summary "Sequence-aware execution preserves stable listing and plan semantics while allowing explicit run-order control."
     :public-apis ("run" "run-all" "list-tests" "collect-test-plan")
     :quality-gates ("plan-artifact" "filtered-smoke" "flake-check")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "retry"
     :status "implemented"
     :summary "Retry controls surface per-test retry metadata and runner entrypoints that preserve retry behavior in artifacts."
     :public-apis ("retry-test" "run" "run-all" "list-tests")
     :quality-gates ("plan-artifact" "cli-json-results" "flake-check")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "timeout"
     :status "implemented"
     :summary "Timeout declarations and runner integration enforce bounded execution and expose timeout policy through metadata."
     :public-apis ("test-timeout" "test-timeout-ms" "run" "run-all"
                   "list-tests")
     :quality-gates ("plan-artifact" "cli-json-results" "flake-check")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "mop-architecture-assertions"
     :status "implemented"
     :summary "MOP-aware matcher metadata documents architecture assertions for slots and specialized methods."
     :public-apis ("list-matchers" "matcher-metadata")
     :quality-gates ("flake-check" "ai-metadata-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "logic-test-plan"
     :status "implemented"
     :summary "Logic-oriented test plan collection and query APIs expose analyzable execution facts before a suite runs."
     :public-apis ("collect-test-plan" "query-test-plan" "test-plan-facts"
                   "test-plan-where")
     :quality-gates ("plan-artifact" "flake-check")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "ai-discovery-metadata"
     :status "implemented"
     :summary "Machine-readable CLI discovery, package exports, matcher metadata, mutation operators, and quality gates."
     :public-apis ("reporter-artifact-schemas" "framework-metadata"
                   "list-matchers" "list-mutation-operators")
     :quality-gates ("ai-metadata-artifact" "flake-check")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "public-package-exports"
     :status "implemented"
     :summary "Package export metadata exposes the supported public API surface for both core and CLI packages."
     :public-apis ("framework-metadata" "list-matchers"
                   "list-mutation-operators")
     :quality-gates ("ai-metadata-artifact" "flake-check")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "cps-continuation-helpers"
     :status "implemented"
     :summary "Continuation helpers bridge thunk-based CPS flows with polling assertions."
     :public-apis ("with-continuation-result" "with-continuation-values"
                   "expect-poll")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/ai-contract.md"))
    (:name "time-travel-debugging"
     :status "implemented"
     :summary "An execution journal records a chronological timeline of assertions, mock calls, fixture hooks, property-shrink steps, and notes for each test attempt, surfaced through the spec and JSON reporters; record-journal-frame and the eql-specialized journal-frame-line-for-kind generic function let callers extend the timeline with their own frame kinds and renderers, and journal-frame-from-plist rebuilds a saved sexp timeline for offline analysis."
     :public-apis ("*journal-enabled*" "journal-note" "with-execution-journal"
                   "record-journal-frame" "journal-frame-line-for-kind"
                   "journal-frame-from-plist" "journal-frames-from-plists")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/time-travel-debugging.md"))
    (:name "deterministic-replay"
     :status "implemented"
     :summary "Per-test random seeding makes CL:RANDOM reproducible and order-independent, with recorded replay seeds and single-test replay for isolating failures."
     :public-apis ("*test-random-seed*" "replay-test")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/time-travel-debugging.md"))
    (:name "soft-assertions"
     :status "implemented"
     :summary "with-soft-assertions runs every expectation in a block and reports all failures together instead of stopping at the first."
     :public-apis ("with-soft-assertions")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/assertions.md"))
    (:name "interactive-breakpoints"
     :status "implemented"
     :summary "A journal frame index or predicate signals journal-breakpoint-hit mid-test, dropping into a live debugger (or a handler-bind-driven programmatic hook) with the test's dynamic environment intact, pairing with journal-diff to land exactly on a divergence."
     :public-apis ("*journal-breakpoint*" "journal-breakpoint-hit"
                   "journal-breakpoint-hit-frame")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/time-travel-debugging.md"))
    (:name "journal-logic-queries"
     :status "implemented"
     :summary "journal-facts adapts a time-travel timeline into the same relation-fact shape as test-plan-facts, so journal-where queries assertion, mock-call, hook, shrink-step, and note frames with the same Prolog-style engine and rule composition as test-plan-where."
     :public-apis ("journal-facts" "journal-where" "query-journal")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/src/time-travel-debugging.md" "docs/src/logic-programming.md"))))
