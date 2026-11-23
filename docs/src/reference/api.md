# API Reference

This page lists the public APIs exported by `cl-weave`, `cl-weave/cli`,
`cl-weave/metadata`, and `cl-weave/spec`, grouped by concept. The `cl-weave` groups match the sections
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

The package `cl-weave/spec`, from the separate ASDF system of the same name,
is listed in the "Specification checking" section below, after "Logic queries".
It is not part of the `cl-weave` export inventory.

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

`benchmark`, `benchmark-scaling-within-p`, `measure`, `benchmark-result`,
`benchmark-result-iterations`,
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

## Specification checking (`cl-weave/spec`)

TLA+-style specifications: declare constants, variables, an initial state,
actions and properties, then explore the state space exhaustively or randomly,
check liveness, reduce symmetric states, check refinement between two
specifications, and compare an implementation with a specification, either
sequentially or under concurrency. See
[Specification Checking](../guide/specification-checking.md).

These symbols live in the package `cl-weave/spec`, which belongs to the separate
ASDF system `cl-weave/spec`. Load it with `(asdf:load-system "cl-weave/spec")`.
The system depends on `cl-weave` and adds no export to it, so none of these
symbols are exported from `cl-weave`, and none appear in the `:package-exports`
metadata of `framework-metadata`, which covers `cl-weave`, `cl-weave/metadata`
and `cl-weave/cli` only. Import the symbols you use with `:import-from`, or
qualify them with `cl-weave/spec:`.

