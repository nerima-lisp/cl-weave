# Specification Checking

`cl-weave/spec` brings the working method of TLA+ to Common Lisp. You describe a
system as a specification: constants, variables, the initial states, and named
actions that move the system from one state to the next. The checkers then
explore the states the specification can reach and report a counterexample, a
sequence of steps that breaks a property you declared. Exhaustive exploration
reports a shortest counterexample for a safety property. Random exploration and
conformance checking report a shrunk sequence, which is not guaranteed to be the
shortest.

Use it where a plain example test cannot cover the interleavings or the state
space:

- **State machines and protocols** where "every reachable state satisfies
  this invariant" is the real requirement.
- **"Eventually" requirements**, such as "a waiting process is eventually
  served", which no finite test run can confirm.
- **Implementations that must match a model**, either one thread at a time or
  under concurrent calls.

The specification is plain Lisp data and functions. The macros only carry
syntax, as `logic-program` does in [Logic Programming](logic-programming.md),
so a specification can also be built by computation. For generated example
inputs without a model, see [Property Testing](property-testing.md).

## Loading the system

`cl-weave/spec` is a separate ASDF system, defined in the same repository as
`cl-weave` and released with the same version. Loading `cl-weave` alone does not
create the `cl-weave/spec` package. Using the two systems at different versions
is unsupported.

All examples on this page are evaluated in order, in one image, and each
`;; =>` comment is the value the form returned. Printed output appears as
`;; |` lines.

```lisp
(asdf:load-system "cl-weave/spec")

(defpackage #:my-specs
  (:use #:cl #:cl-weave/spec))

(in-package #:my-specs)
```

## Writing a specification

`defspec` defines a function that returns a specification, and `specification`
is the same form as an expression. Constants become keyword parameters of the
defined function, so a model parameter can be overridden per call.

```lisp
(defspec counter ((limit 3))
  (:variables x)
  (:init (x 0))
  (:action inc
    (:guard (< x limit))
    (:next (x (1+ x))))
  (:invariant bounded (<= x limit))
  (:action-property monotone (>= (next x) x))
  (:deadlock-check nil))
```

The counter stops at `limit`, where no action is enabled. The default deadlock
check would report that state, so this specification turns the check off.

The clauses are:

