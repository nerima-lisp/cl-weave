# DSL Guide

## Suites And Cases

```lisp
(describe "suite name"
  (it "case name"
    (expect ...)))
```

`describe` forms can be nested. Tests are registered when the file is loaded.
Because Common Lisp already exports `CL:DESCRIBE`, test packages should import
`cl-weave:describe` with `:shadowing-import-from`.

## Table Tests

```lisp
(it-each ((1 2 3)
          (13 21 34))
    "adds ~A and ~A"
    (left right total)
  (expect (+ left right) :to-be total))

(describe-each ((:json "application/json")
                (:sexp "application/s-expression"))
    "~A reporter"
    (reporter content-type)
  (it "declares its content type"
    (expect content-type :to-satisfy #'stringp)))

(describe-each ((:json "application/json"))
    "~A reporter with fixtures"
    (reporter content-type)
  (before-each
    (setf (gethash :content-type *test-context*) content-type))
  (it-each ((:ok :ok))
      "runs generated case ~A"
      (actual expected)
    (expect actual :to-be expected)))

(it-only-each ((1 2 3))
    "focuses generated case ~A and ~A"
    (left right total)
  (expect (+ left right) :to-be total))

(it-skip-each ((:slow :case))
    "skips generated case ~A"
    (kind label)
  "blocked by upstream")

(it-todo-each ((:parser :stream) (:ffi :crash-boundary))
    "documents generated todo ~A"
    (area label)
  "needs design")
```

`it-each` expands into independent `it` forms at macro expansion time.
`describe-each` expands into independent `describe` forms, so nested
fixtures and cases keep the same semantics as hand-written suites. Table forms
compose with canonical modifiers such as `it-only-each`,
`it-concurrent-each`, `it-sequential-each`, `it-fails-each`, `it-skip-each`,
and `it-todo-each`, and with the suite-level table variants
`describe-only-each`, `describe-skip-each`, and `describe-todo-each`. Fixture
hooks use the canonical Lisp names.
[ai-contract.md](ai-contract.md) is the machine-readable normalization
contract for agents. Runtime metadata also exposes `referenceDocuments`,
`supportChannels`, `securityContacts`, `lifecycle`,
`runtimeSupport`, and `releaseProcess` so external tools can discover
canonical docs, support routing, disclosure paths,
platform support, release policy, and project status without scraping prose.

## Conditional Runs

```lisp
(it-skip-if (not (probe-file #P"/tmp/service.sock"))
    "talks to a local service"
  (expect (probe-file #P"/tmp/service.sock") :to-be-truthy))

(it-run-if (member :sbcl *features*)
    "uses SBCL allocation counters"
  (expect (lambda () (list :ok)) :to-allocate-under 4096))

(describe-run-if (member :linux *features*)
    "linux-only integration"
  (it "checks a platform boundary"
    (expect :ok :to-be :ok)))
```

`it-skip-if` and `describe-skip-if` register skipped tests or suites when the
condition is true. `it-run-if` and `describe-run-if` register skipped tests or
suites when the condition is false.
Conditions are evaluated while the test file registers tests; skipped branches
emit ordinary `:skip` events with deterministic reasons, and their hooks and
bodies are not executed.

## Fixtures

```lisp
(defvar *state*)

(describe "with fixture"
  (before-all
    (setf *state* (make-hash-table)))

  (before-all
    (setf (gethash :created *state*) t))

  (before-each
    (setf (gethash :trace *state*) nil))

  (around-each (next)
    (let ((*state* *state*))
      (unwind-protect
           (funcall next)
        (remhash :scratch *state*))))

  (after-each
    (remhash :trace *state*))

  (after-all
    (setf *state* nil))

  (it "uses dynamic state"
    (setf (gethash :x *state*) 1)
    (expect (gethash :x *state*) :to-be 1)))
```

`before-all` / `after-all` bodies run once around a suite. `before-each` /
`after-each` bodies run around every test in the current suite and nested suites.
`around-each` receives a continuation for the remaining around hooks and test
body, so special variables can be dynamically rebound around only the case.
Use `unwind-protect` inside `around-each` when the fixture owns cleanup.
`after-each` and `after-all` teardown runs even when a test body or hook exits
non-locally — including SBCL timeouts and debugger restarts — so fixtures that
release resources in a teardown hook are not skipped when a case times out.
When a hook itself fails, cl-weave signals a `hook-failure` condition whose
readers `hook-failure-phase` and `hook-failure-causes` identify which lifecycle
phase failed and the underlying conditions it collected.
Fixture hooks intentionally use canonical Lisp names rather than camelCase
aliases, because Common Lisp uppercases unescaped symbols while reading source.

## CPS Continuation Helpers

Use `with-continuation-result` when testing callback/CPS APIs that receive a
continuation function. The macro binds the continuation name supplied in the
binding list, runs the form, asserts that the continuation was called, and then
exposes the first value passed to it.

```lisp
(it "tests a CPS parser"
  (with-continuation-result (node next calledp)
      (parse-token-cps "42" #'next)
    (expect calledp :to-be-truthy)
    (expect node :to-equal '(:number 42))))
```

