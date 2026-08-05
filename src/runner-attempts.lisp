(in-package #:cl-weave)

(defvar *collection-test-paths* nil)

(defun test-path (suite test)
  (append (mapcar #'suite-name (rest (suite-lineage suite)))
          (list (test-case-name test))))

(defun filter-path-string (path)
  (format nil "~{~A~^ > ~}" path))

(defun make-event (status suite test start
                   &key condition secondary-conditions assertion reason)
  (make-instance
   (load-time-value (find-class 'test-event))
   :status status
   :path (or (and *collection-test-paths*
                  (gethash test *collection-test-paths*))
             (test-path suite test))
   :condition condition
   :secondary-conditions (or secondary-conditions
                             *attempt-secondary-conditions*)
   :assertion assertion
   :reason reason
   :location (test-case-location test)
   :elapsed-internal-time (- (get-internal-real-time) start)
   :journal (current-journal-frames)
   :replay-seed *attempt-replay-seed*))

(defun make-pass-event-with-path (test path start)
  (make-instance
   (load-time-value (find-class 'test-event))
   :status :pass
   :path path
   :condition nil
   :secondary-conditions *attempt-secondary-conditions*
   :assertion nil
   :reason nil
   :location (test-case-location test)
   :elapsed-internal-time (- (get-internal-real-time) start)
   :journal (current-journal-frames)
   :replay-seed *attempt-replay-seed*))

(defmacro define-bounded-integer-normalizer
    (name (value-var) &key null-value min-bound max-constant label unit)
  "Define a function NAME (VALUE-VAR) that normalizes an optional bounded
integer: NIL maps to NULL-VALUE, an integer within [MIN-BOUND, MAX-CONSTANT]
passes through unchanged, and anything else signals an error describing the
bound as LABEL (with an optional trailing UNIT word, e.g. \"milliseconds\")."
  `(defun ,name (,value-var)
     (cond
       ((null ,value-var) ,null-value)
       ((and (integerp ,value-var)
             (<= ,min-bound ,value-var ,max-constant))
        ,value-var)
       (t
        (error "~A must be NIL or an integer between ~D and ~D~@[ ~A~]: ~S"
               ,label ,min-bound ,max-constant ,unit ,value-var)))))

(define-bounded-integer-normalizer normalize-retry-count (retry)
  :null-value 0
  :min-bound 0
  :max-constant +maximum-retry-count+
  :label "Retry")

(define-bounded-integer-normalizer normalize-timeout-ms (timeout-ms)
  :null-value nil
  :min-bound 1
  :max-constant +maximum-timeout-ms+
  :label "Timeout"
  :unit "milliseconds")

(define-bounded-integer-normalizer normalize-max-workers (max-workers)
  :null-value nil
  :min-bound 1
  :max-constant +maximum-worker-count+
  :label "Max workers")

(defun retry-count (test)
  (let ((retry (test-case-retry test)))
    (normalize-retry-count
      (if (null retry) *default-retry*
        retry))))

(defun effective-timeout-ms (test)
  (normalize-timeout-ms
   (or (test-case-timeout-ms test)
       *default-timeout-ms*)))

(defun call-test-case-with-timeout/k (suite test timeout continue)
  (if timeout
      (call-with-platform-timeout/k
       timeout
       (lambda () (call-test-case/k suite test continue))
       (function identity))
      (call-test-case/k suite test continue)))

(defun expected-failure-case-p (test)
  (test-case-expected-failure-reason test))

(defun expected-failure-event (suite test start event)
  (let ((reason (expected-failure-case-p test)))
    (cond
      ((null reason)
       event)
      ((eq (test-event-status event) :pass)
       (make-event :fail
                   suite
                   test
                   start
                   :condition (make-condition 'expected-failure-missed
                                              :reason reason)))
      ((and (eq (test-event-status event) :fail)
            (typep (test-event-condition event) 'assertion-failure))
       (let ((cleanup-conditions
               (test-event-secondary-conditions event)))
         (if cleanup-conditions
             (make-event
              :error
              suite
              test
              start
              :condition (make-condition 'hook-failure
                                         :phase :after-each
                                         :causes cleanup-conditions)
              :assertion (test-event-assertion event)
              :secondary-conditions cleanup-conditions)
             (make-event :pass suite test start))))
      (t
       event))))

(defun normalize-restart-skip-reason (reason)
  (cond
    ((null reason) "skipped by skip-test restart")
    ((stringp reason) reason)
    (t (princ-to-string reason))))

(defun retry-budget-exhausted-error ()
  (make-condition 'simple-error
                  :format-control "The configured retry budget is exhausted."))

(defun test-case-hookless-p (suite)
  (loop for current = suite then (suite-parent current)
        while current
        never (or
      (suite-before-each current)
      (suite-after-each current)
      (suite-around-each current))))

(defun call-test-attempt/restarts (suite test start timeout retry)
  (restart-case (call-test-case-with-timeout/k
      suite
      test
      timeout
      (lambda ()
        (make-event :pass suite test start)))
    (continue-test ()
      :report
      "Continue the current failed test attempt and record it as passed."
      (make-event :pass suite test start))
    (skip-test (&optional reason)
      :report
      "Skip the current failed test attempt and record it as skipped."
      (make-event
        :skip
        suite
        test
        start
        :reason
        (normalize-restart-skip-reason reason)))
    (retry-test ()
      :report
      "Retry the current test attempt using the configured retry budget."
      (if (plusp *retry-budget-remaining*) (funcall retry)
        (make-event :error suite test start :condition (retry-budget-exhausted-error))))))

(defun offer-condition-to-outer-handlers (condition)
  (let ((*runner-default-condition-handler-disabled* t))
    (signal condition)))

(defun call-with-propagated-condition/k (condition continue)
  (when (and *runner-propagate-conditions*
             (not *runner-default-condition-handler-disabled*))
    (offer-condition-to-outer-handlers condition))
  (funcall continue))

(defmacro with-runner-condition-propagation ((enabled) &body body)
  `(let ((*runner-propagate-conditions* ,enabled))
     ,@body))

(defun attempt-condition-handler (finish-attempt suite test start)
  "Build an error handler that finishes the current test attempt.
The handler declines while the condition is being offered to outer
handlers, so runner propagation cannot abort an enclosing runner."
  (lambda (condition)
    (unless *runner-default-condition-handler-disabled*
      (funcall finish-attempt
               (call-with-propagated-condition/k
                condition
                (lambda ()
                  (if (typep condition (quote assertion-failure))
                      (make-event :fail suite test start
                                  :condition condition
                                  :assertion (failure-detail condition))
                      (make-event :error suite test start
                                  :condition condition))))))))

(defun platform-timeout-condition-handler (finish-attempt suite test start timeout-ms)
  "Build a handler that finishes the current attempt as a structured
TEST-TIMEOUT failure. Mirrors ATTEMPT-CONDITION-HANDLER's decline-while-
propagating shape for the PLATFORM-TIMEOUT condition specifically, since its
failure event embeds TIMEOUT-MS rather than the signaled condition itself."
  (lambda (condition)
    (unless *runner-default-condition-handler-disabled*
      (funcall finish-attempt
               (call-with-propagated-condition/k
                condition
                (lambda ()
                  (make-event :fail suite test start
                              :condition
                              (make-condition (quote test-timeout)
                                              :timeout-ms timeout-ms))))))))

(defun run-test-attempt/k (suite test start timeout-ms timeout retry continue)
  (let* ((*attempt-replay-seed* (replay-seed-for-attempt (test-path suite test)))
         (*attempt-secondary-conditions* nil)
         (*execution-journal* (when *journal-enabled* (make-execution-journal))))
    (call-with-test-randomness
     *attempt-replay-seed*
     (lambda ()
       (let ((event
               (with-escape-continuation (finish-attempt)
                 (handler-bind
                     ((platform-timeout
                        (platform-timeout-condition-handler
                         finish-attempt suite test start timeout-ms))
                      (serious-condition
                        (attempt-condition-handler
                         finish-attempt suite test start)))
                   (call-test-attempt/restarts suite test start timeout retry)))))
         (setf event (expected-failure-event suite test start event))
         ;; The pass event is built inside the body continuation, before
         ;; after-each cleanup runs; re-attach the now-complete timeline so
         ;; after-each hook frames are included on every outcome.
         (when (journaling-active-p)
           (setf (test-event-journal event) (current-journal-frames)))
         (funcall continue event))))))

(defun retryable-event-p (event)
  (member (test-event-status event) '(:fail :error)))

(defun call-with-attempt-outcome/k (event retries-remaining on-retry on-give-up)
  "Dispatch on one finished attempt EVENT the way CALL-WITH-WATCH-RUN-ATTEMPT/K
dispatches on a watch cycle's outcome: a retryable EVENT with RETRIES-REMAINING
budget left calls ON-RETRY to spend one more attempt, and any other outcome --
a pass, or a retryable failure with no budget left -- calls ON-GIVE-UP with
EVENT as the final result."
  (if (and (plusp retries-remaining) (retryable-event-p event))
      (funcall on-retry)
      (funcall on-give-up event)))

(defun run-test-attempts
    (suite test start remaining-retries timeout-ms)
  (let ((timeout (and timeout-ms
                      (/ timeout-ms 1000.0))))
    (if (zerop remaining-retries)
        (let ((*retry-budget-remaining* 0))
          (run-test-attempt/k
           suite test start timeout-ms timeout
           (function identity)
           (function identity)))
        (labels ((attempt (retries)
                   (block retry-attempt
                     (let ((*retry-budget-remaining* retries))
                       (run-test-attempt/k
                        suite
                        test
                        start
                        timeout-ms
                        timeout
                        (lambda ()
                          (return-from retry-attempt
                            (attempt (1- retries))))
                        (lambda (event)
                          (call-with-attempt-outcome/k
                           event retries
                           (lambda () (attempt (1- retries)))
                           (function identity))))))))
          (attempt remaining-retries)))))

(defun run-trusted-empty-test-case (suite test start)
  (expected-failure-event
   suite
   test
   start
   (make-event :pass suite test start)))

(defun trusted-empty-fast-path-p (suite test marker remaining-retries timeout-ms)
  "True when TEST's function is still MARKER, its own known-empty
trusted-empty-function, and nothing -- a retry budget, a timeout, or a suite
hook -- could tell running it apart from skipping it entirely."
  (and marker
       (eq marker (test-case-function test))
       (zerop remaining-retries)
       (null timeout-ms)
       (test-case-hookless-p suite)))

(defun run-test-case/internal (suite test)
  (let ((start (get-internal-real-time)))
    (cond
      ((test-case-todo-reason test)
       (make-event :todo suite test start :reason (test-case-todo-reason test)))
      ((test-case-skip-reason test)
       (make-event :skip suite test start :reason (test-case-skip-reason test)))
      (t
       (let ((remaining-retries (retry-count test))
             (timeout-ms (effective-timeout-ms test))
             (marker (test-case-trusted-empty-function test)))
         (if (trusted-empty-fast-path-p suite test marker remaining-retries timeout-ms)
             (run-trusted-empty-test-case suite test start)
             (run-test-attempts suite test start remaining-retries timeout-ms)))))))

(defun run-test-case (suite test)
  (with-runner-condition-propagation (nil)
    (run-test-case/internal suite test)))

(defun run-test-case/interactively (suite test)
  (with-runner-condition-propagation (t)
    (run-test-case/internal suite test)))
