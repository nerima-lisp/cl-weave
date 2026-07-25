(in-package #:cl-weave/test)

(defmacro with-registered-demo-suites ((&rest names) &body body)
  "Run BODY against a fresh root suite containing one passing test per name."
  `(let ((cl-weave::*root-suite* (cl-weave::make-suite :name "root"))
         (cl-weave::*current-suite* nil)
         (cl-weave::*named-suites* (make-hash-table :test #'equal)))
     ,@(loop for name in names
             collect `(describe ,name
                        (it "passes"
                          (expect 1 :to-be 1))))
     ,@body))

(describe "runner public API"
  (it "exports the registered root suite"
    (with-registered-demo-suites ("root suite api")
      (multiple-value-bind (symbol status)
          (find-symbol "ROOT-SUITE" "CL-WEAVE")
        (expect status :to-be :external)
        (expect symbol :to-be 'cl-weave:root-suite))
      (expect (cl-weave:root-suite) :to-be cl-weave::*root-suite*)))

  (it "runs a suite selected by its name designator"
    (with-registered-demo-suites ("selected api suite" "other api suite")
      (let ((events (cl-weave:run "selected api suite"
                                  :reporter :sexp
                                  :stream (make-broadcast-stream))))
        (expect (length events) :to-be 1)
        (expect (cl-weave::test-event-status (first events)) :to-be :pass)
        (expect (cl-weave::test-event-path (first events))
                :to-equal '("selected api suite" "passes")))))

  (it "caches named suite designators between runs"
    (with-registered-demo-suites ("cached api suite")
      (cl-weave:run "cached api suite" :stream (make-broadcast-stream))
      (let ((cached (gethash (cl-weave::named-suite-key "cached api suite")
                             cl-weave::*named-suites*)))
        (expect cached :to-satisfy #'cl-weave::suite-p)
        (expect (cl-weave:run "cached api suite"
                              :stream (make-broadcast-stream))
                :to-satisfy #'consp))))

  (it "runs a suite object and the root suite designator directly"
    (with-registered-demo-suites ("object api suite")
      (let ((suite (cl-weave::find-suite-by-designator "object api suite")))
        (expect suite :to-satisfy #'cl-weave::suite-p)
        (expect (length (cl-weave:run suite :stream (make-broadcast-stream)))
                :to-be 1)
        (expect (length (cl-weave:run nil :stream (make-broadcast-stream)))
                :to-be 1))))

  (it "emits every run reporter format from RUN"
    (with-registered-demo-suites ("reporting api suite")
      (dolist (reporter '(:spec :sexp :json :jsonl :tap :github :junit))
        (let ((output (with-output-to-string (stream)
                        (cl-weave:run "reporting api suite"
                                      :reporter reporter
                                      :stream stream))))
          (expect (plusp (length output)) :to-be-truthy)))))

  (it "rejects unknown suite designators"
    (with-registered-demo-suites ("known api suite")
      (expect (lambda ()
                (cl-weave:run "missing api suite"
                              :stream (make-broadcast-stream)))
              :to-throw "unknown suite designator")))

  (it "finds nested suites by designator"
    (let ((cl-weave::*root-suite* (cl-weave::make-suite :name "root"))
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test #'equal)))
      (describe "outer api suite"
        (describe "inner api suite"
          (it "passes" (expect 1 :to-be 1))))
      (let ((inner (cl-weave::find-suite-by-designator "inner api suite")))
        (expect inner :to-satisfy #'cl-weave::suite-p)
        (expect (cl-weave::suite-name inner) :to-equal "inner api suite"))
      (expect (cl-weave::find-suite-by-designator "absent api suite")
              :to-be nil)))

  (it "normalizes nested run results and rejects foreign values"
    (with-registered-demo-suites ("normalized api suite")
      (let ((events (cl-weave:run "normalized api suite"
                                  :stream (make-broadcast-stream))))
        (expect (cl-weave::normalize-run-results (list nil events (first events)))
                :to-satisfy
                (lambda (normalized)
                  (every #'cl-weave::test-event-p normalized)))
        (expect (lambda ()
                  (cl-weave::normalize-run-results (list :not-an-event)))
                :to-throw "expected test events")
        (expect (with-output-to-string (stream)
                  (cl-weave:explain! events stream))
                :to-contain "passes"))))

  (it "lists plans through every list reporter"
    (with-registered-demo-suites ("planned api suite")
      (dolist (reporter '(:spec :sexp :json :jsonl))
        (let ((output (with-output-to-string (stream)
                        (cl-weave:list-tests :reporter reporter
                                             :stream stream))))
          (expect (plusp (length output)) :to-be-truthy)))
      (expect (length (cl-weave:list-tests :stream (make-broadcast-stream)))
              :to-be 1)))

  (it "rejects run-only reporters in list mode"
    (with-registered-demo-suites ("rejecting api suite")
      (expect (lambda ()
                (cl-weave:list-tests :reporter :tap
                                     :stream (make-broadcast-stream)))
              :to-throw "list mode supports")))

  (it "rejects atoms, closed streams, and input-only streams"
    (with-registered-demo-suites ("invalid stream api suite")
      (let ((closed-stream (make-string-output-stream)))
        (close closed-stream)
        (dolist (stream (list :not-a-stream
                              closed-stream
                              (make-string-input-stream "")))
          (expect (lambda ()
                    (cl-weave:run "invalid stream api suite"
                                  :reporter :spec
                                  :stream stream))
                  :to-throw
                  "cl-weave: expected an open output stream."))
        (expect (length (cl-weave:run "invalid stream api suite"
                                      :reporter nil
                                      :stream :not-a-stream))
                :to-be 1))))

  (it "validates RUN reporting before test execution"
    (let ((cl-weave::*root-suite* (cl-weave::make-suite :name "root"))
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test (function equal)))
          (effects 0))
      (describe "run stream preflight api suite"
        (it "does not run"
          (incf effects)))
      (expect (lambda ()
                (cl-weave:run "run stream preflight api suite"
                              :reporter :unknown
                              :stream (make-broadcast-stream)))
              :to-throw "run mode supports")
      (expect effects :to-be 0)
      (expect (lambda ()
                (cl-weave:run "run stream preflight api suite"
                              :reporter :spec
                              :stream :not-a-stream))
              :to-throw "cl-weave: expected an open output stream.")
      (expect effects :to-be 0)))

  (it "validates RUN-ALL stream before coverage and test execution"
    (let ((cl-weave::*root-suite* (cl-weave::make-suite :name "root"))
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test (function equal)))
          (coverage-thunk-count 0)
          (coverage-require-count 0)
          (coverage-reset-count 0)
          (effects 0))
      (describe "run all stream preflight api suite"
        (it "does not run"
          (incf effects)))
      (with-mocked-functions
          (((symbol-function (quote cl-weave::call-with-coverage))
            (lambda (coverage coverage-output coverage-report-directory
                     reset-p thunk &rest options)
              (declare (ignore coverage
                               coverage-output
                               coverage-report-directory
                               reset-p
                               options))
              (incf coverage-thunk-count)
              (cl-weave::require-coverage-support)
              (cl-weave:reset-coverage)
              (funcall thunk)))
           ((symbol-function (quote cl-weave::require-coverage-support))
            (lambda ()
              (incf coverage-require-count)))
           ((symbol-function (quote cl-weave:reset-coverage))
            (lambda ()
              (incf coverage-reset-count))))
        (expect (lambda ()
                  (cl-weave:run-all :coverage t
                                    :stream :not-a-stream))
                :to-throw "cl-weave: expected an open output stream."))
      (expect coverage-thunk-count :to-be 0)
      (expect coverage-require-count :to-be 0)
      (expect coverage-reset-count :to-be 0)
      (expect effects :to-be 0)))

  (it "rejects invalid streams from LIST-TESTS and EXPLAIN!"
      (with-registered-demo-suites ("invalid reporting api suite")
        (expect (lambda ()
                  (cl-weave:list-tests :stream :not-a-stream))
                :to-throw "cl-weave: expected an open output stream.")
        (expect (lambda ()
                  (cl-weave:explain! (list :not-an-event)
                                     :not-a-stream))
                :to-throw "cl-weave: expected an open output stream.")))

    (it "finds suites 50,000 levels deep without consuming the control stack"
      (let* ((root (cl-weave::make-suite :name "root"))
             (node root)
             (target nil))
        (loop repeat 49999
              do (let ((child (cl-weave::make-suite :name "nested")))
                   (setf (cl-weave::suite-children node) (list child)
                         node child)))
        (setf target (cl-weave::make-suite :name "deep target")
              (cl-weave::suite-children node) (list target))
        (expect (cl-weave::find-suite-by-designator-unlocked
                 "deep target"
                 root)
                :to-be target)))

    (it "normalizes 50,000 event conses without consuming the control stack"
      (let ((event (cl-weave::make-test-event
                    :status :pass
                    :path (list "deep")))
            (results nil))
        (loop repeat 50000
              do (push event results))
        (let ((normalized (cl-weave::normalize-run-results results)))
          (expect (length normalized) :to-be 50000)
          (expect (first normalized) :to-be event)
          (expect (car (last normalized)) :to-be event))))

    (it "rejects circular and foreign run result structures deterministically"
      (let* ((event (cl-weave::make-test-event
                     :status :pass
                     :path (list "cycle")))
             (cycle (list event))
             (message nil))
        (setf (cdr cycle) cycle)
        (handler-case
            (cl-weave::normalize-run-results cycle)
          (error (condition)
            (setf message (princ-to-string condition))))
        (expect message
                :to-equal
                "cl-weave: circular nested event lists are not supported.")
        (expect (lambda ()
                  (cl-weave::normalize-run-results :not-an-event))
                :to-throw "expected test events")
        (expect (lambda ()
                  (cl-weave::normalize-run-results
                   (cons event :not-an-event)))
                :to-throw "expected test events")))

    (it "preserves event order and expands shared result branches each time"
      (let* ((first-event (cl-weave::make-test-event
                           :status :pass
                           :path (list "first")))
             (second-event (cl-weave::make-test-event
                            :status :pass
                            :path (list "second")))
             (third-event (cl-weave::make-test-event
                           :status :pass
                           :path (list "third")))
             (shared (list first-event second-event))
             (normalized
               (cl-weave::normalize-run-results
                (list (list third-event)
                      shared
                      (list first-event)
                      shared))))
        (expect normalized
                :to-equal
                (list third-event
                      first-event
                      second-event
                      first-event
                      first-event
                      second-event)))))