| Clause | Meaning |
| --- | --- |
| `(:variables v ...)` | The state variables. Required, once. |
| `(:init (v form) ...)` | The initial state. `(v (:in domain-form))` makes one initial state per element of the list. Required, once. |
| `(:action name clause...)` | A named action with at most one each of the `:for`, `:guard`, `:next` and `:output` clauses. |
| `(:invariant name form)` | A predicate that must hold in every reachable state. |
| `(:action-property name form)` | A predicate over a step, written with `(next v)`. |
| `(:temporal name (kind P [Q]))` | A liveness formula. See [Liveness and fairness](#liveness-and-fairness). |
| `(:fairness (:weak action...) (:strong action...))` | Fairness conditions on actions. |
| `(:symmetry constant...)` | Constants whose elements are interchangeable. See [Symmetry](#symmetry). |
| `(:deadlock-check nil)` | Turns the deadlock check off for this specification. |

Inside guards, updates, outputs and predicates, each state variable and each
constant is an ordinary lexical variable holding its current value. In an
action, the `:for` clause quantifies over lists (`\E x \in S` in TLA+). An action
takes exactly one `:for` clause. To quantify over several parameters, write one
`(parameter domain-form)` binding per parameter inside that clause. A later
domain can use an earlier parameter. `:next` lists only the variables that
change, and every variable not listed is unchanged. An action without `:guard` is
always enabled, one without `:next` changes nothing, and one without `:output`
returns no output. The `next` form reads a variable in the next state, and it is
available only in `:output` and `:action-property` forms.

Two rules from TLA+ apply without being written. The next-state relation is the
disjunction of the actions, and a stuttering step, which leaves every variable
unchanged, is always allowed. An action is enabled in a state when its guard holds
for some choice of parameters. Stuttering does not count. [Safety](#safety)
defines deadlock.

```lisp
(spec-initial-states (counter))
;; => ((X 0))
(mapcar #'spec-transition-to
        (spec-successors (counter) (first (spec-initial-states (counter)))))
;; => ((X 1))
(let ((result (explore-spec (counter))))
  (list :states (spec-result-states-found result)
        :depth (spec-result-depth-reached result)
        :passed (spec-result-passed-p result)
        :checked (spec-result-checked-properties result)))
;; => (:STATES 4 :DEPTH 3 :PASSED T :CHECKED (BOUNDED MONOTONE))
(spec-result-states-found (explore-spec (counter :limit 5)))
;; => 6
```

The next specification passes a token between processes with one action. The
`:for` clause of `pass` binds `source` and `target`, and the domain of `target`
uses `source`, so a process never passes the token to itself.

```lisp
(defspec token-passing ((procs '(p1 p2 p3)))
  (:variables holder)
  (:init (holder 'p1))
  (:action pass
    (:for (source procs) (target (remove source procs)))
    (:guard (eq holder source))
    (:next (holder target)))
  (:deadlock-check nil))

(mapcar (lambda (transition)
          (list (spec-transition-action transition)
                (spec-transition-params transition)))
        (spec-successors (token-passing)
                         (first (spec-initial-states (token-passing)))))
;; => ((PASS (P1 P2)) (PASS (P1 P3)))
(spec-result-states-found (explore-spec (token-passing)))
;; => 3
```

A syntax error in the macros, such as an unknown clause, a repeated clause in one
action or a variable assigned twice, signals `spec-definition-error` when the
form is expanded.

### The function API

The macros expand into calls of `make-spec`, `make-spec-action`,
`make-spec-invariant`, `make-spec-action-property`, `make-spec-temporal-property`
and `make-spec-fairness-condition`. Call them directly when the specification is
computed, for example one action per element of a list. The keywords and the
signature of each function you supply are in [Specification
objects](../reference/api.md#specification-objects). They take the state first,
then the quantified parameters, and `state-ref` reads a variable from a state.
The next example builds one action per step size.

```lisp
(defun make-stepper (step-sizes limit)
  (make-spec
   :name 'stepper
   :constants (list 'limit limit)
   :variables '(x)
   :init (lambda () (list (list 'x 0)))
   :actions (mapcar (lambda (size)
                      (make-spec-action
                       :name (intern (format nil "STEP-~D" size))
                       :guard (lambda (state) (<= (+ (state-ref state 'x) size) limit))
                       :update (lambda (state)
                                 (list 'x (+ (state-ref state 'x) size)))))
                    step-sizes)
   :invariants (list (make-spec-invariant
                      :name 'bounded
                      :predicate (lambda (state) (<= (state-ref state 'x) limit))))
   :check-deadlock nil))
```

```lisp
(let ((result (explore-spec (make-stepper '(1 2) 4))))
  (list :states (spec-result-states-found result)
        :passed (spec-result-passed-p result)))
;; => (:STATES 5 :PASSED T)
(mapcar #'spec-action-name (spec-actions (make-stepper '(1 2 5) 4)))
;; => (STEP-1 STEP-2 STEP-5)
```

## Values and states

A state is a property list of the variables in declaration order, such as
`(X 0)`. Two states are the same state exactly when they are `equal`, so
everything a state holds must compare structurally under `equal`. Lists,
numbers, symbols, characters, strings, bit vectors and pathnames qualify.

Sets, functions (finite maps from keys to values, not Lisp functions), records and
sequences have no `equal`-stable representation in Lisp, so `cl-weave/spec`
provides them as immutable values with a canonical form. Two sets with the same elements are `equal` whatever order
they were built in, and they have the same `state-fingerprint`. The printed form
of these values is internal. Read them through the accessors.

```lisp
(equal (spec-set 3 1 2) (spec-set 2 3 1 1))
;; => T
(spec-set-elements (spec-set-union (spec-set 1 2) (spec-set 2 3)))
;; => (1 2 3)
(spec-set-member-p 2 (spec-set 1 2))
;; => T
(mapcar #'spec-set-elements
        (spec-set-elements (spec-powerset (spec-set 1 2))))
;; => (NIL (1) (1 2) (2))
(spec-set-elements (spec-set-of (* n n) :for n :in (spec-set 1 2 3) :when (oddp n)))
;; => (1 9)
```

Functions, records and sequences follow the same pattern.

```lisp
(let ((f (spec-function-over (spec-set :a :b)
                             (lambda (key) (if (eq key :a) 0 1)))))
  (list (spec-function-apply f :a)
        (spec-function-pairs (spec-function-except f :b 9))))
;; => (0 ((:A . 0) (:B . 9)))

(let ((record (make-spec-record 'name "ann" 'age 30)))
  (list (spec-record-ref record 'age)
        (spec-record-ref (spec-record-except record 'age 31) 'age)))
;; => (30 31)

(let ((items (spec-sequence-concat (spec-sequence 1 2) (spec-sequence 3))))
  (list (spec-sequence-length items)
        (spec-sequence-ref items 0)
        (spec-sequence-elements items)))
;; => (3 1 (1 2 3))
```

The other operations are listed in [Value
model](../reference/api.md#value-model). An error in a value operation, such as
applying a function outside its domain, signals `spec-value-error`.

Hash tables, other arrays, structures, closures and CLOS instances are rejected,
because `equal` compares them by identity and two states holding equal-looking
copies would be counted as different. The error names the variable.

```lisp
(defspec cache-spec ()
  (:variables cache)
  (:init (cache (make-hash-table)))
  (:action noop (:guard t)))

(handler-case (explore-spec (cache-spec))
  (spec-state-error (condition)
    (list (type-of condition) (spec-state-error-variable condition))))
;; => (SPEC-STATE-ERROR CACHE)
```

The initial states are checked before the search starts. A value that first
appears in a successor state is rejected when that state is generated.

## Exhaustive exploration

`explore-spec` searches the states reachable from the initial states
breadth-first, so a safety counterexample has the shortest possible length. The
next specification has two processes, and `checked-lock` switches the lock check
in `enter` on and off.

```lisp
(defun set-pc (pc proc value)
  (mapcar (lambda (entry) (if (eq (car entry) proc) (cons proc value) entry))
          pc))

(defspec mutex ((procs '(p1 p2)) (checked-lock t))
  (:variables pc lock)
  (:init (pc (mapcar (lambda (p) (cons p :idle)) procs))
         (lock :free))
  (:action try
    (:for (p procs))
    (:guard (eq (cdr (assoc p pc)) :idle))
    (:next (pc (set-pc pc p :waiting))))
  (:action enter
    (:for (p procs))
    (:guard (and (eq (cdr (assoc p pc)) :waiting)
                 (or (not checked-lock) (eq lock :free))))
    (:next (pc (set-pc pc p :critical))
           (lock p)))
  (:action leave
    (:for (p procs))
    (:guard (eq (cdr (assoc p pc)) :critical))
    (:next (pc (set-pc pc p :idle))
           (lock :free)))
  (:invariant mutual-exclusion
    (<= (count :critical pc :key #'cdr) 1)))
```

The process table is a plain association list. That works here because every
action rewrites it in the same order. [Symmetry](#symmetry) explains when it does
not.

With the lock check, the search covers every reachable state and passes. Without
it, the search stops at the first violation and returns the trace that leads
there.

```lisp
(let ((result (explore-spec (mutex))))
  (list :states (spec-result-states-found result)
        :depth (spec-result-depth-reached result)
        :passed (spec-result-passed-p result)))
;; => (:STATES 8 :DEPTH 3 :PASSED T)

(defvar *broken*
  (explore-spec (mutex :checked-lock nil) :max-states 500 :max-depth 20))

(list (spec-result-passed-p *broken*)
      (spec-violation-kind (spec-result-violation *broken*))
      (spec-violation-property (spec-result-violation *broken*)))
;; => (NIL :INVARIANT MUTUAL-EXCLUSION)

(format-spec-trace (spec-violation-trace (spec-result-violation *broken*))
                   *standard-output*)
;; |   0: NIL NIL => (PC ((P1 . :IDLE) (P2 . :IDLE)) LOCK :FREE)
;; |   1: TRY (P1) => (PC ((P1 . :WAITING) (P2 . :IDLE)) LOCK :FREE)
;; |   2: TRY (P2) => (PC ((P1 . :WAITING) (P2 . :WAITING)) LOCK :FREE)
;; |   3: ENTER (P1) => (PC ((P1 . :CRITICAL) (P2 . :WAITING)) LOCK P1)
;; |   4: ENTER (P2) => (PC ((P1 . :CRITICAL) (P2 . :CRITICAL)) LOCK P2)
```

A trace prints one step per line as `index: action params => state`.
`explore-spec` accepts these keyword arguments:

| Keyword | Meaning |
| --- | --- |
| `:max-states`, `:max-depth` | Search limits. Both must be positive integers. The defaults are finite. See [Truncation and limits](#truncation-and-limits). |
| `:allow-bounded` | Accept a truncated search as a pass. |
| `:check-deadlock` | `:spec` (the default, follow the specification), `t` or `nil`. |
| `:symmetry` | `t` (the default, use the specification's `:symmetry`) or `nil`. |
| `:temporal` | `:all` (the default), a list of property names, or `nil`. |

The result is a `spec-result`. Its accessors are listed in [Results, traces and
limits](../reference/api.md#results-traces-and-limits). A property name that the
specification does not declare signals `spec-configuration-error` before the
search starts.

## Random exploration

`simulate-spec` checks the same specification on randomly chosen action
sequences. It suits specifications whose state space is too large to explore
exhaustively. It checks invariants in every state, action
properties on every step, and deadlock.

The seed and the number of runs follow the property-testing settings, which are
`*property-seed*` and `*property-test-count*`, or the environment variables
`CL_WEAVE_PROPERTY_SEED` and `CL_WEAVE_PROPERTY_TESTS`. The seed is overridden by `:seed`, and `:runs` overrides the run count. The same seed reproduces the same
counterexample. A failing sequence is shrunk: the search removes steps while the
shorter sequence still fails with the same kind of violation on the same
property. The shrink limit is `*property-shrink-max-steps*`, as in [Property
Testing](property-testing.md#controlling-shrinking). Each candidate is recorded as a
`:shrink-step` frame on the [execution journal](time-travel-debugging.md), as
[Watching a Shrink Run](property-testing.md#watching-a-shrink-run) describes.

Shrinking does not guarantee the shortest counterexample. It tries to delete a
block of consecutive steps, largest blocks first, and keeps the first deletion
that still fails. It stops when no block can be deleted, so a different failing
sequence of the same specification could be shorter. The breadth-first search of
`explore-spec` is the way to get a shortest safety counterexample.

```lisp
(let* ((result (simulate-spec (mutex :checked-lock nil)
                              :runs 50 :max-steps 30 :seed 7))
       (violation (spec-result-violation result))
       (detail (spec-violation-detail violation)))
  (list :passed (spec-result-passed-p result)
        :property (spec-violation-property violation)
        :seed (getf detail :seed)
        :case-index (getf detail :case-index)
        :original-length (getf detail :original-length)
        :shrunk-length (getf detail :shrunk-length)))
;; => (:PASSED NIL :PROPERTY MUTUAL-EXCLUSION :SEED 7 :CASE-INDEX 0 :ORIGINAL-LENGTH 19 :SHRUNK-LENGTH 4)
```

The violation records the seed, the zero-based run in which it appeared, and the
number of calls before and after shrinking, so the shrunk trace has four steps
after its initial state. A run without a violation reports its statistics.

```lisp
(let ((result (simulate-spec (mutex) :runs 20 :max-steps 30 :seed 7)))
  (list (spec-result-passed-p result) (spec-result-statistics result)))
;; => (T (:RUNS 20 :STEPS 600 :SEED 7))
```

`replay-action-sequence` runs a list of calls, each written `(action . params)`,
from an initial state. It returns the trace, whether every call was enabled, and
the index of the first call that was not. `generate-action-sequence` and
`shrink-action-sequence` are the two halves that `simulate-spec` combines.

```lisp
(let ((initial (first (spec-initial-states (mutex)))))
  (multiple-value-bind (trace ok-p failed-index)
      (replay-action-sequence (mutex) initial '((try p1) (enter p1) (enter p2)))
    (list (length trace) ok-p failed-index)))
;; => (3 NIL 2)
```

Random exploration cannot decide a liveness property, because a finite random
trace never shows that something happens eventually. Passing `:temporal` signals
`spec-configuration-error` before the first run.

```lisp
(handler-case (simulate-spec (mutex) :temporal '(mutual-exclusion))
  (spec-configuration-error (condition) (spec-error-message condition)))
;; => "Random search cannot check temporal properties."
```

## Safety

Safety properties say that something bad never happens. There are three, and
`explore-spec` and `simulate-spec` both check them:

- **State invariants** (`:invariant`), checked when a state is first discovered.
- **Action properties** (`:action-property`), the TLA+ form `[][A]_vars`, checked
  on every step. A step that changes no variable satisfies the property.
- **Deadlock**, a state in which no action is enabled. A state whose enabled
  actions all lead back to itself is not a deadlock. The check is on by default
  and `(:deadlock-check nil)` or `:check-deadlock nil` turns it off.

```lisp
(defspec countdown ((start 3))
  (:variables n)
  (:init (n start))
  (:action dec
    (:guard (> n 0))
    (:next (n (1- n)))))

(let ((result (explore-spec (countdown))))
  (format-spec-trace (spec-violation-trace (spec-result-violation result))
                     *standard-output*)
  (list (spec-violation-kind (spec-result-violation result))
        (spec-result-passed-p result)))
;; |   0: NIL NIL => (N 3)
;; |   1: DEC NIL => (N 2)
;; |   2: DEC NIL => (N 1)
;; |   3: DEC NIL => (N 0)
;; => (:DEADLOCK NIL)

(spec-result-passed-p (explore-spec (countdown) :check-deadlock nil))
;; => T
```

An action property that a step breaks is reported with the step.

```lisp
(defspec slipping ()
  (:variables x)
  (:init (x 0))
  (:action up (:guard (< x 3)) (:next (x (1+ x))))
  (:action down (:guard (> x 1)) (:next (x (- x 2))))
  (:action-property monotone (>= (next x) x))
  (:deadlock-check nil))

(let* ((result (explore-spec (slipping)))
       (violation (spec-result-violation result)))
  (format-spec-trace (spec-violation-trace violation) *standard-output*)
  (list (spec-violation-kind violation) (spec-violation-property violation)))
;; |   0: NIL NIL => (X 0)
;; |   1: UP NIL => (X 1)
;; |   2: UP NIL => (X 2)
;; |   3: DOWN NIL => (X 0)
;; => (:ACTION-PROPERTY MONOTONE)
```

## Liveness and fairness

Liveness properties say that something good eventually happens. A specification
can declare five forms, and no others. Arbitrary nesting of temporal operators
is not available.

| Form | TLA+ | Meaning |
| --- | --- | --- |
| `(:always P)` | `[]P` | `P` holds in every state. |
| `(:eventually P)` | `<>P` | `P` holds in some state. |
| `(:infinitely-often P)` | `[]<>P` | `P` holds again and again. |
| `(:eventually-always P)` | `<>[]P` | From some point on, `P` always holds. |
| `(:leads-to P Q)` | `P ~> Q` | Whenever `P` holds, `Q` holds then or later. |

A property is judged against the behaviors that satisfy the declared fairness.
Without fairness, a system may stay in a state forever, so "eventually" fails.
`(:weak a)` is weak fairness: if action `a` stays enabled, it is eventually
taken. `(:strong a)` is strong fairness: if `a` is enabled again and again, it is
eventually taken. A fairness condition applies to the disjunction of every
parameter instance of the action, as `WF_vars(\E x : A(x))` does in TLA+. An
action counts as taken when its step changes at least one variable.

```lisp
(defspec ticker ((limit 3))
  (:variables x)
  (:init (x 0))
  (:action tick
    (:guard (< x limit))
    (:next (x (1+ x))))
  (:temporal reaches-limit (:eventually (= x limit)))
  (:fairness (:weak tick))
  (:deadlock-check nil))

(defspec lazy-ticker ((limit 3))
  (:variables x)
  (:init (x 0))
  (:action tick
    (:guard (< x limit))
    (:next (x (1+ x))))
  (:temporal reaches-limit (:eventually (= x limit)))
  (:deadlock-check nil))
```

The ticker reaches its limit under weak fairness. The lazy ticker declares no
fairness, so the search returns a lasso: a prefix from an initial state and a
cycle that repeats forever. [Reading a counterexample](#reading-a-counterexample)
explains how to read one.

```lisp
(let ((result (explore-spec (ticker))))
  (list (spec-result-passed-p result) (spec-result-checked-properties result)))
;; => (T (REACHES-LIMIT))

(let* ((result (explore-spec (lazy-ticker)))
       (violation (spec-result-violation result)))
  (format-spec-trace (spec-violation-trace violation) *standard-output*)
  (list (spec-violation-kind violation) (spec-violation-property violation)))
;; | Prefix:
;; |   0: NIL NIL => (X 0)
;; | Cycle:
;; |   0: NIL NIL => (X 0)
;; => (:TEMPORAL REACHES-LIMIT)
```

Liveness is decided only on the complete state graph. `explore-spec` builds the
graph while it searches. If the search is truncated, liveness is not decided and
the run fails, even with `:allow-bounded t` (see [Truncation and
limits](#truncation-and-limits)). Symmetry and liveness cannot be used together,
and the combination signals `spec-configuration-error`.

## Symmetry

If some constants are interchangeable, such as the processes of a protocol, the
search can treat two states that differ by a permutation of those constants as one
state. `(:symmetry procs)` declares that the elements of the constant `procs` are
symmetric. `spec-state-canonicalizer` returns the function that maps a state to
the representative of its class, or `nil` if the specification declares no
symmetry. `explore-spec` uses it when `:symmetry` is `t`.

The next specification lets four processes each grab a resource once. Without
symmetry it has one state per subset. With symmetry it has one state per subset
size.

```lisp
(defspec grabbers ((procs '(p1 p2 p3 p4)) (alone nil))
  (:variables holders)
  (:init (holders (spec-set)))
  (:action grab
    (:for (p procs))
    (:guard (not (spec-set-member-p p holders)))
    (:next (holders (spec-set-union holders (spec-set p)))))
  (:invariant bounded (<= (spec-set-size holders) (length procs)))
  (:invariant never-alone
    (or (null alone) (not (equal holders (spec-set alone)))))
  (:symmetry procs)
  (:deadlock-check nil))
```

```lisp
(list (spec-result-states-found (explore-spec (grabbers) :symmetry nil))
      (spec-result-states-found (explore-spec (grabbers))))
;; => (16 5)

(let ((canonicalize (spec-state-canonicalizer (grabbers))))
  (equal (funcall canonicalize (make-state (grabbers) (list 'holders (spec-set 'p3))))
         (funcall canonicalize (make-state (grabbers) (list 'holders (spec-set 'p1))))))
;; => T

(list :without-symmetry
      (spec-result-passed-p (explore-spec (grabbers :alone 'p4) :symmetry nil))
      :with-symmetry
      (spec-result-passed-p (explore-spec (grabbers :alone 'p4))))
;; => (:WITHOUT-SYMMETRY NIL :WITH-SYMMETRY T)
```

The last result, `:WITH-SYMMETRY T`, is a wrong answer, shown on purpose. The
`never-alone` invariant names one process through the constant `alone`, so it is
not invariant under permutation, and symmetry is sound only for properties that
are. The reduced search discards the state `{p4}` as equivalent to `{p1}`
before it checks it. The trace and the checks use the real states, and the
canonical form only decides whether a state was already visited. A numeric
constant that also appears as an ordinary number in another variable is not
invariant either, because the permutation rewrites those numbers too. Such a
specification can pass with symmetry on and fail with it off. Symmetric
constants must be a set or a list of atoms, and the list must not contain `nil`.

Keep the state that mentions symmetric constants in sets, functions, records or
sequences, which are rebuilt in canonical form after a permutation. A plain list
is not. In a variant of the mutex above that kept its process table as an
association list and declared `(:symmetry procs)`, exploration found the same
number of states with and without symmetry, and the same table kept as a
function value reduced it.

```lisp
(handler-case (explore-spec (grabbers :procs '(nil p1)))
  (spec-definition-error (condition) (spec-error-message condition)))
;; => "Symmetric constant PROCS must not contain NIL."

(defspec fair-pair ((procs '(a b)))
  (:variables x)
  (:init (x 0))
  (:action tick (:guard (< x 2)) (:next (x (1+ x))))
  (:temporal reaches (:eventually (= x 2)))
  (:fairness (:weak tick))
  (:symmetry procs)
  (:deadlock-check nil))

(list (handler-case (explore-spec (fair-pair))
        (spec-configuration-error (condition) (spec-error-message condition)))
      (spec-result-passed-p (explore-spec (fair-pair) :symmetry nil)))
;; => ("Symmetry and temporal properties cannot be checked together." T)
```

Canonicalizing a state tries every permutation of the symmetric constants, so the
cost grows factorially with the number of symmetric elements. On a small state
space the cost can exceed the saving. Measure with `:symmetry nil` before relying
on it.

## Refinement

`check-refinement` checks that a low-level specification implements a high-level
one. The third argument is a refinement mapping, a function from a low-level
state to the property list of a high-level state. It checks that:

- the image of every low-level initial state is a high-level initial state, and
- the image of every low-level step is either unchanged (a stuttering step of the
  high-level specification) or a step of one of the high-level actions.

The low-level specification counts from 0 to `(* 2 top)`, which is 4, and the
mapping halves the count. Each high-level step corresponds to every second
low-level step.

```lisp
(defspec halves ((top 2))
  (:variables y)
  (:init (y 0))
  (:action bump (:guard (< y top)) (:next (y (1+ y))))
  (:temporal reaches-top (:eventually (= y top)))
  (:fairness (:weak bump))
  (:deadlock-check nil))

(defspec single-steps ((top 2))
  (:variables x)
  (:init (x 0))
  (:action inc (:guard (< x (* 2 top))) (:next (x (1+ x))))
  (:fairness (:weak inc))
  (:deadlock-check nil))

(defun halve (state)
  (list 'y (floor (state-ref state 'x) 2)))

(let ((result (check-refinement (single-steps) (halves) #'halve)))
  (list (spec-result-mode result)
        (spec-result-passed-p result)
        (spec-result-checked-properties result)))
;; => (:REFINEMENT T (REACHES-TOP))
```

A mapping that does not preserve steps is reported with the low-level trace and
the mapped step that the high-level specification cannot take.

```lisp
(defspec double-steps ((top 2))
  (:variables x)
  (:init (x 0))
  (:action jump (:guard (< x (* 2 top))) (:next (x (+ x 2))))
  (:deadlock-check nil))

(let* ((result (check-refinement (double-steps) (halves)
                                 (lambda (state) (list 'y (state-ref state 'x)))))
       (violation (spec-result-violation result))
       (detail (spec-violation-detail violation)))
  (format-spec-trace (spec-violation-trace violation) *standard-output*)
  (list (spec-violation-kind violation)
        (getf detail :phase)
        (getf detail :mapped-from)
        (getf detail :mapped-to)))
;; |   0: NIL NIL => (X 0)
;; |   1: JUMP NIL => (X 2)
;; => (:REFINEMENT :STEP (Y 0) (Y 2))
```

If the high-level specification declares temporal properties, they are checked
too, and only when the low-level search is complete. Each property is checked on
the low-level graph, with its predicates composed with the mapping, under the
low-level fairness conditions. The high-level fairness conditions themselves are
not checked, so a low-level specification that does not enforce the progress the
high-level one assumes fails the check.

```lisp
(defspec unfair-steps ((top 2))
  (:variables x)
  (:init (x 0))
  (:action inc (:guard (< x (* 2 top))) (:next (x (1+ x))))
  (:deadlock-check nil))

(let* ((result (check-refinement (unfair-steps) (halves) #'halve))
       (violation (spec-result-violation result)))
  (list (spec-violation-kind violation) (spec-violation-property violation)))
;; => (:TEMPORAL REACHES-TOP)
```

The `:temporal` keyword selects high-level properties or turns the check off
with `nil`, and `:max-states`, `:max-depth` and `:allow-bounded` behave as in
`explore-spec`.

## Conformance checking

Conformance checking compares an implementation with the specification. You give
each action a function that drives the implementation, plus a function that
resets it and a function that abstracts its state into a specification state.

### Sequential conformance

`check-sequential-conformance` takes these keywords:

| Keyword | Meaning |
| --- | --- |
| `:reset` | Returns a fresh implementation value. |
| `:operations` | An alist from an action name to a function of the implementation value and the action parameters. Every action must have one. |
| `:abstraction` | Maps the implementation value to a state property list. |
| `:mode` | `:random` (the default) or `:tree`. |
| `:seed`, `:runs`, `:max-steps` | Limits for `:random`. |
| `:depth`, `:max-states`, `:allow-bounded` | Limits for `:tree`. |

At each step the checker picks an action that the specification enables, calls the
operation, abstracts the implementation state, and requires it to equal the
specification's next state. If the action declares an `:output`, the returned
value must equal it. An operation that signals an error is a violation, and the
condition object is reported as the actual value. A failing sequence is shrunk by
re-running candidates against fresh implementations.

The queue below has an implementation bug: with two or more items, `deq` removes
the newest item. The operations here return the new size, which the specification
states with `(next items)`.

```lisp
(defspec bounded-queue ((capacity 2) (elements '(a b)))
  (:variables items)
  (:init (items nil))
  (:action enq
    (:for (element elements))
    (:guard (< (length items) capacity))
    (:next (items (append items (list element))))
    (:output (length (next items))))
  (:action deq
    (:guard (plusp (length items)))
    (:next (items (rest items)))
    (:output (length (next items)))))

(defstruct (list-queue (:constructor make-list-queue (&optional buggy)))
  (items nil)
  buggy)

(defun queue-enq (queue element)
  (setf (list-queue-items queue)
        (append (list-queue-items queue) (list element)))
  (length (list-queue-items queue)))

(defun queue-deq (queue)
  (let ((items (list-queue-items queue)))
    ;; Bug: with two or more items the buggy queue removes the newest one.
    (setf (list-queue-items queue)
          (if (and (list-queue-buggy queue) (rest items))
              (butlast items)
              (rest items)))
    (length (list-queue-items queue))))

(defun check-queue (buggy &rest options)
  (apply #'check-sequential-conformance (bounded-queue)
         :reset (lambda () (make-list-queue buggy))
         :operations (list (cons 'enq #'queue-enq) (cons 'deq #'queue-deq))
         :abstraction (lambda (queue) (list 'items (copy-list (list-queue-items queue))))
         options))
```

```lisp
(let ((result (check-queue nil :seed 7 :runs 30 :max-steps 20)))
  (list (spec-result-mode result)
        (spec-result-passed-p result)
        (spec-result-statistics result)))
;; => (:SEQUENTIAL-CONFORMANCE T (:RUNS 30 :STEPS 600 :SEED 7))

(let* ((result (check-queue t :seed 7 :runs 30 :max-steps 20))
       (violation (spec-result-violation result))
       (detail (spec-violation-detail violation)))
  (format-spec-trace (spec-violation-trace violation) *standard-output*)
  (list :passed (spec-result-passed-p result)
        :step (getf detail :step)
        :action (getf detail :action)
        :what (getf detail :what)
        :expected (getf detail :expected)
        :actual (getf detail :actual)
        :original-entries (length (getf detail :original-trace))
        :shrunk-entries (length (spec-violation-trace violation))))
;; |   0: NIL NIL => (ITEMS NIL)
;; |   1: ENQ (B) => (ITEMS (B))
;; |   2: ENQ (A) => (ITEMS (B A))
;; |   3: DEQ NIL => (ITEMS (A))
;; => (:PASSED NIL :STEP 3 :ACTION DEQ :WHAT :STATE :EXPECTED (ITEMS (A)) :ACTUAL (ITEMS (B)) :ORIGINAL-ENTRIES 16 :SHRUNK-ENTRIES 4)
```

The checker shrank the failing run to three calls and reports the expected and
the actual state at the failing step. The unshrunk trace is under
`:original-trace`. Take the original length as the length of that list. The list
starts with the initial state, so the 16 entries above are 15 calls and the
shrunk trace's four entries are three calls. Only `simulate-spec` adds
`:original-length` and `:shrunk-length` keys; conformance checking does not.

`:tree` mode does not draw random sequences. It walks the specification's
reachable states breadth-first up to `:depth`, and for each transition it finds it
calls `reset` and replays the path that leads there. A tree that stops at the
depth limit while some state still has an enabled action is truncated (see
[Truncation and limits](#truncation-and-limits)). The queue has seven states, and
each is reachable in at most two steps, so a depth of four covers all of them.

```lisp
(let ((result (check-queue nil :mode :tree :depth 1)))
  (list (spec-result-passed-p result)
        (spec-result-truncated result)
        (spec-result-truncation-reason result)))
;; => (NIL T :MAX-DEPTH)

(let ((result (check-queue nil :mode :tree :depth 4)))
  (list (spec-result-passed-p result) (spec-result-truncated result)))
;; => (T NIL)

(spec-violation-kind (spec-result-violation (check-queue t :mode :tree :depth 4)))
;; => :CONFORMANCE
```

The tree starts at the state that the first `reset` abstracts to, and every later
`reset` must land in the same state. Two different mismatches can occur, and they
are reported differently:

- A `reset` that lands in a state matching none of the specification's initial
  states is a `:conformance` violation at step 0, with the initial states as
  `:expected` and the abstracted state as `:actual`. A step 0 violation is
  reported as found and is not shrunk.
- A `reset` that lands in a different state that is a valid initial state of the
  specification signals `spec-configuration-error`, because the checker does not
  skip paths silently.

Use `:random` mode for an implementation whose initial state varies.

```lisp
(defspec two-starts ()
  (:variables x)
  (:init (x (:in '(0 1))))
  (:action stay (:guard (< x 2)) (:next (x x))))

(let ((resets 0))
  (handler-case
      (check-sequential-conformance
       (two-starts)
       :mode :tree :depth 2
       :reset (lambda () (list (mod (incf resets) 2)))
       :operations (list (cons 'stay #'identity))
       :abstraction (lambda (sut) (list 'x (first sut))))
    (spec-configuration-error (condition) (spec-error-message condition))))
;; => "Tree reset changed initial state from (X 1) to (X 0)."
```

A `reset` that lands outside the initial states, here in the state `(X 5)`, is a
violation instead of an error.

```lisp
(let* ((result (check-sequential-conformance
                (two-starts)
                :mode :tree :depth 2
                :reset (lambda () (list 5))
                :operations (list (cons 'stay #'identity))
                :abstraction (lambda (sut) (list 'x (first sut)))))
       (violation (spec-result-violation result))
       (detail (spec-violation-detail violation)))
  (list (spec-violation-kind violation)
        (getf detail :step)
        (getf detail :expected)
        (getf detail :actual)))
;; => (:CONFORMANCE 0 ((X 0) (X 1)) (X 5))
```

`:tree` mode explores per specification state. For each transition it resets the
implementation, replays the path to the source state and executes the transition,
and that includes a transition into a state the tree already holds. A state is
queued for expansion only when it is first reached, so its successors are tried
along the first path that reaches it and not along later ones. An implementation
with internal history that the abstraction does not show can behave differently
after another path to the same state, and a mismatch that appears only then goes
unnoticed. `:random` mode samples other paths, and an abstraction that includes
the history lets either mode see it.

### Concurrent conformance

`check-linearizability` runs operations on several threads and checks that the
observed results could have come from some sequential execution of the
specification that respects real time. This is linearizability. It records a
history of operations, each with its thread, the action, the parameters, the
output, and an `invoked` and a `returned` stamp from one shared clock.

The seed fixes the sequence of generated operations. It does not fix the thread
schedule, so a run that finds a race may not find it again, and a passing run does
not prove the absence of one. Judging a recorded history is deterministic.

The check requires the `:concurrency` platform capability, which the SBCL platform
layer registers when the image has thread support. Without it,
`platform-capability-unavailable` is signaled before any thread starts, and the
check never passes silently. See [Runtime Support](../reference/runtime-support.md).

The specification's actions must be total: each must be enabled, and have a
result, in every state that any interleaving can reach. An action that is
disabled in some reachable state makes the checker reject a correct execution.

`check-linearizability` takes `:reset` and `:operations` as the sequential check
does, plus `:threads`, `:operations-per-thread`, `:runs`, `:seed`, `:budget` and
`:allow-bounded`. Each run resets the implementation, generates a sequence of
operations that the specification enables in order, splits it among the threads,
starts the threads together, and judges the recorded history.

`linearizable-history-p` judges a history that you supply and needs no threads.
It returns whether the history is linearizable, the longest linearizable prefix,
and whether the search budget ran out. `make-history-operation` builds an entry.

```lisp
(defspec shared-counter ()
  (:variables n)
  (:init (n 0))
  (:action incr
    (:next (n (1+ n)))
    (:output (next n))))

(defun op (id thread output invoked returned)
  (make-history-operation :id id :thread thread :action 'incr :params nil
                          :output output :invoked invoked :returned returned))
```

The arguments of `op` are the id, the thread, the output, and the `invoked` and
`returned` stamps. In the third history the first call returned before the second
began, so the second must come later in any order, and the outputs 2 then 1 cannot
come from a counter.

```lisp
(multiple-value-bind (linearizable-p prefix budget-exceeded-p)
    (linearizable-history-p (shared-counter) (list (op 0 0 1 1 4) (op 1 1 2 2 3)))
  (list linearizable-p (mapcar #'history-operation-id prefix) budget-exceeded-p))
;; => (T (0 1) NIL)

(multiple-value-bind (linearizable-p prefix budget-exceeded-p)
    (linearizable-history-p (shared-counter) (list (op 0 0 1 1 4) (op 1 1 1 2 3)))
  (list linearizable-p (mapcar #'history-operation-id prefix) budget-exceeded-p))
;; => (NIL (0) NIL)

(linearizable-history-p (shared-counter) (list (op 0 0 2 1 2) (op 1 1 1 3 4)))
;; => NIL

(nth-value 2 (linearizable-history-p (shared-counter)
                                     (list (op 0 0 1 1 4) (op 1 1 2 2 3))
                                     :budget 1))
;; => T
```

A counter whose increment holds a lock is linearizable. One that reads, yields,
and writes loses updates, and the history records an output pair that no
sequential order explains.

```lisp
(defvar *counter-lock* (sb-thread:make-mutex))

(defun locked-incr (cell)
  (sb-thread:with-mutex (*counter-lock*)
    (incf (car cell))))

(defun racy-incr (cell)
  (let ((seen (car cell)))
    (sb-thread:thread-yield)
    (setf (car cell) (1+ seen))))

(defun check-counter (incr &rest options)
  (apply #'check-linearizability (shared-counter)
         :reset (lambda () (list 0))
         :operations (list (cons 'incr incr))
         options))
```

```lisp
(let ((result (check-counter #'locked-incr :threads 4 :operations-per-thread 5
                                           :runs 20 :seed 3)))
  (list (spec-result-mode result) (spec-result-passed-p result)))
;; => (:LINEARIZABILITY T)

(let* ((result (check-counter #'racy-incr :threads 4 :operations-per-thread 5
                                          :runs 20 :seed 3))
       (violation (spec-result-violation result)))
  (list (spec-result-passed-p result)
        (spec-violation-kind violation)
        (length (getf (spec-violation-detail violation) :history))))
;; => (NIL :LINEARIZABILITY 20)
```

With this much contention a failure is expected but not guaranteed on every run,
and the history differs between runs. [Reading a
counterexample](#reading-a-counterexample) explains the detail list.

When the search budget runs out, `check-linearizability` returns a truncated
result with the reason `:budget`, which fails by default (see [Truncation and
limits](#truncation-and-limits)).

```lisp
(let ((result (check-counter #'locked-incr :threads 2 :operations-per-thread 3
                                           :runs 2 :seed 3 :budget 1)))
  (list (spec-result-truncated result)
        (spec-result-truncation-reason result)
        (spec-result-passed-p result)))
;; => (T :BUDGET NIL)
```

## Registering specification tests

`it-spec` registers a test that runs one check form and reports its result. It
expands into `cl-weave:it`, so focus, skip, todo, retry, timeout, filters and
shards work as they do for any other test. A leading options plist is passed to
`it`. The macro does not inspect the check form, so any of `explore-spec`,
`simulate-spec`, `check-refinement`, `check-sequential-conformance` and
`check-linearizability` fits.

- `it-spec-only` focuses the test like `it-only`.
- `it-spec-skip` and `it-spec-todo` take an optional reason before the check
  form, as `it-skip` and `it-todo` do. The check form is never evaluated.

An `it-spec` form must hold exactly one check form, and a second form is a
registration syntax error. The check runs inside `report-spec-result`. A
pass records its statistics on the journal and returns normally. Any other result
signals `assertion-failure`, so a failure reports through the same path as `expect`.

```lisp
(cl-weave:describe "queue model"
  (it-spec "never deadlocks"
    (explore-spec (bounded-queue)))
  (it-spec "matches the list implementation" (:timeout-ms 5000)
    (check-queue nil :seed 7 :runs 30))
  (it-spec-skip "pending refinement" "waiting for the ring buffer"
    (check-queue nil))
  (it-spec-todo "write the liveness check"
    (explore-spec (bounded-queue))))
```

The `spec` reporter (`:reporter :spec`, see [Reporters and
CI](reporters-and-ci.md)) prints the following. Timings and the summary line are omitted here.

```text
[PASS] queue model > never deadlocks
[PASS] queue model > matches the list implementation
[SKIP] queue model > pending refinement
    reason: waiting for the ring buffer
[TODO] queue model > write the liveness check
    reason: todo
```

## Truncation and limits

Every search has finite default limits, which [Results, traces and
limits](../reference/api.md#results-traces-and-limits) lists. Pass keyword
arguments to override them per check, or rebind the variables.

A check that stops because of a limit has not covered the space, so by default it
fails. The failure message names the number of states found and the depth
reached. `:allow-bounded t` says that a bounded check is acceptable, and the
result then passes while its statistics stay in the journal. This holds for the
state limit, the depth limit, the tree mode of conformance checking and the
linearization budget.

Liveness is the exception. Beyond the edge of a truncated graph the successors
are unknown. Treating the edge as a dead end would report violations that do not
exist, and ignoring its successors would miss real cycles. So a truncated run
that requested temporal properties fails even with `:allow-bounded t`.
Pass `:temporal nil` to check only the safety properties of a large
specification.

`spec-result-passed-p` is the single place that decides this. `report-spec-result`,
and therefore `it-spec`, calls it, and so should any code that reads a result:

| Situation | `spec-result-passed-p` |
| --- | --- |
| A violation was found | false |
| No truncation and no violation | true |
| Truncated, `:allow-bounded` not given | false |
| Truncated, `:allow-bounded t`, no temporal properties requested | true |
| Truncated, temporal properties requested | false, even with `:allow-bounded t` |

```lisp
(let ((result (explore-spec (countdown :start 50) :max-states 10 :check-deadlock nil)))
  (list :truncated (spec-result-truncated result)
        :reason (spec-result-truncation-reason result)
        :passed (spec-result-passed-p result)
        :states (spec-result-states-found result)
        :depth (spec-result-depth-reached result)))
;; => (:TRUNCATED T :REASON :MAX-STATES :PASSED NIL :STATES 10 :DEPTH 9)

(let ((result (explore-spec (countdown :start 50) :max-states 10 :check-deadlock nil
                                                  :allow-bounded t)))
  (list (spec-result-truncated result) (spec-result-passed-p result)))
;; => (T T)

(let ((result (explore-spec (ticker :limit 50) :max-states 5 :allow-bounded t)))
  (list (spec-result-truncated result) (spec-result-passed-p result)))
;; => (T NIL)

(let ((result (explore-spec (ticker :limit 50) :max-states 5 :allow-bounded t
                                               :temporal nil)))
  (list (spec-result-truncated result) (spec-result-passed-p result)))
;; => (T T)
```

The depth limit counts steps from an initial state. A state at the depth limit is
not expanded, and the run is truncated only if such a state still has an enabled
action. `simulate-spec` has no truncation: it stops each run after `:max-steps`
steps and reports the runs it made.

## Reading a counterexample

A failed check returns a `spec-violation`. Its `kind`, the other fields and their
accessors are listed in [Results, traces and
limits](../reference/api.md#results-traces-and-limits). The checkers that explore
or replay a sequence of steps (`explore-spec`, `simulate-spec`, `check-refinement`
and `check-sequential-conformance`) give a violation a `trace`.
`check-linearizability` gives it a history instead, and the two are read
differently.

**A violation with a trace.** The `trace` is a list of `trace-step` values, each
holding an action, its parameters and the state after the step. The first step is
an initial state and has no action. For a `:temporal` violation the trace is a
`lasso`, which has a prefix and a cycle. The last state of the cycle equals the
last state of the prefix. A cycle that stays in one state is a single step with
no action.

For a shrunk random or conformance failure, `trace` is the shrunk sequence. The
unshrunk trace is under `:original-trace` in the violation's detail list, together
with `:seed` and `:case-index` for random runs. A conformance violation at step 0
is reported as found, so it has no `:original-trace`.

**A violation from `check-linearizability`.** A `:linearizability` violation has
no trace, and `spec-violation-trace` returns `nil`. The threads of a concurrent run
leave a history of operations that overlap in time, not a sequence of steps, so
the detail list holds the evidence. `:history` holds every recorded operation as a
`history-operation`, ordered by its `invoked` stamp. `:longest-prefix` holds the
longest list of those operations that the search could put in an order the
specification allows. The operations of `:history` that are missing from the
prefix are the ones the search could not place after it, so start with the first
of them.

Two operations may be ordered either way when their time spans, from `invoked` to
`returned`, overlap. An operation that returned before another was invoked must
come first. A violation therefore means that the recorded outputs fit no such
order. The next check uses an increment that always returns 0, which no order of
a counter can explain, so the run fails whatever the thread schedule is.

```lisp
(let* ((result (check-counter (lambda (cell) (declare (ignore cell)) 0)
                              :threads 2 :operations-per-thread 2 :runs 1 :seed 3))
       (violation (spec-result-violation result))
       (detail (spec-violation-detail violation)))
  (list (spec-violation-kind violation)
        (spec-violation-trace violation)
        (length (getf detail :history))
        (length (getf detail :longest-prefix))))
;; => (:LINEARIZABILITY NIL 4 0)
```

An operation that signals an error during a concurrent run is reported as a
`:conformance` violation, which has no trace either. Its detail list holds
`:step` (the one-based position of the call in the generated sequence), `:action`,
`:params` and `:condition`.

A failed test carries a payload, a property list. [Reporting and
registration](../reference/api.md#reporting-and-registration) lists its keys and
describes `format-spec-trace` and `report-spec-result`. In the payload, `:values` holds the unshrunk trace when there was one, and `:minimal`
holds the trace that is reported.

The `:condition` string of the payload holds the violated property, its kind, every
step of the trace, and the statistics, so the failure is readable without the
journal. For a `:linearizability` violation, which has no trace, `:minimal` is
empty and the string lists the history and the longest prefix instead. A
truncated run reports the reason and what can be done about it:

```lisp
(let ((result (explore-spec (countdown :start 50) :max-states 10 :check-deadlock nil)))
  (write-string (getf (spec-result-payload result) :condition)))
;; | States found: 10; depth reached: 9.
;; | Search truncated: :MAX-STATES. Use :allow-bounded t to permit bounded checking (except temporal properties).
```

When temporal properties were requested, the second line says instead that they
cannot pass a truncated search, even with `:allow-bounded t`.

In a test run, the spec reporter shows the payload. With the journal enabled
(bind `cl-weave:*journal-enabled*` or pass `--journal`, see [Time-Travel
Debugging](time-travel-debugging.md)), it also shows a timeline of `:spec-step`
frames, one per trace step, ending in a `:spec-stats` frame. A concurrent failure
adds a `:spec-history` frame for each recorded operation. This is the report for
`(it-spec "without the lock check (broken)" (explore-spec (mutex :checked-lock nil) :max-states 500 :max-depth 20))`
in a suite named `mutex`. It is abbreviated: `actual:` carries the payload, and
the `condition:`, `form:` and `negated:` lines are left out.

```text
[FAIL] mutex > without the lock check (broken)
    matcher: :SPEC
    actual: (:SEED NIL :CASE-INDEX NIL :VALUES NIL :MINIMAL (...) :CONDITION "..."
             :SPEC MUTEX :MODE :EXHAUSTIVE :KIND :INVARIANT :PROPERTY
             MUTUAL-EXCLUSION :STATS (:TRANSITIONS 14 :INITIAL-STATES 1))
    expected: (MUTUAL-EXCLUSION :DEADLOCK)
    timeline (6 frames):
      #0 spec-step :INIT => (PC ((P1 . :IDLE) (P2 . :IDLE)) LOCK :FREE) ok
      #1 spec-step (TRY P1) => (PC ((P1 . :WAITING) (P2 . :IDLE)) LOCK :FREE) ok
      #2 spec-step (TRY P2) => (PC ((P1 . :WAITING) (P2 . :WAITING)) LOCK :FREE) ok
      #3 spec-step (ENTER P1) => (PC ((P1 . :CRITICAL) (P2 . :WAITING)) LOCK P1) ok
      #4 spec-step (ENTER P2) => (PC ((P1 . :CRITICAL) (P2 . :CRITICAL)) LOCK P2) FAIL
      #5 spec-stats MUTEX (:STATES-FOUND 9 :DEPTH-REACHED 4 :TRUNCATED NIL :TRANSITIONS 14
 :INITIAL-STATES 1) limits (:MAX-STATES 500 :MAX-DEPTH 20) FAIL
```

`explain-journal` renders the same frames for any journal that `report-spec-result`
wrote to.

## Limits and caveats

Each constraint is stated where the feature is described:

- Refinement does not check the high-level fairness conditions: [Refinement](#refinement).
- Symmetry is sound only for permutation-invariant predicates, and it can slow a
  small search: [Symmetry](#symmetry).
- Concurrent conformance needs total actions and the `:concurrency` capability, and
  the seed does not fix the thread schedule: [Concurrent
  conformance](#concurrent-conformance).
- Truncation is a failure by default, and never passes for liveness: [Truncation
  and limits](#truncation-and-limits).
- `:tree` conformance needs a deterministic `reset` and explores per state:
  [Sequential conformance](#sequential-conformance).
- Liveness and symmetry exclude each other: [Liveness and
  fairness](#liveness-and-fairness).
- Random exploration cannot check liveness: [Random
  exploration](#random-exploration).

See also [Property Testing](property-testing.md), [Test
Execution](test-execution.md), [Time-Travel Debugging](time-travel-debugging.md),
the [API Reference](../reference/api.md) and
[Runtime Support](../reference/runtime-support.md).
