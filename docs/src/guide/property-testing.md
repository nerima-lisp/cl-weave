# Property Testing

```lisp
(it-property "addition is commutative"
    ((left (gen-integer :min -100 :max 100))
     (right (gen-integer :min -100 :max 100)))
  (expect (+ left right) :to-be (+ right left)))
```

Property generators are plain data objects. `it-property` runs generated examples
through the normal assertion engine, then reports the original failing values and
the minimized values through the same structured `assertion-failure` path used by
`expect`. Failure payloads also include the seed and zero-based generated case
index, so CI and agents can reproduce the run with `CL_WEAVE_PROPERTY_SEED`.

## Built-In Generators

- `(gen-integer :min -100 :max 100)`
- `(gen-boolean)`
- `(gen-character :alphabet "abc")`
- `(gen-member '(:a :b :c))`
- `(gen-map function generator :name :derived)`
- `(gen-list generator :min-length 0 :max-length 8)`
- `(gen-string :min-length 0 :max-length 16 :alphabet "abc")`
- `(gen-vector generator :min-length 0 :max-length 8)`
- `(gen-state-machine initial-state transition event-generator :min-length 0 :max-length 16)`
- `(gen-one-of generator-a generator-b ...)`
- `(gen-recursive base-generator builder :max-depth 4)`
- `(gen-symbol :names '("x" "y") :package "CL-USER")`
- `(gen-keyword '("left" "right"))`
- `(gen-sexp :max-depth 4 :max-list-length 4)`
- `(gen-form :operators '(progn list cons) :max-depth 4 :max-arguments 3)`
- `(gen-tuple generator-a generator-b ...)`
- `(gen-such-that predicate generator :attempts 100)`

Generator combinators keep data and logic separate: generators describe how
values are produced and shrunk, while `it-property` owns execution, failure
capture, and reporting. `gen-list` shrinks both list structure and individual
elements; `gen-string` and `gen-vector` apply the same structural and element
shrinking to sequence-heavy APIs; `gen-state-machine` generates bounded event
streams and replayed state traces as `(:initial ... :events ... :states ...
:final ...)`, shrinking the event stream while recomputing states through the
same transition function; `gen-recursive` gives the builder a self-referential
generator for bounded S-expression and AST shapes; `gen-sexp` and `gen-form`
provide common Lisp data and macro-expansion inputs without embedding runner
logic in tests; `gen-tuple` shrinks each slot through its corresponding
generator; `gen-such-that` keeps generated and shrunk values inside the
predicate. `gen-such-that` validates its arguments eagerly: `predicate` must be
a function and `attempts` must be a positive integer, so a misplaced value
(for example passing a symbol instead of `#'plusp`) signals a `cl-weave` error
at construction time rather than failing deep inside generation.

```lisp
(it-property "command shape is stable"
    ((command (gen-tuple (gen-one-of (gen-member '(:open :close))
                                     (gen-member '(:resize)))
                         (gen-such-that #'plusp
                                        (gen-integer :min 1 :max 20)))))
  (destructuring-bind (kind count) command
    (expect kind :to-satisfy #'keywordp)
    (expect count :to-satisfy #'plusp)))

(it-property "forms stay bounded"
    ((form (gen-form :operators '(quote if progn)
                     :max-depth 3
                     :max-arguments 2)))
  (expect form :to-satisfy (lambda (value) (or (atom value) (consp value)))))

(it-property "state machine traces stay replayable"
    ((trace (gen-state-machine
             :idle
             (lambda (state event)
               (ecase event
                 (:start :running)
                 (:stop :idle)
                 (:error :failed)))
             (gen-member '(:start :stop :error))
             :min-length 1
             :max-length 5)))
  (expect (getf trace :states) :to-satisfy
          (lambda (states)
            (= (length states) (1+ (length (getf trace :events))))))
  (expect (getf trace :final) :to-be (first (last (getf trace :states)))))
```

Use `*property-test-count*` and `*property-seed*` for dynamic REPL control, or
`CL_WEAVE_PROPERTY_TESTS` and `CL_WEAVE_PROPERTY_SEED` for reproducible CI runs.
`CL_WEAVE_PROPERTY_TESTS` must be a positive integer. Both CI environment
variables are parsed strictly, so invalid values fail fast with a `cl-weave:`
diagnostic instead of silently running zero generated cases.

## Fuzzing with `it-fuzz`

`it-fuzz` reuses `it-property`'s generator and shrinking machinery, but the body
is *not* a boolean predicate. A trial passes simply by running without signaling
an `error`; a trial that signals an `error` is a failure, and its generated
inputs are minimized exactly as a failing `it-property`'s are. This makes
`it-fuzz` the right tool for "must never crash" invariants over generated
inputs — parsers, decoders, and state machines.

```lisp
(it-fuzz "parser never crashes on generated forms"
    ((form (gen-form :operators '(progn list cons) :max-depth 3)))
    (:trials 200 :timeout-per-trial 2)
  (my-parser form))
```

`bindings` is the same literal `((name generator) ...)` list as `it-property`.
`options` is a literal plist accepting:

- `:trials` — number of generated trials (default `100`); it binds
  `*property-test-count*` for the run.
- `:timeout-per-trial` — per-trial budget in seconds (default `5`, or `nil` to
  disable). A trial that merely *times out* is not evidence of a bug, so it
  counts as neither a pass nor a failure and is skipped rather than shrunk.

## Controlling Shrinking

Shrinking is bounded and recoverable through the condition system, so a
misbehaving shrinker never hangs a run:

- `*property-shrink-max-steps*` (default `1000`) caps the number of shrink
  steps. Exceeding it signals `property-shrink-limit` (readers
  `property-shrink-limit-values`, `property-shrink-limit-steps`,
  `property-shrink-limit-max-steps`), which offers the `accept-current` restart
  to stop and keep the smallest value found so far.
- If a generator's own shrink function errors, cl-weave signals
  `property-shrinker-error` (readers `property-shrinker-error-generator`,
  `property-shrinker-error-value`, `property-shrinker-error-cause`) with three
  restarts: `retry-shrinker` (run the shrinker again), `use-value` (supply
  replacement shrink candidates), and `skip-shrinking` (keep the current value
  and stop shrinking it).
- `same-property-failure-p` is a generic function that decides whether a shrink
  candidate reproduces the *same* failure. The default method compares the
  signaled condition's class; specialize it when two distinct failures share a
  class and should not be conflated during minimization.

## Watching a Shrink Run

Every candidate the shrinker tries becomes a `:shrink-step` frame on the
[execution journal](time-travel-debugging.md) when `*journal-enabled*` is
bound, interleaved chronologically with the assertion frames from the
property function itself. The frame's form is the full candidate argument
tuple; `pass` records whether that candidate reproduced the failure and became
the new shrink frontier:

```lisp
(let ((cl-weave:*journal-enabled* t))
  (cl-weave:with-execution-journal
    (cl-weave::shrink-property-values ...)))
;; => (#<journal-frame #0 shrink-step arg 0 -> (5) rejected>
;;     #<journal-frame #1 shrink-step arg 0 -> (1) accepted> ...)
```

In practice this surfaces automatically wherever the journal already does: the
`spec` reporter prints the walk from the first failing case down to the
minimal one underneath a failed `it-property` test, and `explain-journal` or
the JSON `timeline` field carry the same frames for offline inspection or
`replay-test`.
