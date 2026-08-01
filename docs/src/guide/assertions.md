# Assertions And Matchers

```lisp
(expect actual :to-be expected)
(expect (= actual expected))
(expect (< low value high))
(expect actual :to-equal expected)
(expect value :to-be-greater-than 10)
(expect values :to-have-length 3)
(expect (lambda () (parse-integer "42")) :to-run-under-ms 5)
(expect (lambda () (loop repeat 10 collect :x)) :to-allocate-under 4096)
(expect form :to-match-inline-snapshot "(:ok 42)")
(let ((*snapshot-directory* #P"tests/__snapshots__/")
      (*snapshot-file-name* "snapshots.sexp"))
  (with-snapshot-updates
    (expect form :to-match-snapshot "suite/case"))
  (expect form :to-match-snapshot "suite/case")
  (with-snapshot-updates
    (expect '((:pc 0 :acc 0) (:pc 1 :acc 1))
            :to-match-snapshot-sequence
            "vm/run"))
  (expect '((:pc 0 :acc 0) (:pc 1 :acc 1))
          :to-match-snapshot-sequence
          "vm/run"))
(expect value :not :to-be nil)
(expect-not value :to-be nil)
(expect-resolves (lambda () (fetch-account)) :to-satisfy #'account-ready-p)
(expect-rejects (lambda () (error "missing user")) :to-be-type-of 'simple-error)
(expect-poll (lambda () (current-state job)) (:timeout-ms 200 :interval-ms 10) :to-be :ready)
(expect-assertions 2)
(expect-has-assertions)
```

With matcher syntax, `expect` captures the original S-expression and reports
matcher, actual, expected, negation, and pass metadata through conditions and
reporters. `expect-not` is Vitest-style sugar for matcher assertions that
should fail when the underlying matcher passes; it uses the same structured
failure payload as `(expect value :not matcher ...)`.

`expect-resolves` and `expect-rejects` express asynchronous-style assertions
with Lisp thunks. `expect-resolves` runs a zero-argument function and applies the
matcher to its primary returned value. If the thunk signals a condition, the
assertion fails with `:matcher :resolves` and `:actual` containing `:state`,
`:condition-type`, and `:message`. `expect-rejects` requires the thunk to
signal a condition and then applies the matcher to that condition object; a
normally returned value fails with `:matcher :rejects`.
`expect-poll` repeatedly evaluates a zero-argument thunk until the matcher
passes or the timeout expires. Polling failures report `:matcher :poll` with
structured timeout metadata such as `:attempts`, `:timeout-ms`,
`:interval-ms`, `:last-value`, and optional `:last-condition`.
`expect-assertions` and `expect-has-assertions` are checked at the end of each
test attempt and reset for retries and concurrent tests. Declaration forms do
not count as assertions; executed `expect`, `expect-not`, smart assertions,
and the thunk expectation macros `expect-resolves` and `expect-rejects` count
once.

With no matcher, `expect` treats the form as a smart assertion. Predicate forms
using `=`, `/=`, `<`, `<=`, `>`, `>=`, `eql`, `equal`, `equalp`, `string=`, or
`string-equal` are macro-expanded into single-evaluation operand capture:

```lisp
(expect (= (parse-integer "42") 41))
```

The failure report includes the original predicate and a list of operand forms
with their evaluated values, which is intended to be both REPL-friendly and
AI-friendly. Any other bare form is checked as truthy.

`with-snapshot-updates` enables deterministic external snapshot creation and
updates inside a dynamic scope. For command-line usage,
`CL_WEAVE_UPDATE_SNAPSHOTS=1`, `CL_WEAVE_SNAPSHOT_DIR`, and
`CL_WEAVE_SNAPSHOT_FILE` provide the same dynamic settings for CI and agents.
External snapshot failures report `:snapshot-key`, `:snapshot-file`, `:value`,
`:reason`, and first-difference data through the normal structured assertion
payload, so agents do not need to parse human-readable failure strings.
`:to-match-snapshot-sequence` stores a list or non-string vector of replay
states as deterministic `prefix[n]` snapshot keys, for example `vm/run[0]` and
`vm/run[1]`. Snapshot update mode replaces all entries for that prefix, which
prunes stale states. Verification fails on missing, mismatched, or unexpected
extra stored states and adds `:snapshot-prefix`, `:snapshot-index`, and
`:snapshot-count` to the structured payload.
`snapshot-entries` returns the current external snapshot alist, and
`snapshot-value` returns the serialized value plus a presence flag for one
explicit key. These APIs are intended for replay tools and CI agents that need
to inspect snapshot artifacts without depending on private file readers.

## Built-In Matchers

