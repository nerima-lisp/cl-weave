(in-package #:cl-weave/spec-test)

;;;; Self-verification of the attempt runner (FR-014, area "attempt retry and
;;;; timeout"). ATTEMPT-SPEC is an abstract model of src/runner-attempts.lisp:
;;;; RUN-TEST-ATTEMPTS, CALL-WITH-ATTEMPT-OUTCOME/K, EXPECTED-FAILURE-EVENT and
;;;; the restarts of CALL-TEST-ATTEMPT/RESTARTS. It is explored exhaustively,
;;;; broken variants prove the properties can fail, and the real runner is
;;;; driven from outside and compared with the model step by step.
;;;;
;;;; Model, read from the runner:
;;;;   - A test with RETRY = r runs at most r + 1 attempts: the first attempt
;;;;     plus r retries, so RETRY counts additional attempts.
;;;;   - Each attempt ends in one OUTCOME. A failed (:fail, :error, :timeout,
;;;;     :retry-restart) attempt is retried while budget remains; one retry
;;;;     costs one budget unit. :pass, :continue-restart and :skip finish the
;;;;     run at once.
;;;;   - With an expected-failure reason, an assertion failure becomes a pass,
;;;;     but a pass becomes a retryable failure (expected-failure-missed).
;;;;     Errors and timeouts are not assertion failures and stay failures.
;;;;   - A timeout is a :fail event, so it is retried like any failure.
;;;;   - The :retry-restart restart with no budget left ends in :error.
;;;;   - A skip or todo reason runs no attempt at all (STATIC).
;;;; Not modelled: hook failures and secondary after-each conditions, the
;;;; *default-retry* fallback, the trusted-empty fast path and the interactive
;;;; runner.
;;;;
;;;; Variables: ATTEMPTS finished attempts, BUDGET retries still available,
;;;; FINAL the terminal event status or NIL while the run continues.
;;;;
;;;; Time never enters: a timeout is a scripted outcome delivered through the
;;;; runner's own *platform-timeout-caller* hook, so no timer is armed.

(defparameter *attempt-outcomes*
  '(:pass :continue-restart :fail :error :timeout :skip :retry-restart))

(defun attempt-classify (outcome expected-failure bug)
  "Return (KIND STATUS): KIND is :terminal or :retryable, STATUS the event
status the attempt ends in (for :retryable, the status if no budget is left)."
  (ecase outcome
    ((:pass :continue-restart)
     (if expected-failure '(:retryable :fail) '(:terminal :pass)))
    (:fail (if expected-failure '(:terminal :pass) '(:retryable :fail)))
    (:error '(:retryable :error))
    (:timeout (if (eq bug :timeout-terminal) '(:terminal :fail) '(:retryable :fail)))
    (:skip '(:terminal :skip))
    (:retry-restart '(:retryable :error))))

(defun attempt-step (outcome budget expected-failure bug)
  "Return (NEXT-BUDGET NEXT-FINAL) for one attempt. BUG selects a deliberately
wrong variant: :over-budget retries once too often, :unbounded retries at zero
budget without charging it, :timeout-terminal never retries a timeout."
  (destructuring-bind (kind status) (attempt-classify outcome expected-failure bug)
    (let ((can-retry (ecase bug
                       ((nil :timeout-terminal) (plusp budget))
                       (:over-budget (>= budget 0))
                       (:unbounded t))))
      (cond ((eq kind :terminal) (list budget status))
            (can-retry (list (if (eq bug :unbounded) (max 0 (1- budget)) (1- budget)) nil))
            (t (list budget status))))))

(defspec attempt-spec ((retry 2) (expected-failure nil) (bug nil) (static nil))
  (:variables attempts budget final)
  (:init (attempts 0) (budget retry) (final static))
  (:action attempt
    (:for (outcome *attempt-outcomes*))
    (:guard (null final))
    (:next (attempts (1+ attempts))
           (budget (first (attempt-step outcome budget expected-failure bug)))
           (final (second (attempt-step outcome budget expected-failure bug)))))
  (:invariant attempts-within-budget (<= attempts (1+ retry)))
  (:invariant give-up-only-when-exhausted
    (or (not (member final '(:fail :error))) (zerop budget)))
  (:invariant budget-conserved
    (= (+ attempts budget) (+ retry (if (and final (plusp attempts)) 1 0))))
  (:action-property retry-charges-one-budget-unit
    (or (next final)
        (and (= (next attempts) (1+ attempts)) (= (next budget) (1- budget)))))
  (:temporal eventually-finishes (:eventually (not (null final))))
  (:fairness (:weak attempt))
  (:deadlock-check nil))

(defun attempt-spec-without-fairness (spec)
  (make-spec :name (spec-name spec) :constants (spec-constants spec)
             :variables (spec-variables spec) :init (spec-init spec)
             :actions (spec-actions spec) :invariants (spec-invariants spec)
             :action-properties (spec-action-properties spec)
             :temporal-properties (spec-temporal-properties spec)
             :check-deadlock nil))

(defun attempt-successor-table (spec attempts budget)
  "List of (OUTCOME ATTEMPTS BUDGET FINAL) for every successor of the
nonfinal state (ATTEMPTS BUDGET NIL)."
  (mapcar (lambda (transition)
            (let ((to (spec-transition-to transition)))
              (list (first (spec-transition-params transition))
                    (getf to 'attempts) (getf to 'budget) (getf to 'final))))
          (spec-successors spec (make-state spec (list 'attempts attempts
                                                       'budget budget 'final nil)))))

(defun attempt-violation-summary (result)
  (let ((violation (spec-result-violation result)))
    (list (spec-violation-kind violation)
          (spec-violation-property violation)
          (length (spec-violation-trace violation)))))

;;; The system under test: the real attempt runner, driven from outside. The
;;; runner executes all attempts of a test in one call, so each operation
;;; replays the scripted outcomes from scratch. When the script runs out, the
;;; test body throws out of the runner: that observes "the runner wants another
;;; attempt" without running it. The budget is read from the runner's own
;;; *retry-budget-remaining* at the start of the last attempt, which equals the
;;; budget after the last attempt because finishing never charges it.

(define-condition simulated-timeout (serious-condition) ()
  (:documentation "Stands for the platform's raw timeout interrupt."))

(defstruct (attempt-sut (:constructor %make-attempt-sut))
  retry expected-failure static defect (script '()) observation)

(defun attempt-perform (outcome)
  (ecase outcome
    (:pass nil)
    (:continue-restart (invoke-restart 'cl-weave::continue-test))
    (:fail (expect :actual :to-be :expected))
    (:error (error "scripted error"))
    (:timeout (error 'simulated-timeout))
    (:skip (invoke-restart 'cl-weave::skip-test "scripted skip"))
    (:retry-restart (invoke-restart 'cl-weave::retry-test))))

(defun attempt-timeout-caller (defect)
  ;; Same shape as the SBCL caller in src/platform-sbcl.lisp, with a scripted
  ;; condition in place of sb-ext:timeout and no timer.
  (lambda (timeout callable continue)
    (declare (ignore timeout))
    (handler-case (funcall continue (funcall callable))
      (simulated-timeout ()
        (if (eq defect :timeout-as-error)
            (error "timeout surfaced as a generic error")
            (error 'cl-weave::platform-timeout))))))

(defun attempt-run (script &key retry expected-failure static defect)
  "Run one real test through RUN-TEST-CASE. Return (VALUES EVENT INVOCATIONS
BUDGET); EVENT is NIL when the runner asked for an attempt beyond SCRIPT."
  (let* ((pending (copy-list script))
         (invocations 0)
         (budget nil)
         (test (cl-weave::make-test-case
                :name "scripted attempts"
                :retry (if (eq defect :retry-plus-one) (1+ retry) retry)
                :timeout-ms 1000
                :expected-failure-reason (and expected-failure "known failure")
                :skip-reason (and (eq static :skip) "skipped")
                :todo-reason (and (eq static :todo) "todo")
                :function (lambda ()
                            (incf invocations)
                            (setf budget cl-weave::*retry-budget-remaining*)
                            (if pending
                                (attempt-perform (pop pending))
                                (throw 'attempt-pending nil)))))
         (event (let ((cl-weave::*platform-capabilities*
                        (adjoin :timeout cl-weave::*platform-capabilities*))
                      (cl-weave::*platform-timeout-caller* (attempt-timeout-caller defect))
                      (cl-weave::*platform-timeout-condition-predicate*
                        (lambda (condition) (typep condition 'simulated-timeout))))
                  (catch 'attempt-pending
                    (cl-weave::run-test-case (cl-weave::make-suite :name "attempt suite")
                                             test)))))
    (values event invocations (or budget (cl-weave::retry-count test)))))

(defun attempt-sut-observe (sut)
  (multiple-value-bind (event invocations budget)
      (attempt-run (attempt-sut-script sut)
                   :retry (attempt-sut-retry sut)
                   :expected-failure (attempt-sut-expected-failure sut)
                   :static (attempt-sut-static sut)
                   :defect (attempt-sut-defect sut))
    ;; Without an event the last invocation was the probe, not an attempt.
    (list 'attempts (if event invocations (1- invocations))
          'budget budget
          'final (and event (cl-weave::test-event-status event)))))

(defun make-attempt-sut (retry expected-failure static defect)
  (let ((sut (%make-attempt-sut :retry retry :expected-failure expected-failure
                                :static static :defect defect)))
    (setf (attempt-sut-observation sut) (attempt-sut-observe sut))
    sut))

(defun attempt-sut-operate (sut outcome)
  (setf (attempt-sut-script sut) (append (attempt-sut-script sut) (list outcome))
        (attempt-sut-observation sut) (attempt-sut-observe sut))
  nil)

(defun check-attempt-conformance (retry expected-failure
                                  &key static bug defect (mode :tree)
                                    (seed 7) (runs 40) (max-steps 8))
  "Compare the real runner, built with DEFECT, against ATTEMPT-SPEC built with BUG."
  (check-sequential-conformance
   (attempt-spec :retry retry :expected-failure expected-failure
                 :static static :bug bug)
   :reset (lambda () (make-attempt-sut retry expected-failure static defect))
   :operations (list (cons 'attempt #'attempt-sut-operate))
   :abstraction #'attempt-sut-observation
   :mode mode :seed seed :runs runs :max-steps max-steps
   :depth (1+ retry)))

(defun call-with-errors-not-retried (thunk)
  "Run THUNK with the runner's retry policy broken in one place: only :fail
events are retryable. The definition is restored on every exit."
  (let ((original (fdefinition 'cl-weave::retryable-event-p)))
    (unwind-protect
         (progn (setf (fdefinition 'cl-weave::retryable-event-p)
                      (lambda (event) (eq (cl-weave::test-event-status event) :fail)))
                (funcall thunk))
      (setf (fdefinition 'cl-weave::retryable-event-p) original))))

(defun conformance-violation-detail (result)
  (spec-violation-detail (spec-result-violation result)))

(defun conformance-called-outcomes (result)
  (mapcar (lambda (step) (first (trace-step-params step)))
          (rest (spec-violation-trace (spec-result-violation result)))))

(defmacro attempt-explore-cases (&rest configs)
  `(progn
     ,@(loop for (retry expected-failure) in configs
             collect `(it-spec ,(format nil "attempt model holds exhaustively (retry ~D, expected-failure ~:[off~;on~])"
                                        retry expected-failure)
                        (explore-spec (attempt-spec :retry ,retry
                                                    :expected-failure ,expected-failure))))))

(defmacro attempt-tree-cases (&rest configs)
  `(progn
     ,@(loop for (retry expected-failure) in configs
             collect `(it-spec ,(format nil "runner conforms to the attempt model over the whole tree (retry ~D, expected-failure ~:[off~;on~])"
                                        retry expected-failure)
                        (check-attempt-conformance ,retry ,expected-failure)))))

(describe "self attempt spec: abstract model"
  (attempt-explore-cases (0 nil) (1 nil) (2 nil) (3 nil)
                         (0 t) (1 t) (2 t) (3 t))

  (it "reaches exactly 3r+5 states with 7(r+1) transitions in r+1 steps"
    ;; Hand count for retry r: r+1 nonfinal states (k attempts used, r-k left);
    ;; :pass and :skip can end at any of the r+1 attempts; :fail and :error
    ;; only after the last. Every nonfinal state has 7 outcomes.
    (dolist (expected-failure '(nil t))
      (dolist (retry '(0 1 2 3))
        (let ((result (explore-spec (attempt-spec :retry retry
                                                  :expected-failure expected-failure))))
          (expect (spec-result-states-found result) :to-be (+ (* 3 retry) 5))
          (expect (spec-result-depth-reached result) :to-be (1+ retry))
          (expect (getf (spec-result-statistics result) :transitions)
                  :to-be (* 7 (1+ retry)))
          (expect (spec-result-truncated result) :to-be nil)
          (expect (member 'eventually-finishes (spec-result-checked-properties result))
                  :to-be-truthy)))))

  (it "spends one budget unit per retry and gives up with the status of the last attempt"
    ;; Read from CALL-WITH-ATTEMPT-OUTCOME/K, EXPECTED-FAILURE-EVENT and the
    ;; restarts: each row is (outcome attempts budget final) after one attempt.
    (let ((spec (attempt-spec :retry 2)))
      (expect (attempt-successor-table spec 1 1)
              :to-equal '((:pass 2 1 :pass) (:continue-restart 2 1 :pass)
                          (:fail 2 0 nil) (:error 2 0 nil) (:timeout 2 0 nil)
                          (:skip 2 1 :skip) (:retry-restart 2 0 nil)))
      (expect (attempt-successor-table spec 2 0)
              :to-equal '((:pass 3 0 :pass) (:continue-restart 3 0 :pass)
                          (:fail 3 0 :fail) (:error 3 0 :error) (:timeout 3 0 :fail)
                          (:skip 3 0 :skip) (:retry-restart 3 0 :error))))
    (let ((spec (attempt-spec :retry 2 :expected-failure t)))
      (expect (attempt-successor-table spec 1 1)
              :to-equal '((:pass 2 0 nil) (:continue-restart 2 0 nil)
                          (:fail 2 1 :pass) (:error 2 0 nil) (:timeout 2 0 nil)
                          (:skip 2 1 :skip) (:retry-restart 2 0 nil)))
      (expect (attempt-successor-table spec 2 0)
              :to-equal '((:pass 3 0 :fail) (:continue-restart 3 0 :fail)
                          (:fail 3 0 :pass) (:error 3 0 :error) (:timeout 3 0 :fail)
                          (:skip 3 0 :skip) (:retry-restart 3 0 :error)))))

  (it "runs no attempt for a skip or todo reason and leaves the budget alone"
    (dolist (static '(:skip :todo))
      (let ((result (explore-spec (attempt-spec :retry 2 :static static))))
        (expect (spec-result-passed-p result) :to-be t)
        (expect (spec-result-states-found result) :to-be 1)
        (expect (getf (spec-result-statistics result) :transitions) :to-be 0))))

  (it "needs weak fairness for termination: without it a stalled run is a lasso"
    (let* ((result (explore-spec (attempt-spec-without-fairness (attempt-spec :retry 1))))
           (violation (spec-result-violation result)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :temporal)
      (expect (spec-violation-property violation) :to-be 'eventually-finishes)
      (expect (every (lambda (step) (null (getf (trace-step-state step) 'final)))
                     (append (lasso-prefix (spec-violation-trace violation))
                             (lasso-cycle (spec-violation-trace violation))))
              :to-be t))))

(describe "self attempt spec: broken variants are rejected"
  (it "rejects a retry budget counted one too many with the shortest trace r+3"
    ;; Retrying at budget 0 drives the budget to -1; the first attempt beyond
    ;; r+1 is the (r+2)-th, reached after r+2 steps.
    (dolist (retry '(0 1 2))
      (let ((result (explore-spec (attempt-spec :retry retry :bug :over-budget))))
        (expect (spec-result-passed-p result) :to-be nil)
        (expect (attempt-violation-summary result)
                :to-equal (list :invariant 'attempts-within-budget (+ retry 3)))
        (expect (getf (trace-step-state (car (last (spec-violation-trace
                                                    (spec-result-violation result)))))
                      'attempts)
                :to-be (+ retry 2)))))

  (it "rejects a run that retries forever at zero budget with the shortest trace r+2"
    ;; The model never finishes a persistently failing test, so its state space
    ;; is infinite; the unpaid retry is caught at the first step that does not
    ;; charge the budget.
    (dolist (retry '(0 1 2))
      (let ((result (explore-spec (attempt-spec :retry retry :bug :unbounded))))
        (expect (spec-result-passed-p result) :to-be nil)
        (expect (spec-result-truncated result) :to-be nil)
        (expect (attempt-violation-summary result)
                :to-equal (list :action-property 'retry-charges-one-budget-unit
                                (+ retry 2))))))

  (it "rejects a timeout treated as final while budget remains, in two states"
    (dolist (retry '(1 2 3))
      (let ((result (explore-spec (attempt-spec :retry retry :bug :timeout-terminal))))
        (expect (attempt-violation-summary result)
                :to-equal (list :invariant 'give-up-only-when-exhausted 2))
        (expect (spec-violation-trace (spec-result-violation result))
                :to-satisfy (lambda (trace)
                              (equal (trace-step-params (second trace)) '(:timeout)))))))

  (it "cannot tell a final timeout from a retried one when no budget exists"
    (let ((result (explore-spec (attempt-spec :retry 0 :bug :timeout-terminal))))
      (expect (spec-result-passed-p result) :to-be t))))

(describe "self attempt spec: scripted outcomes match the runner's events"
  (it "turns a scripted timeout into a test-timeout failure without a timer"
    (let ((event (attempt-run '(:timeout) :retry 0)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-condition event) :to-be-instance-of 'cl-weave:test-timeout)
      (expect (cl-weave:test-timeout-ms (cl-weave::test-event-condition event)) :to-be 1000)))

  (it "reports the other outcomes with the statuses the model assumes"
    (flet ((status (script &rest keys)
             (cl-weave::test-event-status (apply #'attempt-run script keys))))
      (expect (status '(:pass) :retry 0) :to-be :pass)
      (expect (status '(:continue-restart) :retry 0) :to-be :pass)
      (expect (status '(:fail) :retry 0) :to-be :fail)
      (expect (status '(:error) :retry 0) :to-be :error)
      (expect (status '(:skip) :retry 0) :to-be :skip)
      (expect (status '(:retry-restart) :retry 0) :to-be :error)
      (expect (status '(:fail) :retry 0 :expected-failure t) :to-be :pass)
      (expect (cl-weave::test-event-condition
               (attempt-run '(:pass) :retry 0 :expected-failure t))
              :to-be-instance-of 'cl-weave:expected-failure-missed)))

  (it "stops asking for attempts after the budget: one retry means two bodies"
    (multiple-value-bind (event invocations budget)
        (attempt-run '(:fail :fail) :retry 1)
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect invocations :to-be 2)
      (expect budget :to-be 0))
    (multiple-value-bind (event invocations budget)
        (attempt-run '(:fail) :retry 1)
      (expect event :to-be nil)
      (expect invocations :to-be 2)
      (expect budget :to-be 0))))

(describe "self attempt spec: runner conformance"
  (attempt-tree-cases (0 nil) (1 nil) (2 nil)
                      (0 t) (1 t) (2 t))

  (it "visits every hand-counted state of the model through the real runner"
    (dolist (expected-failure '(nil t))
      (dolist (retry '(0 1 2))
        (let ((result (check-attempt-conformance retry expected-failure)))
          (expect (spec-result-states-found result) :to-be (+ (* 3 retry) 5))
          (expect (spec-result-truncated result) :to-be nil)
          (expect (spec-result-depth-reached result) :to-be (1+ retry))))))

  (it-spec "runner conforms to the attempt model on random runs (retry 3, expected-failure off)"
    (check-attempt-conformance 3 nil :mode :random :seed 11 :runs 60 :max-steps 8))

  (it-spec "runner conforms to the attempt model on random runs (retry 3, expected-failure on)"
    (check-attempt-conformance 3 t :mode :random :seed 12 :runs 60 :max-steps 8))

  (it-spec "runner runs no attempt for a skip reason"
    (check-attempt-conformance 2 nil :static :skip))

  (it-spec "runner runs no attempt for a todo reason"
    (check-attempt-conformance 2 nil :static :todo)))

(describe "self attempt spec: conformance rejects wrong models"
  (it "rejects a model that retries once too often at the first failing step"
    (let ((result (check-attempt-conformance 0 nil :bug :over-budget)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :conformance)
      (expect (getf (conformance-violation-detail result) :step) :to-be 1)
      (expect (conformance-called-outcomes result) :to-equal '(:fail))
      (expect (getf (getf (conformance-violation-detail result) :expected) 'final)
              :to-be nil)
      (expect (getf (getf (conformance-violation-detail result) :actual) 'final)
              :to-be :fail)))

  (it "rejects a model that never charges the budget at zero"
    (let ((result (check-attempt-conformance 0 nil :bug :unbounded)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (conformance-called-outcomes result) :to-equal '(:fail))))

  (it "rejects a model that does not retry a timeout, shrunk to the timeout alone"
    (let ((result (check-attempt-conformance 1 nil :bug :timeout-terminal)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (conformance-called-outcomes result) :to-equal '(:timeout))
      (expect (getf (getf (conformance-violation-detail result) :expected) 'final)
              :to-be :fail)
      (expect (getf (getf (conformance-violation-detail result) :actual) 'final)
              :to-be nil))))

(describe "self attempt spec: conformance rejects a defective runner"
  (it "detects a timeout surfaced as a generic error, shrunk to one timeout"
    (dolist (mode '(:tree :random))
      (let ((result (check-attempt-conformance 0 nil :defect :timeout-as-error
                                                     :mode mode :runs 60 :max-steps 4)))
        (expect (spec-result-passed-p result) :to-be nil)
        (expect (conformance-called-outcomes result) :to-equal '(:timeout))
        (expect (getf (getf (conformance-violation-detail result) :expected) 'final)
                :to-be :fail)
        (expect (getf (getf (conformance-violation-detail result) :actual) 'final)
                :to-be :error))))

  (it "detects a retry setting off by one at step zero"
    (let* ((result (check-attempt-conformance 1 nil :defect :retry-plus-one))
           (detail (conformance-violation-detail result)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (getf detail :step) :to-be 0)
      (expect (getf (getf detail :actual) 'budget) :to-be 2)))

  (it "detects a retry policy that skips errors, shrunk to one error"
    (let ((result (call-with-errors-not-retried
                   (lambda () (check-attempt-conformance 1 nil)))))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (conformance-called-outcomes result) :to-equal '(:error))
      (expect (getf (getf (conformance-violation-detail result) :expected) 'final)
              :to-be nil)
      (expect (getf (getf (conformance-violation-detail result) :actual) 'final)
              :to-be :error)))

  (it "restores the retry policy after the defective run"
    (call-with-errors-not-retried (lambda () nil))
    (expect (spec-result-passed-p (check-attempt-conformance 1 nil)) :to-be t)))
