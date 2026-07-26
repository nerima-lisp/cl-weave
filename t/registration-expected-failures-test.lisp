(in-package #:cl-weave/test)

(describe "expected failures"
  (it-fails "passes when the body fails"
    (expect 1 :to-be 2))

  (it "turns unexpected success into a structured failure"
    (let* ((test (cl-weave::make-test-case
                  :name "known bug"
                  :expected-failure-reason "known bug"
                  :function (lambda () :ok)))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-condition event)
              :to-be-instance-of 'cl-weave:expected-failure-missed)
      (expect (cl-weave:expected-failure-missed-reason
               (cl-weave::test-event-condition event))
              :to-equal "known bug")))

  (it "retries unexpected success until it becomes an expected failure"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "eventually fails"
                  :retry 2
                  :expected-failure-reason "known bug"
                  :function (lambda ()
                              (incf attempts)
                              (when (= attempts 3)
                                (expect :actual :to-be :expected)))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 3)
      (expect (cl-weave::test-event-status event) :to-be :pass)))

  (it "does not turn implementation errors into expected passes"
    (let* ((condition (make-condition 'simple-error
                                      :format-control "framework bug"))
           (test (cl-weave::make-test-case
                  :name "broken test"
                  :expected-failure-reason "known assertion bug"
                  :function (lambda () (error condition))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :error)
      (expect (cl-weave::test-event-condition event) :to-be condition)))

  (it "does not hide cleanup failures behind an expected assertion failure"
    (let* ((cleanup-condition
             (make-condition 'simple-error :format-control "cleanup failed"))
           (suite
             (cl-weave::make-suite
              :name "expected failure cleanup"
              :after-each (list (lambda () (error cleanup-condition)))))
           (test
             (cl-weave::make-test-case
              :name "known assertion bug with broken cleanup"
              :expected-failure-reason "known assertion bug"
              :function (lambda () (expect :actual :to-be :expected))))
           (event (cl-weave::run-test-case suite test))
           (condition (cl-weave::test-event-condition event))
           (assertion (cl-weave::test-event-assertion event)))
      (expect (cl-weave::test-event-status event) :to-be :error)
      (expect condition :to-be-instance-of 'cl-weave:hook-failure)
      (expect (cl-weave:hook-failure-phase condition) :to-be :after-each)
      (expect (cl-weave:hook-failure-causes condition)
              :to-equal (list cleanup-condition))
      (expect (cl-weave::test-event-secondary-conditions event)
              :to-equal (list cleanup-condition))
      (expect assertion :not :to-be nil)
      (expect (cl-weave::assertion-detail-actual assertion) :to-be :actual)
      (expect (cl-weave::assertion-detail-expected assertion) :to-equal '(:expected))))

  (it "retries implementation errors without converting the final error"
    (let ((attempts 0)
          (conditions '()))
      (flet ((fail-with-next-condition ()
               (incf attempts)
               (let ((condition (make-condition 'simple-error
                                                :format-control "framework bug ~D"
                                                :format-arguments (list attempts))))
                 (push condition conditions)
                 (error condition))))
        (let* ((test (cl-weave::make-test-case
                      :name "persistently broken test"
                      :retry 2
                      :expected-failure-reason "known assertion bug"
                      :function #'fail-with-next-condition))
               (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
          (expect attempts :to-be 3)
          (expect (cl-weave::test-event-status event) :to-be :error)
          (expect (cl-weave::test-event-condition event)
                  :to-be (first conditions))))))

  #+sbcl
  (it "does not turn timeouts into expected passes"
    (let* ((test (cl-weave::make-test-case
                  :name "timed out test"
                  :timeout-ms 10
                  :expected-failure-reason "known assertion bug"
                  :function (lambda () (sleep 1))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-condition event)
              :to-be-instance-of 'cl-weave:test-timeout)))

  #+sbcl
  (it "retries timeouts without converting the final timeout"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "persistently timed out test"
                  :retry 1
                  :timeout-ms 10
                  :expected-failure-reason "known assertion bug"
                  :function (lambda ()
                              (incf attempts)
                              (sleep 1))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 2)
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-condition event)
              :to-be-instance-of 'cl-weave:test-timeout))))