- `:to-be`
- `:to-equal`
- `:to-equalp`
- `:to-be-one-of`
- `:to-be-truthy`
- `:to-be-falsy`
- `:to-be-null`
- `:to-be-defined`
- `:to-be-nan`
- `:to-satisfy`
- `:to-be-type-of`
- `:to-be-instance-of`
- `:to-contain`
- `:to-match`
- `:to-contain-equal`
- `:to-match-object`
- `:to-have-length`
- `:to-have-property`
- `:to-be-close-to`
- `:to-be-greater-than`
- `:to-be-greater-than-or-equal`
- `:to-be-less-than`
- `:to-be-less-than-or-equal`
- `:to-throw`
- `:to-run-under-ms`
- `:to-allocate-under`
- `:to-have-slot`
- `:to-have-method-specialized-on`
- `:to-expand-to`
- `:to-match-inline-snapshot`
- `:to-match-snapshot`
- `:to-match-snapshot-sequence`
- `:to-have-been-called`
- `:to-have-been-called-times`
- `:to-have-been-called-with`
- `:to-have-been-last-called-with`
- `:to-have-been-nth-called-with`
- `:to-have-returned`
- `:to-have-returned-times`
- `:to-have-returned-with`
- `:to-have-last-returned-with`
- `:to-have-nth-returned-with`
- `:to-have-thrown`

`:to-be-one-of` accepts one candidate collection and passes when the actual
value is `eql` to one of its members. Lists and vectors are treated as candidate
sequences; hash tables use their values. Every candidate collection is limited
to 100,000 entries:

```lisp
(expect :ready :to-be-one-of '(:pending :ready :done))
(expect 2 :to-be-one-of #(1 2 3))
```

Failures report `:value`, `:candidates`, `:test`, `:candidate-count`, and
`:matched-index`, so CI and AI agents can distinguish "candidate missing" from
wrong matcher usage.

`:to-throw` accepts an optional expected condition class designator, message
substring, or predicate function. Failures report `:threw`, `:condition-type`,
and `:message` in `:actual`, plus the normalized throw matcher in `:expected`:

```lisp
(expect (lambda () (error "missing user")) :to-throw 'simple-error)
(expect (lambda () (error "missing user")) :to-throw "missing")
(expect (lambda () (error "missing user"))
        :to-throw
        (lambda (condition)
          (search "user" (princ-to-string condition))))
```

## Custom Matchers

Custom matchers use `defmatcher` or the data-driven
`extend-expect`. Each matcher receives the evaluated actual value and the
remaining expected operands as a list. Return the pass boolean, then optional
reported actual and expected values for structured reporters:

```lisp
(cl-weave:defmatcher :to-have-status (response expected)
  "Checks that a response plist has the expected HTTP status."
  (let ((actual-status (getf response :status))
        (wanted-status (first expected)))
    (values (= actual-status wanted-status)
            actual-status
            wanted-status)))

(expect '(:status 201 :body "created") :to-have-status 201)
```

Macro-based bulk registration keeps related domain matchers together:

```lisp
(cl-weave:expect-extend
  (:to-be-cache-hit (response expected)
    "Checks that a response plist came from cache."
    (declare (ignore expected))
    (let ((state (getf response :cache)))
      (values (eq state :hit)
              `(:cache ,state)
              '(:cache :hit)))))
```

AI agents and generators can emit plain matcher data with `extend-expect`:

```lisp
(cl-weave:extend-expect
 (list
  (list :to-have-status
        (lambda (response expected)
          (let ((actual-status (getf response :status))
                (wanted-status (first expected)))
            (values (= actual-status wanted-status)
                    `(:status ,actual-status)
                    `(:status ,wanted-status))))
        :description
        "Checks that a response plist has the expected HTTP status.")))
```

Matcher metadata is first-class data for AI tools, documentation generators,
and editor integrations:

```lisp
(cl-weave:list-matchers)
;; => ((:name :to-be :description nil)
;;     (:name :to-have-status
;;      :description "Checks that a response plist has the expected HTTP status.")
;;     ...)

(cl-weave:matcher-metadata :to-have-status)
;; => (:name :to-have-status
;;     :description "Checks that a response plist has the expected HTTP status.")
```

`list-matchers` returns **every** registered matcher sorted by name; the two
entries above are representative rather than the literal first elements —
built-in matchers often have a `nil` description, while custom matchers carry
the description you gave `defmatcher`. A resolved `matcher` object also answers
`matcher-name` and `matcher-description` directly, which is what
`matcher-metadata` serializes.

## Performance And Allocation

Performance assertions accept thunks so the measured form is executed exactly
inside the matcher:

```lisp
(expect (lambda () (parse-integer "42")) :to-run-under-ms 5)
(expect (lambda () (loop repeat 10 collect :x)) :to-allocate-under 4096)
```

Each matcher executes its thunk once. If you assert both runtime and allocation,
the body runs once per matcher. Failure reports include `:elapsed-seconds`,
`:elapsed-ms`, `:bytes-consed`, and the returned multiple values in `:values`.
Allocation measurement uses the implementation's byte-consing counter; it is
currently backed by SBCL and fails clearly on implementations that do not expose
one.

## Property Assertions

`:to-match` mirrors Vitest `toMatch(pattern)` for strings. A string pattern
checks substring containment; a function designator acts as a Lisp-native
predicate and passes when it returns a non-`nil` value:

```lisp
(expect "common-lisp" :to-match "lisp")
(expect "Common Lisp"
        :to-match
        (lambda (text)
          (search "Lisp" text)))
