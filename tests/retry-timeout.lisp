

(in-package #:cl-weave/tests)
(describe "retry and timeout"
  (it "keeps the test continuation inside the platform timeout boundary"
    (let* ((continuation-calls 0)
           (suite (cl-weave::make-suite :name "timeout continuation"))
           (test (cl-weave::make-test-case
                  :name "single continuation"
                  :function (lambda () :completed)))
           (cl-weave::*platform-capabilities* '(:timeout))
           (cl-weave::*platform-timeout-caller*
             (lambda (timeout callable continue)
               (declare (ignore timeout))
               (funcall continue (funcall callable)))))
      (expect
       (cl-weave::call-test-case-with-timeout/k
        suite
        test
        1.0
        (lambda ()
          (incf continuation-calls)
          :continued))
       :to-be :continued)
      (expect continuation-calls :to-be 1)))

  (it "retries failing tests until they pass"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "eventual pass"
                  :retry 2
                  :function (lambda ()
                              (incf attempts)
                              (when (< attempts 3)
                                (expect attempts :to-be 3)))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 3)
      (expect (cl-weave::test-event-status event) :to-be :pass)))

  (it "stops retrying after the configured retry budget"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "always fails"
                  :retry 2
                  :function (lambda ()
                              (incf attempts)
                              (expect attempts :to-be 10))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 3)
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-assertion event) :to-be-defined)))

  (it "applies global retry defaults to tests without local retry options"
    (let* ((attempts 0)
           (suite (cl-weave::make-suite :name "global retry"))
           (test (cl-weave::make-test-case
                  :name "eventual pass"
                  :function (lambda ()
                              (incf attempts)
                              (when (< attempts 3)
                                (expect attempts :to-be 3))))))
      (cl-weave::add-child suite test)
      (let ((events (cl-weave::collect-events suite :retry 2)))
        (expect attempts :to-be 3)
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:pass)))))

  (it "lets local retry options override global retry defaults"
    (let* ((attempts 0)
           (suite (cl-weave::make-suite :name "local retry"))
           (test (cl-weave::make-test-case
                  :name "still fails"
                  :retry 0
                  :function (lambda ()
                              (incf attempts)
                              (expect attempts :to-be 10)))))
      (cl-weave::add-child suite test)
      (let ((events (cl-weave::collect-events suite :retry 2)))
        (expect attempts :to-be 1)
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:fail)))))

  (it "reports timed out tests as structured failures"
    (let* ((test (cl-weave::make-test-case
                  :name "slow"
                  :timeout-ms 10
                  :function (lambda () (sleep 0.1))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-condition event)
              :to-be-instance-of 'cl-weave:test-timeout)
      (expect (cl-weave:test-timeout-ms (cl-weave::test-event-condition event))
              :to-be 10)))

  (it "applies global timeout defaults to tests without local timeout options"
    (let* ((suite (cl-weave::make-suite :name "global timeout"))
           (test (cl-weave::make-test-case
                  :name "slow"
                  :function (lambda () (sleep 0.1)))))
      (cl-weave::add-child suite test)
      (let* ((events (cl-weave::collect-events suite :timeout-ms 10))
             (event (first events)))
        (expect (cl-weave::test-event-status event) :to-be :fail)
        (expect (cl-weave::test-event-condition event)
                :to-be-instance-of 'cl-weave:test-timeout)
        (expect (cl-weave:test-timeout-ms
                 (cl-weave::test-event-condition event))
                :to-be 10))))

  (it "lists and bounds effective retry and timeout defaults"
    (let* ((suite (cl-weave::make-suite :name "plan defaults"))
           (defaulted (cl-weave::make-test-case
                       :name "defaulted"
                       :function (lambda () t)))
           (local (cl-weave::make-test-case
                   :name "local"
                   :retry 0
                   :timeout-ms 25
                   :function (lambda () t))))
      (cl-weave::add-child suite defaulted)
      (cl-weave::add-child suite local)
      (let ((plan (cl-weave:collect-test-plan
                   suite
                   :retry 2
                   :timeout-ms 100)))
        (expect (mapcar #'cl-weave:test-plan-entry-retry plan)
                :to-equal '(2 0))
        (expect (mapcar #'cl-weave:test-plan-entry-timeout-ms plan)
                :to-equal '(100 25))))
    (expect (cl-weave::collect-events
             (cl-weave::make-suite :name "empty")
             :retry cl-weave::+maximum-retry-count+
             :timeout-ms cl-weave::+maximum-timeout-ms+)
            :to-be-null)
    (dolist (option
             (list
              (list :retry
                    (1+ cl-weave::+maximum-retry-count+)
                    "Retry must be")
              (list :timeout-ms
                    (1+ cl-weave::+maximum-timeout-ms+)
                    "Timeout must be")))
      (let ((executed nil)
            (root (cl-weave::make-suite :name "root")))
        (add-tripwire-test-case root (lambda () (setf executed t)))
        (expect (lambda ()
                  (apply #'cl-weave::collect-events
                         root
                         (list (first option) (second option))))
                :to-throw
                (third option))
        (expect executed :to-be nil))))

  (it "validates public run limits before coverage side effects"
    (dolist (option
             (list
              (list :retry
                    (1+ cl-weave::+maximum-retry-count+)
                    "Retry must be")
              (list :timeout-ms
                    (1+ cl-weave::+maximum-timeout-ms+)
                    "Timeout must be")
              (list :max-workers
                    (1+ cl-weave::+maximum-worker-count+)
                    "Max workers must be")
              (list :bail
                    (1+ cl-weave::+maximum-bail-limit+)
                    "Bail must be")
              (list :shard
                    (list 1 (1+ cl-weave::+maximum-shard-count+))
                    "Shard must be NIL")))
      (destructuring-bind (key value error-message) option
        (let ((coverage-calls 0)
              (executed 0)
              (root (cl-weave::make-suite :name "root")))
          (add-tripwire-test-case root (lambda () (incf executed)))
          (with-mocked-functions
              (((symbol-function 'cl-weave::require-coverage-support)
                (lambda ()
                  (incf coverage-calls)))
               ((symbol-function 'cl-weave:reset-coverage)
                (lambda ()
                  (incf coverage-calls)))
               ((symbol-function 'cl-weave:save-coverage)
                (lambda (path)
                  (declare (ignore path))
                  (incf coverage-calls))))
            (let ((cl-weave::*root-suite* root))
              (expect
               (lambda ()
                 (apply #'cl-weave:run-all
                        :reporter :sexp
                        :stream (make-broadcast-stream)
                        :coverage t
                        :coverage-output "unused.coverage"
                        (list key value)))
               :to-throw
               error-message)))
          (expect coverage-calls :to-be 0)
          (expect executed :to-be 0)))))

  (it "fails a test when expect-assertions count is not met"
    (let* ((test (cl-weave::make-test-case
                  :name "missing assertion"
                  :function (lambda ()
                              (expect-assertions 2)
                              (expect :only :to-be :only))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test))
           (assertion (cl-weave::test-event-assertion event)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::assertion-detail-matcher assertion) :to-be :assertions)
      (expect (cl-weave::assertion-detail-actual assertion) :to-be 1)
      (expect (cl-weave::assertion-detail-expected assertion) :to-be 2)))

  (it "fails a test when expect-has-assertions observes no assertions"
    (let* ((test (cl-weave::make-test-case
                  :name "missing assertions"
                  :function (lambda ()
                              (expect-has-assertions))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test))
           (assertion (cl-weave::test-event-assertion event)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::assertion-detail-matcher assertion) :to-be :has-assertions)
      (expect (cl-weave::assertion-detail-actual assertion) :to-be 0)
      (expect (cl-weave::assertion-detail-expected assertion) :to-equal '(:minimum 1))))

  (it "resets assertion counts for each retry attempt"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "eventual assertion count"
                  :retry 1
                  :function (lambda ()
                              (incf attempts)
                              (expect-assertions 1)
                              (if (= attempts 1)
                                  (progn
                                    (expect :first :to-be :first)
                                    (expect :extra :to-be :extra))
                                  (expect :second :to-be :second)))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 2)
      (expect (cl-weave::test-event-status event) :to-be :pass)))

  (it "reports a timeout that fires inside a hook as a structured timeout"
    ;; Regression: a before/after-each hook slower than the remaining budget
    ;; must surface as a test-timeout, not a spurious hook-failure carrying a
    ;; leaked internal timeout condition.
    (dolist (phase '(:before-each :after-each))
      (let* ((suite (cl-weave::make-suite
                     :name "slow hook timeout"
                     :before-each (when (eq phase :before-each)
                                    (list (lambda () (sleep 0.1))))
                     :after-each (when (eq phase :after-each)
                                   (list (lambda () (sleep 0.1))))))
             (test (cl-weave::make-test-case
                    :name "fast body"
                    :timeout-ms 10
                    :function (lambda () t))))
        (cl-weave::add-child suite test)
        (let ((event (cl-weave::run-test-case suite test)))
          (expect (cl-weave::test-event-status event) :to-be :fail)
          (expect (cl-weave::test-event-condition event)
                  :to-be-instance-of 'cl-weave:test-timeout)))))

  (it "runs after-each cleanup when an attempt times out"
    (let* ((events nil)
           (suite (cl-weave::make-suite
                   :name "timeout cleanup"
                   :after-each (list (lambda () (push :after-each events)))))
           (test (cl-weave::make-test-case
                  :name "slow"
                  :timeout-ms 10
                  :function (lambda () (sleep 0.1)))))
      (cl-weave::add-child suite test)
      (let ((event (cl-weave::run-test-case suite test)))
        (expect (cl-weave::test-event-status event) :to-be :fail)
        (expect events :to-equal '(:after-each)))))

  (it "exposes a restart that can continue a failed attempt as passed"
    (let* ((test (cl-weave::make-test-case
                  :name "continue from failure"
                  :function (lambda ()
                              (expect :actual :to-be :expected))))
           (event (handler-bind ((assertion-failure
                                   (lambda (condition)
                                     (declare (ignore condition))
                                     (invoke-restart 'continue-test))))
                    (cl-weave::run-test-case/interactively (cl-weave::root-suite) test))))
      (expect (cl-weave::test-event-status event) :to-be :pass))
    (let* ((cleanup-count 0)
           (suite (cl-weave::make-suite
                   :name "direct continue cleanup"
                   :after-each (list (lambda () (incf cleanup-count)))))
           (test (cl-weave::make-test-case
                  :name "direct continue"
                  :function (lambda () (invoke-restart 'continue-test))))
           (event (cl-weave::run-test-case suite test)))
      (expect (cl-weave::test-event-status event) :to-be :pass)
      (expect cleanup-count :to-be 1)))

  (it "exposes a restart that records a failed attempt as skipped"
    (let* ((test (cl-weave::make-test-case
                  :name "skip from failure"
                  :function (lambda ()
                              (expect :actual :to-be :expected))))
           (event (handler-bind ((assertion-failure
                                   (lambda (condition)
                                     (declare (ignore condition))
                                     (invoke-restart 'skip-test "patched interactively"))))
                    (cl-weave::run-test-case/interactively (cl-weave::root-suite) test))))
      (expect (cl-weave::test-event-status event) :to-be :skip)
      (expect (cl-weave::test-event-reason event) :to-equal "patched interactively"))
    (let* ((cleanup-count 0)
           (suite (cl-weave::make-suite
                   :name "direct skip cleanup"
                   :after-each (list (lambda () (incf cleanup-count)))))
           (test (cl-weave::make-test-case
                  :name "direct skip"
                  :function (lambda () (invoke-restart 'skip-test "directly skipped"))))
           (event (cl-weave::run-test-case suite test)))
      (expect (cl-weave::test-event-status event) :to-be :skip)
      (expect (cl-weave::test-event-reason event) :to-equal "directly skipped")
      (expect cleanup-count :to-be 1)))

  (it "does not invoke an identity-matched trusted empty function"
    (let* ((calls 0)
           (function (lambda () (incf calls)))
           (test (cl-weave::make-test-case
                  :name "trusted empty"
                  :function function
                  :trusted-empty-function function))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect calls :to-be 0)
      (expect (cl-weave::test-event-status event) :to-be :pass)))

  (it "falls back when the trusted function is replaced"
    (let* ((calls 0)
           (marker (lambda () (error "stale trusted marker invoked")))
           (test (cl-weave::make-test-case
                  :name "replaced trusted empty"
                  :function marker
                  :trusted-empty-function marker)))
      (setf (cl-weave::test-case-function test)
            (lambda () (incf calls)))
      (let ((event (cl-weave::run-test-case (cl-weave::root-suite) test)))
        (expect calls :to-be 1)
        (expect (cl-weave::test-event-status event) :to-be :pass))))

  (it "falls back for directly constructed and registered tests"
    (let ((cl-weave::*root-suite* nil)
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test (function equal)))
          (cl-weave::*registration-owners* (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (let* ((constructed-calls 0)
             (registered-calls 0)
             (constructed
               (cl-weave::make-test-case
                :name "direct constructor"
                :function (lambda () (incf constructed-calls))))
             (registered
               (cl-weave::register-test
                "direct registration"
                (lambda () (incf registered-calls)))))
        (cl-weave::run-test-case (cl-weave::root-suite) constructed)
        (cl-weave::run-test-case (cl-weave::root-suite) registered)
        (expect constructed-calls :to-be 1)
        (expect registered-calls :to-be 1))))

  (it "preserves expected-failure event semantics for trusted empty tests"
    (let* ((function (lambda () (error "trusted empty function invoked")))
           (test (cl-weave::make-test-case
                  :name "expected trusted empty"
                  :function function
                  :trusted-empty-function function
                  :expected-failure-reason "known failure"))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect
       (typep (cl-weave::test-event-condition event)
              (quote cl-weave::expected-failure-missed))
       :to-be t)))

  (it "excludes hooks retries and timeouts from the trusted empty fast path"
    (let* ((body-calls 0)
           (hook-calls 0)
           (function (lambda () (incf body-calls)))
           (suite (cl-weave::make-suite
                   :name "trusted empty hook exclusion"
                   :before-each (list (lambda () (incf hook-calls)))))
           (test (cl-weave::make-test-case
                  :name "trusted empty with hook"
                  :function function
                  :trusted-empty-function function)))
      (cl-weave::add-child suite test)
      (cl-weave::run-test-case suite test)
      (expect body-calls :to-be 1)
      (expect hook-calls :to-be 1))
    (let* ((calls 0)
           (function (lambda () (incf calls)))
           (test (cl-weave::make-test-case
                  :name "trusted empty with retry"
                  :function function
                  :trusted-empty-function function
                  :retry 1)))
      (cl-weave::run-test-case (cl-weave::root-suite) test)
      (expect calls :to-be 1))
    (let* ((calls 0)
           (function (lambda () (incf calls)))
           (test (cl-weave::make-test-case
                  :name "trusted empty with timeout"
                  :function function
                  :trusted-empty-function function
                  :timeout-ms 1000)))
      (cl-weave::run-test-case (cl-weave::root-suite) test)
      (expect calls :to-be 1)))
  (it "allows warnings and notification conditions to continue"
    (dolist (test-function
             (list (lambda ()
                     (warn "nonfatal warning"))
                   (lambda ()
                     (signal (make-condition 'simple-condition
                                             :format-control "notification")))))
      (let* ((test (cl-weave::make-test-case
                    :name "non-error condition"
                    :function test-function))
             (event (handler-bind ((warning #'muffle-warning))
                      (cl-weave::run-test-case (cl-weave::root-suite) test))))
        (expect (cl-weave::test-event-status event) :to-be :pass))))
  (it "records non-error serious conditions as errors in the generic path"
  (let* ((condition (make-condition (quote serious-condition)))
         (suite (cl-weave::make-suite
                 :name "serious condition generic path"
                 :before-each (list (lambda () nil))))
         (test (cl-weave::make-test-case
                :name "serious condition"
                :function (lambda () (signal condition)))))
    (cl-weave::add-child suite test)
    (let ((event (cl-weave::run-test-case suite test)))
      (expect (cl-weave::test-event-status event) :to-be :error)
      (expect (cl-weave::test-event-condition event) :to-be condition))))

  (it "charges interactive retries to the configured retry budget"
    (dolist (case '((1 2 :pass)
                    (0 1 :error)))
      (destructuring-bind (retry expected-attempts expected-status) case
        (let* ((attempts 0)
               (test (cl-weave::make-test-case
                      :name "retry from failure"
                      :retry retry
                      :function (lambda ()
                                  (incf attempts)
                                  (expect attempts :to-be 2))))
               (event
                 (handler-bind ((assertion-failure
                                  (lambda (condition)
                                    (declare (ignore condition))
                                    (invoke-restart 'retry-test))))
                   (cl-weave::run-test-case/interactively
                    (cl-weave::root-suite)
                    test))))
          (expect attempts :to-be expected-attempts)
          (expect (cl-weave::test-event-status event) :to-be expected-status)))))

  (it "uses the same continuation path for automatic and interactive retries"
    (dolist (interactive-p '(nil t))
      (let* ((attempts 0)
             (test (cl-weave::make-test-case
                    :name "continuation retry"
                    :retry 1
                    :function (lambda ()
                                (incf attempts)
                                (expect attempts :to-be 2))))
             (run (lambda ()
                    (if interactive-p
                        (handler-bind
                            ((assertion-failure
                               (lambda (condition)
                                 (declare (ignore condition))
                                 (invoke-restart 'retry-test))))
                          (cl-weave::run-test-case/interactively
                           (cl-weave::root-suite)
                           test))
                        (cl-weave::run-test-case
                         (cl-weave::root-suite)
                         test))))
             (event (funcall run)))
        (expect attempts :to-be 2)
        (expect (cl-weave::test-event-status event) :to-be :pass)))
    (let* ((attempts 0)
           (cleanup-count 0)
           (suite (cl-weave::make-suite
                   :name "direct retry cleanup"
                   :after-each (list (lambda () (incf cleanup-count)))))
           (test (cl-weave::make-test-case
                  :name "direct retry"
                  :retry 1
                  :function (lambda ()
                              (incf attempts)
                              (when (= attempts 1)
                                (invoke-restart 'retry-test)))))
           (event (cl-weave::run-test-case suite test)))
      (expect (cl-weave::test-event-status event) :to-be :pass)
      (expect attempts :to-be 2)
      (expect cleanup-count :to-be 2)))
  (it "consumes one retry budget unit per failed attempt"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "retry budget failure"
                  :retry 2
                  :function (lambda ()
                              (incf attempts)
                              (expect t :to-be nil))))
           (event (cl-weave::run-test-case
                   (cl-weave::root-suite)
                   test)))
      (expect attempts :to-be 3)
      (expect (cl-weave::test-event-status event) :to-be :fail)))
  (it "consumes one retry budget unit per explicit retry restart"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "retry budget restart"
                  :retry 2
                  :function (lambda ()
                              (incf attempts)
                              (invoke-restart 'retry-test))))
           (event (cl-weave::run-test-case
                   (cl-weave::root-suite)
                   test)))
      (expect attempts :to-be 3)
      (expect (cl-weave::test-event-status event) :to-be :error))))
(describe "strict empty batch collection"
  (it "collects a root batch without invoking bodies and preserves event shape"
    (let* ((calls 0)
           (first-location #P"/tmp/strict-empty-first.lisp")
           (second-location #P"/tmp/strict-empty-second.lisp")
           (first-function (lambda () (incf calls)))
           (second-function (lambda () (incf calls)))
           (suite (cl-weave::make-suite :name "root")))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "first"
        :function first-function
        :trusted-empty-function first-function
        :location first-location))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "second"
        :function second-function
        :trusted-empty-function second-function
        :location second-location))
      (with-mocked-functions
          (((symbol-function 'cl-weave::call-with-collection-context)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "generic collection context invoked"))))
        (let ((events (cl-weave::collect-events suite)))
          (expect calls :to-be 0)
          (expect (length events) :to-be 2)
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass :pass))
          (expect (mapcar #'cl-weave::test-event-path events)
                  :to-equal '(("first") ("second")))
          (expect (mapcar #'cl-weave::test-event-condition events)
                  :to-equal '(nil nil))
          (expect (mapcar #'cl-weave::test-event-secondary-conditions events)
                  :to-equal '(nil nil))
          (expect (mapcar #'cl-weave::test-event-assertion events)
                  :to-equal '(nil nil))
          (expect (mapcar #'cl-weave::test-event-reason events)
                  :to-equal '(nil nil))
          (expect (mapcar #'cl-weave::test-event-location events)
                  :to-equal (list first-location second-location))
          (expect (every #'cl-weave::test-event-p events) :to-be t)
          (expect
           (every
            (lambda (event)
              (let ((elapsed
                      (cl-weave::test-event-elapsed-internal-time event)))
                (and (integerp elapsed)
                     (not (minusp elapsed)))))
            events)
           :to-be t)))))

  (it "prefixes direct nested batch paths exactly once"
    (let* ((calls 0)
           (function (lambda () (incf calls)))
           (root (cl-weave::make-suite :name "root"))
           (parent (cl-weave::make-suite :name "parent" :parent root))
           (suite (cl-weave::make-suite :name "target" :parent parent)))
      (cl-weave::add-child root parent)
      (cl-weave::add-child parent suite)
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "case"
        :function function
        :trusted-empty-function function))
      (with-mocked-functions
          (((symbol-function 'cl-weave::call-with-collection-context)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "generic collection context invoked"))))
        (let ((events (cl-weave::collect-events suite)))
          (expect calls :to-be 0)
          (expect (mapcar #'cl-weave::test-event-path events)
                  :to-equal '(("parent" "target" "case")))
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass))))))

  (it "falls back for a replaced trusted marker"
    (let* ((calls 0)
           (marker (lambda () (error "stale marker invoked")))
           (suite (cl-weave::make-suite :name "root"))
           (test (cl-weave::make-test-case
                  :name "replaced"
                  :function marker
                  :trusted-empty-function marker)))
      (setf (cl-weave::test-case-function test)
            (lambda () (incf calls)))
      (cl-weave::add-child suite test)
      (let ((events (cl-weave::collect-events suite)))
        (expect calls :to-be 1)
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:pass))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("replaced"))))))

  (it "preflights the whole batch before creating direct events"
    (let* ((calls 0)
           (function (lambda () (incf calls)))
           (suite (cl-weave::make-suite :name "root")))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "eligible"
        :function function
        :trusted-empty-function function))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "later skipped"
        :function (lambda () (error "skipped body invoked"))
        :skip-reason "not now"))
      (with-mocked-functions
          (((symbol-function 'cl-weave::make-pass-event-with-path)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "batch event created before preflight completed"))))
        (let ((events (cl-weave::collect-events suite)))
          (expect calls :to-be 0)
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass :skip))
          (expect (mapcar #'cl-weave::test-event-reason events)
                  :to-equal '(nil "not now"))))))

  (it "rejects hooks expected failures filters and nested suites"
    (labels ((collect-without-batch (suite &rest options)
               (with-mocked-functions
                   (((symbol-function 'cl-weave::make-pass-event-with-path)
                     (lambda (&rest arguments)
                       (declare (ignore arguments))
                       (error "ineligible suite entered batch path"))))
                 (apply #'cl-weave::collect-events suite options))))
      (let* ((body-calls 0)
             (hook-calls 0)
             (function (lambda () (incf body-calls)))
             (suite (cl-weave::make-suite
                     :name "root"
                     :before-each
                     (list (lambda () (incf hook-calls))))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "hooked"
          :function function
          :trusted-empty-function function))
        (let ((events (collect-without-batch suite)))
          (expect body-calls :to-be 1)
          (expect hook-calls :to-be 1)
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass))))
      (let* ((calls 0)
             (function (lambda () (incf calls)))
             (suite (cl-weave::make-suite :name "root")))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "expected failure"
          :function function
          :trusted-empty-function function
          :expected-failure-reason "known"))
        (let ((events (collect-without-batch suite)))
          (expect calls :to-be 0)
          (expect (mapcar (function cl-weave::test-event-status) events)
                  :to-equal (quote (:fail)))
          (expect (cl-weave::test-event-condition (first events))
                  :to-be-instance-of
                  (quote cl-weave:expected-failure-missed))))
      (let* ((calls 0)
             (function (lambda () (incf calls)))
             (suite (cl-weave::make-suite :name "root")))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "filter match"
          :function function
          :trusted-empty-function function))
        (let ((events (collect-without-batch suite :name-filter "filter")))
          (expect calls :to-be 0)
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass))))
      (let* ((calls 0)
             (function (lambda () (incf calls)))
             (root (cl-weave::make-suite :name "root"))
             (child (cl-weave::make-suite :name "child" :parent root)))
        (cl-weave::add-child root child)
        (cl-weave::add-child
         child
         (cl-weave::make-test-case
          :name "nested"
          :function function
          :trusted-empty-function function))
        (let ((events (collect-without-batch root)))
          (expect calls :to-be 0)
          (expect (mapcar #'cl-weave::test-event-path events)
                  :to-equal '(("child" "nested")))
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass))))))

  (it "distinguishes an empty collected batch from an ineligible suite"
    (let* ((suite (cl-weave::make-suite :name "root"))
           (options (cl-weave::normalize-collection-options)))
      (multiple-value-bind (events collected-p)
          (cl-weave::try-collect-strict-empty-batch-events suite options)
        (expect events :to-be nil)
        (expect collected-p :to-be t))
      (with-mocked-functions
          (((symbol-function 'cl-weave::call-with-collection-context)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "generic collection context invoked"))))
        (expect (cl-weave::collect-events suite) :to-be nil)))))
