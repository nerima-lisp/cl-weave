(in-package #:cl-weave/tests)

(describe "result status public API"
  (it "accepts passing and non-failing test events"
    (expect (cl-weave:results-status
             (list (cl-weave::make-test-event :status :pass)
                   (cl-weave::make-test-event :status :skip)))
            :to-be-truthy))

  (it "rejects a result set containing a failure"
    (expect (cl-weave:results-status
             (list (cl-weave::make-test-event :status :pass)
                   (cl-weave::make-test-event :status :fail)))
            :to-be-falsy))

  (it "normalizes arbitrarily nested event trees"
    (let ((cases
            `((nil t)
              ((,(cl-weave::make-test-event :status :pass)) t)
              ((nil (,(cl-weave::make-test-event :status :skip)
                      (,(cl-weave::make-test-event :status :todo)))) t)
              (((,(cl-weave::make-test-event :status :pass))
                (,(cl-weave::make-test-event :status :error))) nil))))
      (dolist (case cases)
        (destructuring-bind (results expected-status) case
          (expect (cl-weave:results-status results)
                  :to-be
                  expected-status)))))

  (it "validates remaining leaves after finding a failure"
    (let ((failure (cl-weave::make-test-event :status :fail)))
      (expect (lambda ()
                (cl-weave:results-status (list failure :invalid)))
              :to-throw
              "expected test events or nested event lists")))

  (it "handles a large flat result set without recursion"
    (let* ((event (cl-weave::make-test-event :status :pass))
           (results (loop repeat 4097 collect event)))
      (expect (cl-weave:results-status results)
              :to-be-truthy)))

  (it "rejects circular result trees"
    (let ((results (list (cl-weave::make-test-event :status :pass))))
      (setf (cdr results) results)
      (expect (lambda ()
                (cl-weave:results-status results))
              :to-throw
              "circular nested event lists are not supported")))

  (it "rejects every non-event leaf in a result tree"
    (dolist (invalid-results
             '(42
               (:not-an-event)
               ((:nested :invalid))
               (nil . :invalid-tail)))
      (expect (lambda ()
                (cl-weave:results-status invalid-results))
              :to-throw
              "expected test events or nested event lists"))))