```

Failures report the actual `:value`, requested `:pattern`, matching `:mode`,
and normalized `:reason`, so reporters can distinguish non-string actual
values, invalid patterns, predicate errors, and ordinary misses.

`:to-be-nan` mirrors Vitest `toBeNaN()` for floating-point NaN values. It
accepts no expected operands. Failure payloads include `:value`, `:type`,
`:float`, and `:nan`; expected data is `(:predicate :nan :test :float-nan-p)`.

`:to-contain-equal` mirrors Vitest `toContainEqual(value)` for Lisp data. It
checks sequence elements and hash-table values with `equalp`, so structurally
equal lists, vectors, strings, numbers, characters, and nested data pass without
requiring object identity:

```lisp
(expect '((:id 1 :name "Ada") (:id 2 :name "Grace"))
        :to-contain-equal
        '(:id 2 :name "Grace"))
```

Failures report the searched `:container`, expected `:value`, and comparison
`:test`, allowing reporters and agents to explain whether the failure came from
membership or equality semantics.

`:to-match-object` mirrors Vitest `toMatchObject(subset)` for Lisp records.
Expected property lists, association lists, and hash tables are treated as
partial object shapes; actual values may be property lists, association lists,
hash tables, or slot-bearing instances. Nested expected objects are checked
recursively with `equalp`. Expected vectors match actual sequences
element-by-element with the same length and order:

```lisp
(expect '(:user (:name "Ada" :roles #("dev" "ops"))
          :meta :ignored)
        :to-match-object
        '(:user (:roles #("dev" "ops"))))
```

Failures report the original `:value`, requested `:subset`, and a normalized
`:failure` payload with `:path`, `:reason`, `:actual-value`, and
`:expected-value`. This gives humans and agents a stable explanation of the
first divergent property.

`:to-have-property` is Vitest-style `toHaveProperty(path, value?)` for Lisp
data. The path can be a scalar, list, or vector. It traverses property lists,
association lists, hash tables, CLOS slots, and integer sequence indexes:

```lisp
(expect '(:user (:name "Ada" :roles #("dev" "ops")))
        :to-have-property
        '(:user :roles 1)
        "ops")
```

Failures report `:path`, `:present`, and `:value` in `:actual`, plus the
expected path and optional value in `:expected`.

## Close Numeric Assertions

`:to-be-close-to` mirrors Vitest `toBeCloseTo(value, numDigits?)`. The default
digit count is `2`, and a value passes when
`abs(expected - actual) < 10^-digits / 2`:

```lisp
(expect (+ 0.1d0 0.2d0) :to-be-close-to 0.3d0 5)
```

Failures report `:value`, `:expected-value`, `:num-digits`, `:difference`, and
`:threshold`, so reporters can display numeric drift without reparsing strings.

The ordering matchers `:to-be-greater-than`,
`:to-be-greater-than-or-equal`, `:to-be-less-than`, and
`:to-be-less-than-or-equal` accept real expected values and fail cleanly for
non-real actual values. Failure payloads include `:value`, `:expected-value`,
`:matcher`, `:operator`, `:actual-real`, and `:expected-real`.

## MOP Architecture Assertions

MOP architecture assertions let tests describe class and generic-function shape
without ad-hoc reflection helpers:

```lisp
(expect 'widget :to-have-slot 'state)
(expect #'render-widget :to-have-method-specialized-on '(widget stream))
```

These matchers report normalized slot and method-specializer lists through the
structured reporters, which keeps architecture tests AI-readable.

## Soft Assertions

A normal `expect` aborts the test at the first failure. Wrap several
expectations in `with-soft-assertions` to run them all and report every failure
together:

```lisp
(it "validates the whole response"
  (with-soft-assertions
    (expect (status response) :to-be 200)
    (expect (content-type response) :to-equal "application/json")
    (expect (body response) :to-contain "ok")))
```

If the status is wrong *and* the body is missing `"ok"`, both failures are
reported in one run instead of only the first. The block reports them as a
single aggregated failure whose payload carries `:failures` (the count) and
`:details` (one entry per failed expectation).

Only assertion failures are softened — a genuine error (a raised condition,
not an `expect` failure) still aborts the block immediately. This is built on
Common Lisp's condition system: inside the block a failing assertion is
collected and execution simply continues, so no per-expression rewriting is
needed.