Use `with-continuation-values` when the continuation carries multiple values:

```lisp
(with-continuation-values (values next)
    (decode-cps input #'next)
  (expect values :to-equal '(:ok (:amount 100))))
```

## Skipping

```lisp
(describe-skip "upstream-dependent suite" "waiting for upstream behavior"
  (it "documents a blocked case"
    (expect :unreachable :to-be :reachable)))

(it-skip "documents a pending case" "waiting for upstream behavior")
```

Skipped suites report selected descendant cases as `:skip` without running suite
hooks or test bodies. Skipped cases use the same event status and do not fail
`run-all`.

## Focus And Todo

```lisp
(describe-only "focused suite"
  (it "runs inside focused suite"
    (expect :selected :to-be :selected)))

(it-only "focuses a single case"
  (expect (+ 40 2) :to-be 42))

(it-todo "documents a missing edge case" "needs property generator")
(it-todo-each ((:ast) (:ffi))
    "documents future coverage for ~A"
    (area)
  "needs generator")

(describe-todo "future protocol" "needs design"
  (it "documents the expected shape"
    (expect :draft :to-be :stable)))

(describe-todo-each ((:json) (:sexp))
    "future ~A reporter"
    (reporter)
  "needs snapshot contract"
  (it "documents pending reporter behavior"
    (expect reporter :to-satisfy #'keywordp)))
```

When any suite or case is focused, `run-all` executes only the focused path.
Todo suites report selected descendant cases as `:todo` without running suite
hooks or test bodies. Todo cases use the same event status and do not fail
`run-all`.

## Retry And Timeout

```lisp
(it "eventually observes an external state" (:retry 2 :timeout-ms 500)
  (expect (probe-state) :to-be :ready))

(it "supports retry options" (:retry 1)
  (expect (+ 20 22) :to-be 42))

(it-fails "documents a known parser bug" (:retry 1)
  (expect (parse-fragment input) :to-be :accepted))
```

`:retry` is the number of extra attempts after the first attempt. Fixtures and
dynamic `*test-context*` are recreated for every attempt. `:timeout-ms` fails the
case if a single attempt exceeds the configured wall-clock budget. Timeout
failures are reported as `test-timeout` conditions.

CLI and CI runs can set suite-wide defaults with `--retry`,
`CL_WEAVE_RETRY`, `--test-timeout-ms`, `CL_WEAVE_TEST_TIMEOUT_MS`,
`CL_WEAVE_TEST_TIMEOUT`, `--max-workers`, or `CL_WEAVE_MAX_WORKERS`. Per-test
options take priority over
global defaults, so `:retry 0` disables a global retry budget for one case,
`:timeout-ms` replaces the global per-attempt timeout, and `--max-workers`
bounds adjacent concurrent worker batches.

`it-fails` inverts one runnable case only when its test attempt signals
`assertion-failure`. An implementation error or timeout remains visible as
`:error` or `:fail`; an unexpectedly passing body is reported as `:fail` with
`expected-failure-missed`.

## Interactive Restarts

Every runnable attempt installs Common Lisp restarts while the body and
`before-each` / `after-each` hooks are active:

```lisp
(handler-bind ((cl-weave:assertion-failure
                 (lambda (condition)
                   (declare (ignore condition))
                   (invoke-restart 'cl-weave:retry-test))))
  (cl-weave:run-all))
```

`continue-test` records the current attempt as `:pass`, `skip-test` records it
as `:skip` with an optional reason, and `retry-test` reruns the attempt while
consuming the configured `:retry` budget. If no handler or debugger invokes a
restart, CI behavior is unchanged and the original failure, error, or timeout is
reported normally.

## Concurrent Tests

```lisp
(it-concurrent "fetches account metadata" (:timeout-ms 1000)
  (expect (fetch-account) :to-satisfy #'account-ready-p))

(it "uses option form when macros generate cases" (:execution-mode :concurrent :retry 1)
  (expect (probe-cache) :to-be :warm))

(describe-concurrent "parallel-safe API checks"
  (it "fetches account" (expect (fetch-account) :to-satisfy #'account-ready-p))
  (it-sequential "uses shared rate-limit bucket"
    (expect (probe-rate-limit) :to-be :available)))
```

`it-concurrent` and `(:execution-mode :concurrent)` mark a case as safe
to run beside adjacent concurrent cases. `describe-concurrent` sets the same
execution mode for descendant cases, and
`it-sequential` opts a single case back out. `describe-sequential` is the
suite-level inverse — it forces sequential execution for its descendants, which
is useful for nesting a serial group inside an otherwise concurrent parent.
Report order
stays deterministic: events are emitted in the selected definition order. When
`:bail` is enabled, concurrent batching is disabled so fast-fail behavior
remains exact. `run-all :max-workers N`, `--max-workers N`, and
`CL_WEAVE_MAX_WORKERS=N` bound the number of worker threads used for each
adjacent concurrent batch.
