(in-package #:cl-weave/test)

(defun run-soft-test (thunk)
  (let ((test (cl-weave::make-test-case :name "soft subject" :function thunk)))
    (cl-weave::run-test-case (cl-weave::root-suite) test)))

(describe "soft assertions"
  (it "runs every expectation and aggregates the failures"
    (let* ((reached nil)
           (event (run-soft-test
                   (lambda ()
                     (cl-weave:with-soft-assertions
                       (expect 1 :to-be 2)
                       (expect 3 :to-be 3)
                       (expect 4 :to-be 5)
                       (setf reached t))))))
      (expect reached :to-be t)
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (let ((detail (cl-weave::test-event-assertion event)))
        (expect (cl-weave::assertion-detail-matcher detail) :to-be :soft-assertions)
        (expect (getf (cl-weave::assertion-detail-actual detail) :failures)
                :to-be 2)
        (expect (length (getf (cl-weave::assertion-detail-actual detail) :details))
                :to-be 2))))

  (it "passes when every soft expectation passes"
    (let ((event (run-soft-test
                  (lambda ()
                    (cl-weave:with-soft-assertions
                      (expect 1 :to-be 1)
                      (expect 2 :to-be 2))))))
      (expect (cl-weave::test-event-status event) :to-be :pass)))

  (it "still aborts immediately on a real error"
    ;; A real error propagates as :error instead of being aggregated as a soft
    ;; :fail, which proves the block stopped at the error.
    (let ((event (run-soft-test
                  (lambda ()
                    (cl-weave:with-soft-assertions
                      (expect 1 :to-be 2)
                      (error "boom"))))))
      (expect (cl-weave::test-event-status event) :to-be :error)))

  (it "leaves the sink unbound outside the block"
    (run-soft-test
     (lambda ()
       (cl-weave:with-soft-assertions
         (expect 1 :to-be 1))
       (expect cl-weave::*soft-assertion-sink* :to-be nil)))))

(describe "soft assertions journal integration"
  (it "records every soft assertion on the timeline"
    (let ((frames (cl-weave:with-execution-journal
                    (ignore-errors
                     (cl-weave:with-soft-assertions
                       (expect 1 :to-be 2)
                       (expect 3 :to-be 3))))))
      (expect (length frames) :to-be 2)
      (expect (cl-weave:journal-frame-pass (first frames)) :to-be nil)
      (expect (cl-weave:journal-frame-pass (second frames)) :to-be t))))
