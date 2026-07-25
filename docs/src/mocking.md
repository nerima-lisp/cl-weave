# Mocking

```lisp
(let ((add (make-mock-function (lambda (left right)
                                 (+ left right)))))
  (expect (funcall add 1 2) :to-be 3)
  (expect (funcall add 5 8) :to-be 13)
  (expect add :to-have-been-called)
  (expect add :to-have-been-called-times 2)
  (expect add :to-have-been-called-with 1 2)
  (expect add :to-have-been-nth-called-with 1 1 2)
  (expect add :to-have-been-last-called-with 5 8)
  (expect add :to-have-returned)
  (expect add :to-have-returned-times 2)
  (expect add :to-have-returned-with 3)
  (expect add :to-have-nth-returned-with 1 3)
  (expect add :to-have-last-returned-with 13)
  (expect (mock-calls add) :to-equal '((1 2) (5 8)))
  (expect (mock-results add)
          :to-equal
          '((:type :return :value 3 :values (3))
            (:type :return :value 13 :values (13))))
  (clear-mock add))

(with-mocked-functions (((symbol-function 'now) (lambda () 0)))
  (expect (now) :to-be 0))

(let ((spy (spy-on 'now)))
  (mock-return-value spy 42)
  (expect (now) :to-be 42)
  (mock-restore spy))
```

`make-mock-function` creates an inspectable function object. `mock-function-p`
tests whether a value is a registered cl-weave mock without signalling on
non-functions. `mock-calls` returns a copy
of the recorded argument lists, `mock-results` returns return/throw reports,
and `clear-mock` resets both histories for one mock. `reset-mock` resets
histories and replaces that mock's implementation with
the default no-op function.
`dispose-mock` clears retained history references and unregisters a mock when
it is no longer needed. A disposed mock cannot be inspected or called. Active
spies must be restored with `mock-restore` before they can be disposed; this
also applies to pending frames in nested spy stacks. Calling a disposed mock
signals `mock-disposed-error` (reader `mock-disposed-error-mock`); disposing an
active spy signals `active-spy-disposal-error` (readers
`active-spy-disposal-error-mock` and `active-spy-disposal-error-symbol`).
`mock-implementation` replaces an existing mock's active implementation.
`mock-return-value` pins a single return value, while `mock-return-values` pin
Common Lisp multiple values.
`clear-all-mocks` resets histories for every registered mock without replacing
their implementations; `reset-all-mocks` applies the reset behavior to every
registered mock. `spy-on` replaces a symbol's function cell with a registered mock
that calls the original function by default. `mock-restore` restores that
function cell when it is still bound to the spy,
reset the spy history, and restore the spy implementation to the original
function. `restore-all-mocks` applies that behavior to every active spy while
leaving regular mocks untouched.
`:to-have-returned-with` accepts Common Lisp multiple values as matcher
operands, for example
`(expect mock :to-have-returned-with :ok 42)`. Nth mock matchers use one-based
indices. Nth returned matchers count only successful returns, while
`mock-results` still keeps thrown result reports.

`with-mocked-functions` temporarily rewrites global function cells. The
original function cells are restored with `unwind-protect`.

When the execution journal is enabled, every mock invocation — whether from
`make-mock-function`, `spy-on`, or `with-mocked-functions` — is recorded as a
`:mock-call` frame carrying its arguments, so mock calls appear interleaved with
assertions on the time-travel timeline. See
[Time-Travel Debugging](time-travel-debugging.md).
