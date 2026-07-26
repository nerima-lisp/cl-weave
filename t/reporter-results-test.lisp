(in-package #:cl-weave/test)

(describe "reporter result formats"
  (it "rejects unknown run reporters before dispatch"
    (expect (lambda ()
              (with-output-to-string (stream)
                (cl-weave:run-all :reporter :unknown :stream stream)))
            :to-throw
            "cl-weave: run mode supports"))

  (it "prints AI-readable S-expression results"
    (let ((output (with-output-to-string (stream)
                      (cl-weave::report-sexp
                      (list (make-sample-event
                             :status :pass
                             :path '("reporters" "prints")
                             :location '(:file "tests/reporters.lisp"))
                            (make-sample-event
                             :status :skip
                             :path '("reporters" "skips")
                             :reason "example")
                            (make-sample-event
                            :status :todo
                            :path '("reporters" "todos")
                            :reason "pending")
                            (make-sample-event
                             :status :fail
                             :path '("reporters" "fails")
                             :reason "bad"
                             :secondary-conditions '("cleanup one" "cleanup two"))
                            (make-sample-event
                             :status :error
                             :path '("reporters" "errors")))
                      stream))))
      (expect output :to-contain ":CL-WEAVE/RESULTS")
      (expect output :to-contain ":SCHEMA-VERSION 4")
      (expect output :to-contain ":PATH-STRING \"reporters > prints\"")
      (expect output :to-contain ":LOCATION (:FILE \"tests/reporters.lisp\")")
      (expect output :to-contain ":DURATION-MS 0")
      (expect output :to-contain ":SKIPPED")
      (expect output :to-contain ":TODOS")
      (expect output :to-contain ":TODO")
      (expect output :to-contain ":FAILED-PATHS")
      (expect output :to-contain "\"reporters > fails\"")
      (expect output :to-contain ":ERRORED-PATHS")
      (expect output :to-contain "\"reporters > errors\"")
      ;; The pretty printer may wrap between the key and its value.
      (expect (normalize-command-document-text output) :to-contain
              ":SECONDARY-CONDITIONS (\"cleanup one\" \"cleanup two\")")))

  (it "prints secondary conditions in order in spec output"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-spec
                     (list (make-sample-event
                            :status :fail
                            :path '("reporters" "cleanup")
                            :condition "primary"
                            :secondary-conditions '("cleanup one" "cleanup two")))
                     stream))))
      (expect output :to-contain
              (format nil "secondary condition: cleanup one~%    secondary condition: cleanup two"))))

  (it "prints AI-readable JSON results"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-json
                     (list (make-sample-event
                            :status :pass
                            :path '("reporters" "json")
                            :location '(:file "tests/reporters.lisp"))
                           (make-sample-event
                            :status :skip
                            :path '("reporters" "quotes")
                            :reason "needs \"escaping\"")
                           (make-sample-event
                            :status :fail
                            :path '("reporters" "fails")
                            :reason "bad"
                            :secondary-conditions '("cleanup one" "cleanup two"))
                           (make-sample-event
                            :status :error
                            :path '("reporters" "errors")))
                     stream))))
      (expect output :to-contain "\"schemaVersion\":6")
      (expect output :to-contain "\"kind\":\"test-results\"")
      (expect output :to-contain "\"passed\":1")
      (expect output :to-contain "\"skipped\":1")
      (expect output :to-contain "\"failed\":1")
      (expect output :to-contain "\"errored\":1")
      (expect output :to-contain "\"failedPaths\":[\"reporters > fails\"]")
      (expect output :to-contain "\"erroredPaths\":[\"reporters > errors\"]")
      (expect output :to-contain "\"status\":\"pass\"")
      (expect output :to-contain "\"path\":[\"reporters\",\"json\"]")
      (expect output :to-contain "\"pathString\":\"reporters > json\"")
      (expect output :to-contain "\"location\":{\"file\":\"tests\\/reporters.lisp\"}")
      (expect output :to-contain "\"durationMs\":0.000")
      (expect output :to-contain "\"reason\":\"needs \\\"escaping\\\"\"")
      (expect output :to-contain "\"secondaryConditions\":[]")
      (expect output :to-contain
              "\"secondaryConditions\":[\"cleanup one\",\"cleanup two\"]")
      (expect output :to-contain "\"assertion\":null")))

  (it "serializes assertion payloads as structured JSON data"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-json
                     (list (make-sample-event
                            :status :fail
                            :path '("reporters" "isolated")
                            :condition "isolated process failed"
                            :assertion (cl-weave::make-assertion-detail
                                        :form '(expect (run-isolated body) :to-satisfy #'identity)
                                        :matcher :isolated
                                        :actual '(:status :timeout
                                                  :exit-code nil
                                                  :timed-out-p t
                                                  :elapsed-ms 100
                                                  :stdout ""
                                                  :stderr ""
                                                  :script-path "/tmp/cl-weave-isolated.lisp"
                                                  :stdout-path "/tmp/cl-weave-isolated.stdout"
                                                  :stderr-path "/tmp/cl-weave-isolated.stderr"
                                                  :home-path "/tmp/cl-weave-home/")
                                        :expected '(:status :pass :exit-code 0)
                                        :negated nil
                                        :pass nil)))
                     stream))))
      (expect output :to-contain "\"schemaVersion\":6")
      (expect output :to-contain "\"matcher\":\":ISOLATED\"")
      (expect output :to-contain "\"actual\":{\"status\":\"timeout\"")
      (expect output :to-contain "\"timedOutP\":true")
      (expect output :to-contain "\"elapsedMs\":100")
      (expect output :to-contain "\"scriptPath\":\"\\/tmp\\/cl-weave-isolated.lisp\"")
      (expect output :to-contain "\"stdoutPath\":\"\\/tmp\\/cl-weave-isolated.stdout\"")
      (expect output :to-contain "\"stderrPath\":\"\\/tmp\\/cl-weave-isolated.stderr\"")
      (expect output :to-contain "\"homePath\":\"\\/tmp\\/cl-weave-home\\/\"")
      (expect output :to-contain "\"expected\":{\"status\":\"pass\",\"exitCode\":0}")))

  (it "prints AI-readable JSONL result streams"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-jsonl
                     (list (make-sample-event
                            :status :pass
                            :path '("reporters" "jsonl")
                            :location '(:file "tests/reporters.lisp"))
                           (make-sample-event
                           :status :fail
                           :path '("reporters" "fails")
                           :reason "bad"
                            :secondary-conditions
                            (list (make-condition 'simple-error
                                                  :format-control "cleanup"))))
                     stream))))
      (expect (with-input-from-string (stream output)
                (loop for line = (read-line stream nil nil)
                      while line
                      count line))
              :to-be 4)
      (expect output :to-contain "\"kind\":\"test-results-start\"")
      (expect output :to-contain "\"schemaVersion\":1,\"kind\":\"test-results-start\"")
      (expect output :to-contain "\"total\":2")
      (expect output :to-contain "\"kind\":\"test-event\"")
      (expect output :to-contain "\"schemaVersion\":3,\"kind\":\"test-event\"")
      (expect output :to-contain "\"event\":{\"status\":\"pass\"")
      (expect output :to-contain "\"pathString\":\"reporters > jsonl\"")
      (expect output :to-contain "\"secondaryConditions\":[\"cleanup\"]")
      (expect output :to-contain "\"kind\":\"test-results-summary\"")
      (expect output :to-contain "\"schemaVersion\":1,\"kind\":\"test-results-summary\"")
      (expect output :to-contain "\"failed\":1")
      (expect output :to-contain "\"failedPaths\":[\"reporters > fails\"]")))

  (it "escapes JSON strings with portable control-character rules"
    (let ((escaped (cl-weave::json-escaped-string
                    (coerce (list #\" #\\
                                  (code-char 8)
                                  (code-char 9)
                                  (code-char 10)
                                  (code-char 12)
                                  (code-char 13)
                                  (code-char 1))
                            'string))))
      (expect escaped :to-equal
              (concatenate 'string
                           "\\\""
                           "\\\\"
                           "\\b"
                           "\\t"
                           "\\n"
                           "\\f"
                           "\\r"
                           "\\u0001"))))

  (it-fuzz "escapes arbitrary strings into JSON with no raw quote or control character"
      ((text (gen-string
              :min-length 0 :max-length 40
              :alphabet (coerce (list #\" #\\ #\/ (code-char 8) (code-char 9)
                                      (code-char 10) (code-char 12) (code-char 13)
                                      (code-char 0) (code-char 1) (code-char 31)
                                      #\a #\z #\Space #\0)
                                'string))))
      (:trials 300 :timeout-per-trial 1)
    (expect (json-escaped-output-safe-p (cl-weave::json-escaped-string text))
            :to-be-truthy))

  (it "serializes Common Lisp values without producing invalid JSON"
    (let* ((circular (list :head))
           (output
             (progn
               (setf (cdr circular) circular)
               (with-output-to-string (stream)
                 (cl-weave::json-write-value
                  (list :ratio 1/3
                        :complex #C(1 2)
                        :circular circular)
                  stream)))))
      (expect output :to-contain "\"ratio\":\"1\\/3\"")
      (expect output :to-contain "\"complex\":\"#C(1 2)\"")
      (expect output :to-contain "\"circular\":\"")
      (expect output :to-contain "#1=")
      (expect output :to-contain "#1#")))

  (it "serializes JSON objects, arrays, and scalar extensions predictably"
    (flet ((encode (value)
             (with-output-to-string (stream)
               (cl-weave::json-write-value value stream))))
      (dolist (case
               (list
                (list '(:long-key 1 :empty--part 2)
                      "{\"longKey\":1,\"emptyPart\":2}")
                (list (list (cons :keyword-key 1)
                            (cons "string-key" 2)
                            (cons 'symbol-key 3))
                      "{\"keywordKey\":1,\"string-key\":2,\"symbol-key\":3}")
                ;; A list of plists (e.g. the smart-assertion operand reports)
                ;; must serialize as an array of objects, not collapse into one
                ;; object with duplicate keys.
                (list '((:form a :value 1) (:form b :value 2))
                      "[{\"form\":\"A\",\"value\":1},{\"form\":\"B\",\"value\":2}]")
                (list '(1 :array-value) "[1,\"array-value\"]")
                (list #\A "\"A\"")
                (list #P"relative/path" "\"relative\\/path\"")
                (list 'plain-symbol "\"PLAIN-SYMBOL\"")
                (list (cons :head :tail) "\"(:HEAD . :TAIL)\"")))
        (expect (encode (first case)) :to-equal (second case)))))

  (it "cleans up JSON cycle tracking after writer failures"
    (let ((value (list :value))
          (cl-weave::*json-active-values* (make-hash-table :test #'eq)))
      (expect (lambda ()
                (cl-weave::call-with-json-composite
                 value *standard-output*
                 (lambda () (error "writer failed"))))
              :to-throw "writer failed")
      (expect (gethash value cl-weave::*json-active-values*) :to-be nil)
      (expect (with-output-to-string (stream)
                (cl-weave::json-write-value value stream))
              :to-equal "[\"value\"]")))

  (it "terminates on vector and mixed composite cycles"
    (let* ((vector (make-array 1))
           (list (list vector)))
      (setf (aref vector 0) vector)
      (expect (with-output-to-string (stream)
                (cl-weave::json-write-value vector stream))
              :to-contain "#1#")
      (setf (aref vector 0) list)
      (expect (with-output-to-string (stream)
                (cl-weave::json-write-value list stream))
              :to-contain "#1#")))

)
