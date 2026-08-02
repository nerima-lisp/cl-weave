(in-package #:cl-weave/test)

(defvar *coverage-fixture-value* :outer)

(defvar *coverage-fixture-events* '(:original))

(defun coverage-fixture-sample-function (value)
  (length value))

(defvar *coverage-fuzz-suite* (cl-weave::make-suite :name "coverage-fuzz-suite"))

(describe
  "macros"
  (it-each
    ((1 2 3) (13 21 34))
    "adds ~A and ~A at macro expansion time"
    (left right total)
    (expect (+ left right) :to-be total))
  (describe-each
    ((3 4 7) (8 13 21))
    "table suite ~A plus ~A"
    (left right total)
    (before-each
      (setf (gethash :table-total *test-context*) total))
    (it
      "runs generated nested cases with fixtures"
      (expect (+ left right) :to-be total)
      (expect (gethash :table-total *test-context*) :to-be total)))
  (describe-each
    ((4 5 9))
    "dot table suite ~A plus ~A"
    (left right total)
    (before-each
      (setf (gethash :dot-table-total *test-context*) total))
    (it-each
      ((:alpha :alpha) (:beta :beta))
      "runs dot generated case ~A"
      (actual expected)
      (expect actual :to-be expected)
      (expect (+ left right) :to-be total)
      (expect (gethash :dot-table-total *test-context*) :to-be total)))
  (it
    "expands expect into the assertion engine"
    (expect
      (macroexpand-1 '(expect (+ 1 1) :to-be 2))
      :to-satisfy
      (lambda (form)
        (tree-contains-p form 'cl-weave::assert-expectation))))
  (it
    "expands expect-not into a negated matcher assertion"
    (expect
      (macroexpand-1 '(expect-not (+ 1 1) :to-be 3))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::assert-expectation)
          (tree-contains-p form :not)
          (tree-contains-p form 'expect-not)))))
  (it
    "expands expect-resolves into canonical expect-resolves"
    (expect
      (macroexpand-1
        '(expect-resolves
          (lambda ()
            :ok)
          :to-be
          :ok))
      :to-satisfy
      (lambda (form)
        (tree-contains-p form 'expect-resolves))))
  (it
    "expands expect-resolves into resolving thunk evaluation"
    (expect
      (macroexpand-1
        '(expect-resolves
          (lambda ()
            :ok)
          :to-be
          :ok))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::call-resolving-expectation-thunk)
          (tree-contains-p form 'expect-resolves)))))
  (it
    "expands expect-rejects into canonical expect-rejects"
    (expect
      (macroexpand-1
        '(expect-rejects
          (lambda ()
            (error "boom"))
          :to-be-type-of
          'simple-error))
      :to-satisfy
      (lambda (form)
        (tree-contains-p form 'expect-rejects))))
  (it
    "expands expect-poll into canonical expect-poll"
    (expect
      (macroexpand-1
        '(expect-poll
          (lambda ()
            :ok)
          :to-be
          :ok))
      :to-satisfy
      (lambda (form)
        (tree-contains-p form 'expect-poll))))
  (it
    "expands expect-rejects into rejecting thunk evaluation"
    (expect
      (macroexpand-1
        '(expect-rejects
          (lambda ()
            (error "boom"))
          :to-be-type-of
          'simple-error))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::call-rejecting-expectation-thunk)
          (tree-contains-p form 'expect-rejects)))))
  (it
    "expands expect-poll into polling thunk evaluation"
    (expect
      (macroexpand-1
        '(expect-poll
          (lambda ()
            :ok)
          (:timeout-ms 10 :interval-ms 0)
          :to-be
          :ok))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::call-polling-expectation-thunk)
          (tree-contains-p form 'expect-poll)
          (tree-contains-p form :timeout-ms)
          (tree-contains-p form :interval-ms)))))
  (it
    "expands expect-extend into the custom matcher registry"
    (expect
      (macroexpand-1
        '(expect-extend
          (:to-be-small
            (actual expected)
            (declare (ignore expected))
            (< actual 10))))
      :to-satisfy
      (lambda (form)
        (and (tree-contains-p form 'extend-expect) (tree-contains-p form :to-be-small)))))
  (it
    "expands smart expect into operand capture"
    (expect
      (macroexpand-1 '(expect (= (+ 1 1) 2)))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::signal-smart-assertion-failure)
          (tree-contains-p form 'cl-weave::operand-report-form)))))
  (it
    "expands with-continuation-result through the CPS value collector"
    (expect
      (macroexpand-1
        '(with-continuation-result
          (result next calledp)
          (funcall producer #'next)
          (list result calledp)))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave:with-continuation-values)
          (tree-contains-p form 'next)
          (tree-contains-p form 'calledp)
          (tree-contains-p form 'result)))))
  (it
    "expands with-continuation-values into a local continuation gate"
    (expect
      (macroexpand-1
        '(with-continuation-values
          (values next calledp)
          (funcall producer #'next)
          values))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'flet)
          (tree-contains-p form 'next)
          (tree-contains-p form 'cl-weave::ensure-continuation-called)
          (tree-contains-p form 'calledp)
          (tree-contains-p form 'values)))))
  (it
    "rejects non-symbol continuation bindings at macro expansion time"
    (expect
      (lambda ()
        (macroexpand '(with-continuation-result (result 42) :not-called result)))
      :to-throw))
  (it
    "expands it-only into focused test registration"
    (expect
      (macroexpand-1 '(it-only "focused" (expect 1 :to-be 1)))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::register-test)
          (tree-contains-p form :focus)))))
  (it
    "expands it options into retry and timeout metadata"
    (expect
      (macroexpand-1
        '(it
          "eventually stable"
          (:retry 2 :timeout-ms 100 :execution-mode :concurrent)
          (expect :ok :to-be :ok)))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::register-test)
          (tree-contains-p form :retry)
          (tree-contains-p form 2)
          (tree-contains-p form :timeout-ms)
          (tree-contains-p form 100)
          (tree-contains-p form :execution-mode)
          (tree-contains-p form :concurrent)))))
  (it
    "expands explicit sequential execution metadata"
    (expect
      (macroexpand-1
        '(it
          "generated sequential case"
          (:execution-mode :sequential)
          (expect :ok :to-be :ok)))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::register-test)
          (tree-contains-p form :execution-mode)
          (tree-contains-p form :sequential)))))
  (it
    "preserves runtime tag expressions in test registration"
    (let ((expansion
          (macroexpand-1
            '(it "tagged" (:tags (list :fast dynamic-tag)) (expect :ok :to-be :ok)))))
      (expect
        expansion
        :to-satisfy
        (lambda (form)
          (and
            (tree-contains-p form 'cl-weave::register-test)
            (tree-contains-p form :tags)
            (tree-contains-p form 'dynamic-tag))))))
  (it
    "preserves watch dependency expressions in test registration"
    (let ((expansion
          (macroexpand-1
            '(it
              "watched"
              (:watch-depends-on (list "../src/parser.lisp" helper))
              (expect :ok :to-be :ok)))))
      (expect
        expansion
        :to-satisfy
        (lambda (form)
          (and
            (tree-contains-p form 'cl-weave::register-test)
            (tree-contains-p form :watch-depends-on)
            (tree-contains-p form 'helper))))))
  (it
    "rejects removed metadata options"
    (dolist (option '(:depends-on :concurrent))
      (expect
        (lambda ()
          (macroexpand-1 `(it "removed metadata" (,option nil) (expect :ok :to-be :ok))))
        :to-throw)))
  (it
    "validates registration macro syntax at expansion time"
    (dolist (case '(((it "duplicate" (:retry 1 :retry 2) t) "Duplicate test option")
          ((it-concurrent "conflict" (:execution-mode :sequential) t)
            "conflicts with fixed mode")
          ((it-skip-each ((1)) "skip ~A" (value) "reason" value)
            "does not accept a test body")
          ((it-todo-each ((1)) "todo ~A" (value) (print value))
            "does not accept a test body")
          ((it-property "bad" ((value)) value) "must have the form (NAME GENERATOR)")
          ((describe-each dynamic-cases "suite ~A" (value) value) "literal proper list")
          ((describe-each ((1)) dynamic-name (value) value) "literal format string")
          ((describe-each (not-a-case) "suite ~A" (value) value)
            "case 0 must be a literal proper list")))
      (destructuring-bind (form message-fragment) case
        (handler-case (progn
            (macroexpand-1 form)
            (error "Expected macro expansion to reject ~S." form))
          (error (condition)
            (expect
              (princ-to-string condition)
              :to-satisfy
              (lambda (message)
                (search message-fragment message))))))))
  (it
    "normalizes a repeated fixed execution mode"
    (let ((expansion
          (macroexpand-1
            '(it-concurrent "parallel" (:execution-mode :concurrent :retry 1) t))))
      (expect
        (loop for tail on expansion
              count (eq (first tail) :execution-mode))
        :to-be
        1)))
  (it
    "rejects non-list and circular suite-each cases at expansion time"
    (dolist (form-factory
        (list
          (lambda ()
            '(describe-each "not cases" "suite ~A" (value) value))
          (lambda ()
            '(describe-each #(1 2) "suite ~A" (value) value))
          (lambda ()
            '(describe-skip-each dynamic-cases "suite ~A" (value)))
          (lambda ()
            '(describe-todo-each dynamic-cases "suite ~A" (value)))
          (lambda ()
            (let ((cases (list (list 1))))
              (setf (cdr cases) cases)
              (list 'describe-each cases "suite ~A" '(value) 'value)))))
      (handler-case (progn
          (macroexpand-1 (funcall form-factory))
          (error "Expected suite-each expansion to reject invalid cases."))
        (error (condition)
          (expect
            (princ-to-string condition)
            :to-satisfy
            (lambda (message)
              (search "literal proper list" message)))))))
  (it
    "rejects malformed it-property bindings at expansion time"
    (expect
      (lambda ()
        (macroexpand-1
          '(cl-weave:it-property "bad bindings shape" ((n (cl-weave:gen-integer)) . 5) n)))
      :to-throw
      "IT-PROPERTY requires BINDINGS to be a literal proper list")
    (expect
      (lambda ()
        (macroexpand-1 '(cl-weave:it-property "malformed binding" ((n)) n)))
      :to-throw
      "must have the form (NAME GENERATOR)"))
  (it
    "restores replaced functions and bindings after temporary mutation"
    (expect (sample-size '(a b c)) :to-be 3)
    (with-replaced-function
      (sample-size
        (lambda (value)
          (+ 10 (length value))))
      (expect (sample-size '(a b c)) :to-be 13))
    (expect (sample-size '(a b c)) :to-be 3)
    (setf *fixture-value* :outer)
    (with-restored-binding
      (*fixture-value*)
      (setf *fixture-value* :inner)
      (expect *fixture-value* :to-be :inner))
    (expect *fixture-value* :to-be :outer)
    (setf *fixture-value* :root
          *fixture-events* '(:original))
    (with-restored-bindings
      ((*fixture-value*) (*fixture-events*))
      (setf *fixture-value* :mutated
            *fixture-events* '(:changed))
      (expect *fixture-value* :to-be :mutated)
      (expect *fixture-events* :to-equal '(:changed)))
    (expect *fixture-value* :to-be :root)
    (expect *fixture-events* :to-equal '(:original))
    (let ((table (make-hash-table :test #'equal)))
      (setf (gethash "keep" table) 1
            (gethash "drop" table) 2)
      (with-restored-hash-table
        (table)
        (remhash "keep" table)
        (setf (gethash "drop" table) 99
              (gethash "add" table) 3)
        (expect (gethash "drop" table) :to-be 99)
        (expect (gethash "add" table) :to-be 3))
      (expect (hash-table-count table) :to-be 2)
      (expect (gethash "keep" table) :to-be 1)
      (expect (gethash "drop" table) :to-be 2)
      (expect (nth-value 1 (gethash "add" table)) :to-be nil))
    (let ((table (make-hash-table :test #'equal)))
      (setf (gethash "persist" table) 1)
      (with-cleared-hash-table
        (table)
        (expect (hash-table-count table) :to-be 0)
        (setf (gethash "ephemeral" table) 2)
        (expect (gethash "ephemeral" table) :to-be 2))
      (expect (hash-table-count table) :to-be 1)
      (expect (gethash "persist" table) :to-be 1)
      (expect (nth-value 1 (gethash "ephemeral" table)) :to-be nil))
    (let* ((table (make-hash-table :test #'equal))
           (tables (vector table))
           (place-evaluations 0))
      (setf (gethash "persist" table) 1)
      (with-cleared-hash-table
        ((aref
            tables
            (progn
              (incf place-evaluations)
              0)))
        (expect place-evaluations :to-be 1)
        (expect (hash-table-count table) :to-be 0))
      (expect place-evaluations :to-be 1)
      (expect (gethash "persist" table) :to-be 1)))
  (it
    "exercises fixture restoration macro expansion via a fresh invocation"
    (setf *coverage-fixture-value* :outer)
    (eval
      '(cl-weave::with-restored-binding
        (*coverage-fixture-value*)
        (setf *coverage-fixture-value* :inner)))
    (expect *coverage-fixture-value* :to-be :outer)
    (setf *coverage-fixture-events* '(:original))
    (eval
      '(cl-weave::with-restored-bindings
        ((*coverage-fixture-value*) (*coverage-fixture-events*))
        (setf *coverage-fixture-value* :mutated
              *coverage-fixture-events* '(:changed))))
    (expect *coverage-fixture-value* :to-be :outer)
    (expect *coverage-fixture-events* :to-equal '(:original))
    (expect (coverage-fixture-sample-function '(a b c)) :to-be 3)
    (eval
      '(cl-weave::with-replaced-function
        (coverage-fixture-sample-function
          (lambda (value)
            (+ 10 (length value))))
        (funcall 'coverage-fixture-sample-function '(a b c))))
    (expect (coverage-fixture-sample-function '(a b c)) :to-be 3)
    (let ((table (make-hash-table :test #'equal)))
      (setf (gethash "keep" table) 1)
      (eval
        `(let ((table ,table))
          (cl-weave::with-restored-hash-table
            (table)
            (remhash "keep" table)
            (setf (gethash "add" table) 3))))
      (expect (hash-table-count table) :to-be 1)
      (expect (gethash "keep" table) :to-be 1))
    (let ((table (make-hash-table :test #'equal)))
      (setf (gethash "keep" table) 1)
      (eval
        `(let ((table ,table))
          (cl-weave::with-cleared-hash-table
            (table)
            (setf (gethash "temp" table) 1))))
      (expect (hash-table-count table) :to-be 1)
      (expect (gethash "keep" table) :to-be 1)))
  (it
    "expands it-concurrent into concurrent test registration"
    (expect
      (macroexpand-1
        '(it-concurrent "parallel case" (:retry 1) (expect :ok :to-be :ok)))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::register-test)
          (tree-contains-p form :execution-mode)
          (tree-contains-p form :concurrent)
          (tree-contains-p form :retry)))))
  (it
    "expands it-sequential into sequential test registration"
    (expect
      (macroexpand-1
        '(it-sequential "serial case" (:retry 1) (expect :ok :to-be :ok)))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::register-test)
          (tree-contains-p form :execution-mode)
          (tree-contains-p form :sequential)
          (tree-contains-p form :retry)))))
  (it
    "expands it-fails into expected-failure registration"
    (expect
      (macroexpand-1
        '(it-fails "known bug" (:retry 1 :timeout-ms 100) (expect 1 :to-be 2)))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::register-test)
          (tree-contains-p form :expected-failure-reason)
          (tree-contains-p form :retry)
          (tree-contains-p form :timeout-ms)))))
  (it
    "expands describe-skip into skipped suite registration"
    (expect
      (macroexpand-1
        '(describe-skip "blocked" "upstream gap" (it "case" (expect 1 :to-be 1))))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::register-suite)
          (tree-contains-p form :skip-reason)
          (tree-contains-p form "upstream gap")))))
  (it
    "expands describe-todo into todo suite registration"
    (expect
      (macroexpand-1
        '(describe-todo "pending" "needs design" (it "case" (expect 1 :to-be 1))))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::register-suite)
          (tree-contains-p form :todo-reason)
          (tree-contains-p form "needs design")))))
  (it
    "expands describe execution mode macros into suite metadata"
    (expect
      (macroexpand-1
        '(describe-concurrent "parallel suite" (it "case" (expect 1 :to-be 1))))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::register-suite)
          (tree-contains-p form :execution-mode)
          (tree-contains-p form :concurrent))))
    (expect
      (macroexpand-1
        '(describe-sequential "serial suite" (it "case" (expect 1 :to-be 1))))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::register-suite)
          (tree-contains-p form :execution-mode)
          (tree-contains-p form :sequential)))))
  (it
    "expands conditional test registration into run and skip branches"
    (expect
      (macroexpand-1
        '(it-skip-if
          expensivep
          "conditional case"
          (:retry 2 :timeout-ms 100)
          (expect :ok :to-be :ok)))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'if)
          (tree-contains-p form 'it-skip)
          (tree-contains-p form 'it)
          (tree-contains-p form :retry)
          (tree-contains-p form :timeout-ms)))))
  (it
    "expands conditional suite registration into run and skip branches"
    (expect
      (macroexpand-1
        '(describe-run-if
          (member :sbcl *features*)
          "conditional suite"
          (it "case" (expect :ok :to-be :ok))))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'if)
          (tree-contains-p form 'describe)
          (tree-contains-p form 'describe-skip)
          (tree-contains-p form "conditional run-if")))))
  (it
    "expands describe-each into independent suites"
    (expect
      (macroexpand-1
        '(describe-each
          ((1 2 3))
          "suite ~A"
          (left right total)
          (it "adds" (expect (+ left right) :to-be total))))
      :to-satisfy
      (lambda (form)
        (and
          (tree-contains-p form 'cl-weave::describe)
          (tree-contains-p form 'destructuring-bind)))))
  (it
    "does not export removed legacy aliases"
    (dolist (name '("IT.CONCURRENT" "TEST.ONLY" "DESCRIBE.EACH" "VI.FN"))
      (expect (nth-value 1 (find-symbol name :cl-weave)) :not :to-be :external)))
  (it
    "compares a single macroexpansion step"
    (expect
      '(sample-unless
        ready
        (setf *fixture-value* :done))
      :to-expand-to
      '(if ready nil
        (progn
          (setf *fixture-value* :done)))))
  (it
    "reports the expanded form when to-expand-to fails"
    (handler-case (progn
        (expect
          '(sample-unless
            ready
            (setf *fixture-value* :done))
          :to-expand-to
          '(when ready
            (setf *fixture-value* :done)))
        (error "Expected to-expand-to to fail."))
      (cl-weave:assertion-failure (condition)
        (let ((detail (cl-weave::failure-detail condition)))
          (expect
            (cl-weave::assertion-detail-actual detail)
            :to-equal
            '(if ready nil
              (progn
                (setf *fixture-value* :done))))
          (expect
            (cl-weave::assertion-detail-expected detail)
            :to-equal
            '(when ready
              (setf *fixture-value* :done))))))))

(describe
  "trusted empty test registration"
  (it
    "marks only macro-generated strictly empty bodies"
    (let ((cl-weave::*root-suite* nil)
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test (function equal)))
          (cl-weave::*registration-owners* (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (let ((empty (it "empty probe"))
            (explicit-nil (it "explicit nil probe" nil))
            (constructed
            (cl-weave::make-test-case
              :name
              "constructed probe"
              :function
              (lambda ())))
            (registered
            (cl-weave::register-test
              "directly registered probe"
              (lambda ()))))
        (expect
          (eq
            (cl-weave::test-case-function empty)
            (cl-weave::test-case-trusted-empty-function empty))
          :to-be
          t)
        (expect (cl-weave::test-case-trusted-empty-function explicit-nil) :to-be nil)
        (expect (cl-weave::test-case-trusted-empty-function constructed) :to-be nil)
        (expect (cl-weave::test-case-trusted-empty-function registered) :to-be nil))))
  (it
    "invalidates trust when the registered function is replaced"
    (let ((cl-weave::*root-suite* nil)
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test (function equal)))
          (cl-weave::*registration-owners* (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (let* ((test (it "mutable empty probe"))
             (marker (cl-weave::test-case-trusted-empty-function test)))
        (expect (eq (cl-weave::test-case-function test) marker) :to-be t)
        (setf (cl-weave::test-case-function test) (lambda ()
            :replacement))
        (expect (eq (cl-weave::test-case-function test) marker) :to-be nil))))
  (it
    "refreshes the marker when an empty test is redefined"
    (let ((cl-weave::*root-suite* nil)
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test (function equal)))
          (cl-weave::*registration-owners* (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (let* ((original (it "redefined empty probe"))
             (original-function (cl-weave::test-case-function original))
             (replacement (it "redefined empty probe"))
             (replacement-function (cl-weave::test-case-function replacement)))
        (expect
          (eq original-function (cl-weave::test-case-trusted-empty-function original))
          :to-be
          t)
        (expect
          (eq
            replacement-function
            (cl-weave::test-case-trusted-empty-function replacement))
          :to-be
          t)
        (expect (eq replacement-function original-function) :to-be nil)))))

(describe
  "model record and suite-hook macros"
  (it
    "exercises define-record-class expansion via a fresh invocation"
    (eval '(cl-weave::define-record-class coverage-fuzz-record (alpha beta)))
    (let* ((constructor (intern "MAKE-COVERAGE-FUZZ-RECORD"))
           (predicate (intern "COVERAGE-FUZZ-RECORD-P"))
           (instance (funcall constructor :alpha 1 :beta 2)))
      (expect (funcall predicate instance) :to-be-truthy)
      (expect (funcall predicate 42) :to-be nil)
      (expect (slot-value instance 'alpha) :to-be 1)
      (expect (slot-value instance 'beta) :to-be 2)))
  (it
    "exercises every suite-hook branch via a fresh invocation"
    (expect
      (eval '(cl-weave::suite-hook *coverage-fuzz-suite* before-all))
      :to-be
      (cl-weave::suite-before-all *coverage-fuzz-suite*))
    (expect
      (eval '(cl-weave::suite-hook *coverage-fuzz-suite* after-all))
      :to-be
      (cl-weave::suite-after-all *coverage-fuzz-suite*))
    (expect
      (eval '(cl-weave::suite-hook *coverage-fuzz-suite* before-each))
      :to-be
      (cl-weave::suite-before-each *coverage-fuzz-suite*))
    (expect
      (eval '(cl-weave::suite-hook *coverage-fuzz-suite* around-each))
      :to-be
      (cl-weave::suite-around-each *coverage-fuzz-suite*))
    (expect
      (eval '(cl-weave::suite-hook *coverage-fuzz-suite* after-each))
      :to-be
      (cl-weave::suite-after-each *coverage-fuzz-suite*))))

(describe
  "test plan entry positional constructor"
  (it
    "constructs test plan entries with the same values and identities"
    (let* ((path (list :path))
           (status (list :status))
           (reason (list :reason))
           (focused (list :focused))
           (retry (list :retry))
           (timeout-ms (list :timeout-ms))
           (concurrent (list :concurrent))
           (location (list :location))
           (tags (list :tags))
           (values
          (list path status reason focused retry timeout-ms concurrent location tags))
           (record
          (cl-weave::make-test-plan-entry-record
            path
            status
            reason
            focused
            retry
            timeout-ms
            concurrent
            location
            tags))
           (ordinary
          (cl-weave::make-test-plan-entry
            :path
            path
            :status
            status
            :reason
            reason
            :focused
            focused
            :retry
            retry
            :timeout-ms
            timeout-ms
            :concurrent
            concurrent
            :location
            location
            :tags
            tags))
           (accessors
          (list
            (function cl-weave::test-plan-entry-path)
            (function cl-weave::test-plan-entry-status)
            (function cl-weave::test-plan-entry-reason)
            (function cl-weave::test-plan-entry-focused)
            (function cl-weave::test-plan-entry-retry)
            (function cl-weave::test-plan-entry-timeout-ms)
            (function cl-weave::test-plan-entry-concurrent)
            (function cl-weave::test-plan-entry-location)
            (function cl-weave::test-plan-entry-tags))))
      (expect (eq (class-of record) (class-of ordinary)) :to-be t)
      (loop for accessor in accessors
            for value in values
            do (expect (eq (funcall accessor record) value) :to-be t) (expect (eq (funcall accessor record) (funcall accessor ordinary)) :to-be t))))
  (it
    "runs initialize-instance once while collecting a plan"
    (let* ((generic-function (fdefinition (quote initialize-instance)))
           (specializers (list (find-class (quote cl-weave::test-plan-entry))))
           (previous-method (find-method generic-function (list :after) specializers nil))
           (probe-symbol (gensym "TEST-PLAN-ENTRY-INITIALIZE-PROBE-"))
           (count-indicator (gensym "CALL-COUNT-"))
           (method nil))
      (unwind-protect (progn
          (remprop probe-symbol count-indicator)
          (setf method (eval
              `(defmethod initialize-instance :after ((instance cl-weave::test-plan-entry) &rest initargs &key &allow-other-keys)
                (declare (ignore instance initargs))
                (incf (get (quote ,probe-symbol) (quote ,count-indicator) 0)))))
          (let ((root (cl-weave::make-suite :name "root")))
            (cl-weave::add-child
              root
              (cl-weave::make-test-case
                :name
                "case"
                :function
                (lambda ()
                  t)))
            (expect (length (cl-weave:collect-test-plan root)) :to-be 1)
            (expect (get probe-symbol count-indicator 0) :to-be 1)))
        (when method
          (remove-method generic-function method))
        (when previous-method
          (add-method generic-function previous-method))
        (remprop probe-symbol count-indicator)))))