Every search has finite default limits, and a search that reaches a limit is
reported as truncated, not as a pass; see [Results](#results-traces-and-limits)
below.

### Specification DSL

`specification` returns a `spec`. `defspec` defines a function that returns one,
with each constant as a keyword parameter.

```lisp
(specification name (constant-or-binding ...) clause ...)  ; => spec
(defspec name (constant-or-binding ...) clause ...)        ; defines (name &key constant ...)
(next variable)                                            ; value in the next state
```

A constant is `symbol` or `(symbol default-form)`. Inside guards, updates,
outputs, invariants and predicates, each state variable and each constant is a
lexical variable that holds its current value. `next` is valid only in
`:output` and `:action-property` forms. A malformed clause signals
`spec-definition-error` at macroexpansion time.

| Clause | Form |
| --- | --- |
| `:variables` | `(:variables variable ...)`. Required, at most once. |
| `:init` | `(:init (variable form) ...)`. Required, at most once. Each variable appears exactly once. `form` may be `(:in domain-form)`, where `domain-form` returns a list; one initial state is produced for each combination. |
| `:action` | `(:action name clause ...)` with clauses `(:for (parameter domain-form) ...)`, `(:guard form ...)`, `(:next (variable form) ...)` and `(:output form ...)`, each at most once. A later `:for` domain may use earlier parameters. A variable not listed in `:next` is unchanged. |
| `:invariant` | `(:invariant name form)` |
| `:action-property` | `(:action-property name form)`. `form` may use `(next variable)`. A step that leaves every variable unchanged satisfies it. |
| `:temporal` | `(:temporal name (kind predicate [consequent]))`. `kind` is `:always`, `:eventually`, `:infinitely-often`, `:eventually-always` or `:leads-to`; `consequent` is required for `:leads-to` and forbidden otherwise. |
| `:fairness` | `(:fairness (:weak action-name ...) (:strong action-name ...))` |
| `:symmetry` | `(:symmetry constant-name ...)` |
| `:deadlock-check` | `(:deadlock-check form)`. `form` is evaluated when the specification is built; a false value disables the deadlock check. |

Domains are lists. A value-model set is not a list: pass
`(spec-set-elements set)` to `:in` and `:for`.

### Specification objects

`make-spec` builds and validates a `spec` from components, which is what the
DSL expands into.

```lisp
(make-spec &key name constants variables init actions invariants
                action-properties temporal-properties fairness-conditions
                symmetry (check-deadlock t))
(make-spec-action &key name params guard update output)
(make-spec-invariant &key name predicate)
(make-spec-action-property &key name relation)
(make-spec-temporal-property &key name kind predicate consequent)
(make-spec-fairness-condition &key kind action)
(spec-constant spec name)
(spec-find-action spec name)
```

`constants` is a property list, `variables` a list of symbols, `symmetry` a list
of constant names, and `params` a list of `(symbol domain-function)`. Property
names are unique symbols across invariants, action properties and temporal
properties. `spec-constant` signals `spec-definition-error` for an unknown
constant; `spec-find-action` returns `nil` for an unknown action.

User-supplied functions follow one calling convention. A state is a property
list of every variable, in declaration order, and `params` are the quantified
values of the action.

| Component | Lambda list | Returns |
| --- | --- | --- |
| `init` | `()` | list of state property lists |
| action parameter domain | `(state . earlier-params)` | list of values |
| `guard` | `(state . params)` | generalized boolean |
| `update` | `(state . params)` | property list of the changed variables |
| `output` | `(state next-state . params)` | any `equal`-comparable value |
| invariant `predicate` | `(state)` | generalized boolean |
| action property `relation` | `(state next-state)` | generalized boolean |
| temporal `predicate`, `consequent` | `(state)` | generalized boolean |

Types, each with a `-p` predicate: `spec`, `spec-action`, `spec-invariant`,
`spec-action-property`, `spec-temporal-property`, `spec-fairness-condition`.

`spec-name`, `spec-constants`, `spec-variables`, `spec-init`, `spec-actions`,
`spec-invariants`, `spec-action-properties`, `spec-temporal-properties`,
`spec-fairness-conditions`, `spec-symmetry`, `spec-check-deadlock`,
`spec-action-name`, `spec-action-params`, `spec-action-guard`,
`spec-action-update`, `spec-action-output`, `spec-invariant-name`,
`spec-invariant-predicate`, `spec-action-property-name`,
`spec-action-property-relation`, `spec-temporal-property-name`,
`spec-temporal-property-kind`, `spec-temporal-property-predicate`,
`spec-temporal-property-consequent`, `spec-fairness-condition-kind`,
`spec-fairness-condition-action`

### States and successors

States compare with `equal`. A state variable may hold symbols, numbers,
characters, strings, bit vectors, pathnames, conses of those, and the
[value model](#value-model) constructors. Hash tables, other arrays, structures
and closures signal `spec-state-error`, because `equal` compares them by
identity.

```lisp
(make-state spec plist)                          ; canonical state
(spec-initial-states spec)                       ; => list of states
(spec-successors spec state)                     ; => list of spec-transition
(spec-deadlock-p spec state)
(spec-check-invariants spec state)               ; => names of violated invariants
(spec-check-action-properties spec state next-state)
(state-ref state variable)
(state-fingerprint value)                        ; => non-negative integer
(validate-comparable-value value &optional variable)
(make-state-table)
(state-table-ref table key)                      ; => (values value found-p); setf-able
(state-table-count table)
(map-state-table function table)                 ; insertion order
```

`spec-successors` visits actions in declaration order and each quantifier domain
in list order, so a search is reproducible. A transition that leaves the state
unchanged is returned like any other; stuttering steps are implicit.
`spec-initial-states` signals `spec-definition-error` when `init` returns no
state. `state-table-p` tests for a state table.

### Value model

Sets, functions, records and sequences are plain Lisp data in a canonical form,
so equal values are `equal` regardless of how they were built.

```lisp
(make-spec-set elements)           (spec-set &rest elements)
(spec-set-elements set)            (spec-set-size set)
(spec-set-member-p element set)    (spec-subset-p a b)
(spec-set-union a b)               (spec-set-intersection a b)
(spec-set-difference a b)          (spec-powerset set)
(spec-set-filter predicate set)    (spec-set-map function set)
(spec-set-of expression :for variable :in set [:when condition])

(make-spec-function pairs)         ; pairs: list of (key . value)
(spec-function-over domain function)  ; domain is a set
(spec-function-domain function)    (spec-function-pairs function)
(spec-function-apply function argument)
(spec-function-except function argument value)

(make-spec-record &rest field-value-pairs)
(spec-record-ref record field)     (spec-record-except record field value)
(spec-record-fields record)

(make-spec-sequence elements)      (spec-sequence &rest elements)
(spec-sequence-elements sequence)  (spec-sequence-length sequence)
(spec-sequence-ref sequence index) ; zero-based
(spec-sequence-concat a b)

(value< a b)                       ; total order used to canonicalize sets
(map-value-atoms function value)
```

Predicates: `spec-set-p`, `spec-function-p`, `spec-record-p`,
`spec-sequence-p`. An operation applied outside its domain, such as a missing
function key, a missing record field, an out-of-range index, a duplicate key,
or a power set of too large a set, signals `spec-value-error`.

### Exhaustive exploration

```lisp
(explore-spec spec &key (max-states *default-max-states*)
                        (max-depth *default-max-depth*)
                        allow-bounded
                        (check-deadlock :spec)
                        (symmetry t)
                        (temporal :all)
                        initial-check step-check)   ; => spec-result
```

Breadth-first search, so a counterexample trace is the shortest one. It checks
invariants when a state is first found, action properties on every transition,
and deadlock when a state is expanded. `max-states` and `max-depth` must be
positive integers.

- `check-deadlock`: `:spec` follows `spec-check-deadlock`; `t` and `nil`
  override it.
- `symmetry`: when true, states are compared through `spec-state-canonicalizer`
  while traces keep the real states.
- `temporal`: `:all`, `nil`, or a list of declared temporal property names.
  Temporal properties are checked on the complete state graph, only when the
  search was not truncated and found no safety violation. Requesting them
  together with an active symmetry reduction signals `spec-configuration-error`;
  pass `:symmetry nil` or `:temporal nil`.
- `initial-check` and `step-check` are extension points that `check-refinement`
  uses. Each is called with an initial state or a `spec-transition` and returns
  `nil` or a `spec-violation` without a trace, which the search fills in.

### Random exploration

```lisp
(simulate-spec spec &key runs max-steps seed temporal allow-bounded
                         (check-deadlock :spec))        ; => spec-result
(generate-action-sequence spec rng &key max-steps on-step)
                                  ; => (values initial-state calls)
(replay-action-sequence spec initial-state calls)
                                  ; => (values trace valid-p failed-index)
(shrink-action-sequence spec initial-state calls still-fails-p
                        &key max-steps)                 ; => (values calls steps)
```

`simulate-spec` runs `runs` random walks of at most `max-steps` steps. `runs`
defaults to the core property test count, `seed` to the core property seed, and
`max-steps` to `*default-max-simulation-steps*`. Run `n` uses the seed plus `n`,
so a seed reproduces a failure. On a violation it shrinks the action sequence and
adds `:seed`, `:case-index`, `:original-length`, `:shrunk-length` and
`:original-trace` to the violation detail. Random search cannot decide liveness:
a non-`nil` `temporal` signals `spec-configuration-error`.

- `generate-action-sequence` returns an initial state and `calls`, a list of
  `(action-name . params)`. `rng` is a core property-test random state, which
  `simulate-spec` derives from the seed. `on-step` is called with the state
  and the transition after each step, and with the initial state and `nil`
  first; a true return value stops the walk.
- `replay-action-sequence` returns a trace, which is a list of `trace-step`.
  When a call is not enabled, `valid-p` is false, `failed-index` is its
  position, and the trace stops before it.
- `shrink-action-sequence` removes calls while `still-fails-p`, a predicate on
  the replayed trace, stays true. `max-steps` defaults to the core shrink budget.
  When the budget runs out it signals `property-shrink-limit` with the
  `accept-current` restart, as property shrinking does.

### Liveness and symmetry

```lisp
(check-temporal-properties spec graph &key (properties :all))
                                  ; => list of spec-violation
(spec-state-canonicalizer spec)   ; => function of a state, or nil
```

`check-temporal-properties` takes the `state-graph` that `explore-spec` builds
and returns one `:temporal` violation per failing property, each with a `lasso`
trace. A graph whose `state-graph-complete-p` is false, or an unknown property
name, signals `spec-configuration-error`. Weak and strong fairness conditions
declared on the specification restrict which behaviors count.

`spec-state-canonicalizer` returns a function that maps a state to a canonical
representative of its symmetry class, or `nil` when `spec-symmetry` is empty.
Symmetric constants are sets or lists of atoms other than `nil`; any other value
signals `spec-definition-error`. Symmetry reduction is sound only when every
invariant is invariant under permuting those atoms, so a predicate must not name
a specific element or depend on a number shared with another variable.

### Refinement

```lisp
(check-refinement low high mapping &key (max-states *default-max-states*)
                                        (max-depth *default-max-depth*)
                                        allow-bounded (temporal :all))
                                  ; => spec-result
```

`mapping` takes a state of `low` and returns a property list of the variables of
`high`. Every initial state of `low` must map to an initial state of `high`, and
every step of `low` must map to a step of `high` or to a stuttering step.
Violations have kind `:refinement`. `temporal` names temporal properties of
`high`; they are checked on the complete state graph of `low` under the fairness
conditions of `low`. The fairness conditions of `high` are not checked as
obligations.

### Conformance checking

```lisp
(check-sequential-conformance spec &key reset operations abstraction
                                        (mode :random) seed runs max-steps
                                        depth max-states allow-bounded)
                                  ; => spec-result

(check-linearizability spec &key reset operations threads
                                 operations-per-thread runs seed budget
                                 allow-bounded)
                                  ; => spec-result
(linearizable-history-p spec history &key budget)
                                  ; => (values linearizable-p longest-prefix
                                  ;            budget-exceeded-p)
(make-history-operation &key id thread action params output invoked returned)
```

Arguments of the conformance checks:

- `reset`: a function of no arguments that returns a fresh implementation.
- `operations`: an alist from action name to a function that takes the
  implementation followed by the action's params and returns the output. Every
  action of the specification needs an entry, or `spec-configuration-error` is
  signalled.
- `abstraction`: a function from the implementation to a state property list.
  Only `check-sequential-conformance` uses it.

`check-sequential-conformance` drives the implementation through action
sequences of the specification and compares the abstracted state, and the output
when the action declares one, after each step. `mode` is `:random` or `:tree`.
`:random` uses `seed`, `runs` and `max-steps`. `:tree` explores the
specification breadth-first and per state, to `depth` and within `max-states`,
and needs a deterministic `reset`. It runs every transition on a fresh
implementation from `reset`, including a transition that reaches an already
known state, but it explores the successors of a state once, from the first path
that reaches it. An implementation that keeps history internally can therefore
have a mismatch that goes unnoticed, because the successors of a state reached by
a second path are not tried. When a `reset` returns a different valid initial
state than the first one, `:tree` signals `spec-configuration-error`.

A violation has kind `:conformance` and reports `:expected`, `:actual` and
`:what` (`:state` or `:output`). It is shrunk, except a violation at the initial
state (`:step` 0), which is reported as found. An error signalled by an
operation is reported as a violation, not swallowed.

`check-linearizability` runs `operations-per-thread` operations on each of
`threads` threads against one implementation from `reset`, records a history,
and checks that some total order consistent with real time is a valid behavior
of the specification. `linearizable-history-p` makes the same decision on a
history you supply, runs no threads, and counts visited search nodes against
`budget`, which defaults to `*default-linearization-budget*`. A history is a list
of `history-operation`, where `invoked` and `returned` are integers from one
shared increasing counter. Every action of a specification used here must be
enabled in every reachable state; otherwise a linearizable run can be reported as
a failure. `check-linearizability` requires the `:concurrency` platform
capability; see [Runtime Support](runtime-support.md). Thread scheduling is not
reproducible, so a seed fixes the generated operations only.

Predicate and accessors: `history-operation-p`, `history-operation-id`,
`history-operation-thread`, `history-operation-action`,
`history-operation-params`, `history-operation-output`,
`history-operation-invoked`, `history-operation-returned`

### Results, traces and limits

Every check returns a `spec-result`; `spec-result-passed-p` decides whether it
passed.

```lisp
(spec-result-passed-p result)
```

It is true when there is no violation and the search was not truncated, or it
was truncated with `allow-bounded` set and no temporal property requested. A
temporal property never passes a truncated search.

`spec-result`, `make-spec-result`, `spec-result-p`, `spec-result-spec-name`,
`spec-result-mode`, `spec-result-violation`, `spec-result-states-found`,
`spec-result-depth-reached`, `spec-result-truncated`,
`spec-result-truncation-reason`, `spec-result-liveness-requested`,
`spec-result-allow-bounded`, `spec-result-checked-properties`,
`spec-result-limits`, `spec-result-statistics`

- `mode` is `:exhaustive`, `:random`, `:refinement`, `:sequential-conformance`
  or `:linearizability`.
- `truncation-reason` is `:max-states`, `:max-depth` or `:budget`.
- `checked-properties` lists the property names examined, in the order
  invariants, action properties, temporal properties, then `:deadlock`.
- `limits` and `statistics` are property lists whose keys depend on the check.

A violation is a `spec-violation` with `kind`, `property`, `trace` and `detail`.
`trace` is a list of `trace-step`, or a `lasso` for `:temporal`. The first step
of a trace has no action.

| `kind` | `property` | `detail` keys |
| --- | --- | --- |
| `:invariant` | invariant name | `:state` |
| `:action-property` | action property name | `:from` `:to` `:action` `:params` |
| `:deadlock` | `nil` | `:state` |
| `:temporal` | temporal property name | `:kind` |
| `:refinement` | `nil` | `:phase` (`:init` or `:step`) `:low-from` `:low-to` `:mapped-from` `:mapped-to` |
| `:conformance` | `nil` | `:step` `:action` `:params` `:expected` `:actual` `:what`, `:original-trace` when the violation was shrunk, and `:condition` when an operation signalled |
| `:linearizability` | `nil` | `:history` `:longest-prefix` |

Supporting types, each with a `-p` predicate and a `make-` constructor:
`spec-transition` (`spec-transition-action`, `-params`, `-from`, `-to`),
`trace-step` (`trace-step-action`, `-params`, `-state`), `lasso` (`lasso-prefix`,
`lasso-cycle`), `spec-violation` (`spec-violation-kind`, `-property`, `-trace`,
`-detail`), and `state-graph` (`state-graph-spec`, `-initial-states`, `-edges`,
`-complete-p`).

Default limits, each a special variable that you may rebind:
`*default-max-states*` bounds the distinct states `explore-spec` and the related
checks discover, `*default-max-depth*` the path length they follow,
`*default-max-simulation-steps*` the steps of one random run, and
`*default-linearization-budget*` the search nodes `linearizable-history-p`
visits.

### Reporting and registration

```lisp
(report-spec-result result &key form)      ; => result, or signals
(spec-result-payload result &key form)     ; => property list
(format-spec-trace trace &optional stream) ; => string when stream is nil
```

`report-spec-result` returns `result` when `spec-result-passed-p` is true. It
records `:spec-stats`, `:spec-step` and `:spec-history` frames in the execution
journal when the journal is enabled; see
[Time-Travel Debugging](../guide/time-travel-debugging.md). When the result did
not pass, it signals the core `assertion-failure` with matcher `:spec`, so
`with-soft-assertions` collects it like any other failed expectation.
`spec-result-payload` returns the data of that failure: `:seed`, `:case-index`,
`:values`, `:minimal`, `:condition`, `:spec`, `:mode`, `:kind`, `:property` and
`:stats`. `format-spec-trace` accepts a list of `trace-step` or a `lasso` and
abbreviates long traces and long values. `form` is the source form of the check,
which `report-spec-result` records in the failure detail; `spec-result-payload`
accepts and ignores it.

The registration macros wrap one check form in `report-spec-result` and register
it through `it`, `it-only`, `it-skip` and `it-todo`, so focus, tags, retry,
timeout, filtering and sharding behave as they do for those macros.

```lisp
(it-spec name [options-plist] check-form)
(it-spec-only name [options-plist] check-form)
(it-spec-skip name [reason] [options-plist] check-form)
(it-spec-todo name [reason] [options-plist] check-form)
```

`check-form` is a single call such as `explore-spec`, `simulate-spec`,
`check-refinement`, `check-sequential-conformance` or `check-linearizability`.
`it-spec-skip` and `it-spec-todo` count the check form but never expand or
evaluate it.

### Conditions

`spec-error` is the base class and has the reader `spec-error-message`.
`spec-definition-error` signals a malformed specification, `spec-configuration-error`
a check requested with options it cannot honor (signalled before exploration
begins for a problem detected up front, and also during a `:tree` conformance
check when a `reset` returns a different valid initial state), `spec-value-error` a value-model operation outside its domain, and
`spec-state-error` a state variable that `equal` cannot compare, with readers
`spec-state-error-variable` and `spec-state-error-value`. The other
subclasses add no slots.

`spec-error`, `spec-error-message`, `spec-definition-error`,
`spec-configuration-error`, `spec-value-error`, `spec-state-error`,
`spec-state-error-variable`, `spec-state-error-value`

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

The `sb-cover` integration, aggregate and per-file statistics, uncovered form
locations, and the conditions raised when coverage is unavailable or measures
no executable forms. See
[Reporters and CI](../guide/reporters-and-ci.md).

`coverage-file-statistics`, `coverage-no-data`,
`coverage-no-data-exclude-pathnames`, `coverage-no-data-include-pathnames`,
`coverage-statistics`, `coverage-support-available-p`,
`coverage-uncovered-form-locations`, `reset-coverage`, `save-coverage`,
`coverage-unavailable`, `coverage-unavailable-reason`

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
For a `"run"` command, `run-options` accepts the keyword arguments of
`cl-weave:run-all`:

```lisp
:reporter :stream :name-filter :location-filter :test-path-filter
:include-tags :exclude-tags :shard :order :seed :bail :retry
:timeout-ms :max-workers :coverage :coverage-output
:coverage-report-directory :coverage-include-pathnames
:coverage-exclude-pathnames :coverage-minimum-expression
:coverage-minimum-branch :pass-with-no-tests :coverage-reset
:on-test-attempt-complete
```

For `"run"`, any other key reaches `run-all` and signals its normal
keyword-argument error. Other commands use their own option handling:
`"list"` forwards only `:reporter`, `:name-filter`, `:shard`, `:order`, `:seed`,
`:retry`, `:timeout-ms`, and `:stream` to `list-tests`; other keys are not
passed to `list-tests`. `"watch"` forwards the merged plist to `watch-system`,
which signals its normal keyword-argument error for unsupported keys. Doctor
and metadata translate only `:reporter`,
`:name-filter`, `:shard`, `:order`, `:seed`, `:bail`, `:coverage`,
`:coverage-output`, `:coverage-report-directory`,
`:coverage-include-pathnames`, `:coverage-exclude-pathnames`,
`:coverage-minimum-expression`, `:coverage-minimum-branch`,
`:pass-with-no-tests`, `:retry`, `:timeout-ms`, and `:max-workers` to CLI
option fields; other keys are ignored, and neither command forwards
`run-options` to `run-all`.

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
path is configured.

## Dynamic-state helpers

Scoped restoration of bindings, function definitions and hash-table contents,
so a test that mutates global state cannot leak into the next one. See
[Adoption Guide](../guide/adoption.md).

`with-restored-binding`, `with-restored-bindings`, `with-replaced-function`,
`with-restored-hash-table`, `with-cleared-hash-table`
