(in-package #:cl-weave/test)

(describe "reporter artifact schemas"
  (it "enforces the reporter artifact schema contract uniformly"
    (let ((schemas (cl-weave:reporter-artifact-schemas)))
      (expect (mapcar (lambda (schema) (getf schema :kind)) schemas)
              :to-equal
              (remove-duplicates
               (mapcar (lambda (schema) (getf schema :kind)) schemas)
               :test #'string=))
      (dolist (schema schemas)
        (expect (getf schema :kind) :not :to-be nil)
        (expect (loop for (key) on schema by #'cddr
                      thereis (eq key :commands))
                :to-be t)
        (expect (getf schema :reporters) :not :to-be nil)
        (expect (getf schema :schema-version) :to-be-greater-than 0)
        (expect (getf schema :streaming) :to-satisfy
                (lambda (value) (member value '(nil t))))
        (let ((field-names
                (mapcar (lambda (field) (getf field :name))
                        (getf schema :fields))))
          (expect field-names
                  :to-equal (remove-duplicates field-names :test #'string=)))
        (dolist (field (getf schema :fields))
          (expect (getf field :name) :not :to-be nil)
          (expect (getf field :kind) :not :to-be nil)
          (expect (getf field :required) :to-be t)))))

  (it "validates declarative reporter schema contracts at definition time"
    (let ((cl-weave::*reporter-artifact-schemas* cl-weave::*reporter-artifact-schemas*))
      (eval '(cl-weave::define-reporter-artifact-schemas
              (:kind "fuzz-test-schema" :commands ("run") :reporters ("json")
               :schema-version 1 :streaming nil
               :fields ((:name "value" :kind "string" :required t
                         :description "d")))))
      (expect (find "fuzz-test-schema" (cl-weave:reporter-artifact-schemas)
                    :key (lambda (schema) (getf schema :kind))
                    :test #'string=)
              :not :to-be nil))
    (expect (lambda ()
              (eval '(cl-weave::define-reporter-artifact-schemas
                      (:commands () :reporters () :schema-version 1
                       :streaming nil :fields ()))))
            :to-throw
            "must declare :KIND")
    (expect (lambda ()
              (eval '(cl-weave::define-reporter-artifact-schemas
                      (:kind "dup" :commands () :reporters () :schema-version 1
                       :streaming nil :fields ())
                      (:kind "dup" :commands () :reporters () :schema-version 1
                       :streaming nil :fields ()))))
            :to-throw
            "contains duplicate")
    (expect (lambda ()
              (eval '(cl-weave::define-reporter-artifact-schemas
                      (:kind "missing-field-kind" :commands () :reporters ()
                       :schema-version 1 :streaming nil
                       :fields ((:name "x" :required t))))))
            :to-throw
            "must declare :KIND")
    (expect (lambda ()
              (eval '(cl-weave::define-reporter-artifact-schemas
                      (:kind "dup-field-names" :commands () :reporters ()
                       :schema-version 1 :streaming nil
                       :fields ((:name "x" :kind "string" :required t)
                                (:name "x" :kind "string" :required t))))))
            :to-throw
            "contains duplicate"))

  (it "protects reporter schema data from callers"
    (let ((schemas (cl-weave:reporter-artifact-schemas)))
      (setf (getf (first schemas) :kind) "mutated")
      (expect (getf (first (cl-weave:reporter-artifact-schemas)) :kind)
              :to-equal "test-results")))

  (it "exposes stable reporter artifact schema metadata"
    (labels ((schema-for (kind)
               (find-metadata-entry
                :kind kind (cl-weave:reporter-artifact-schemas)))
             (field-names (schema)
               (mapcar (lambda (entry) (getf entry :name))
                       (getf schema :fields))))
      (let ((results (schema-for "test-results"))
            (sexp-results (schema-for "cl-weave/results"))
            (event-stream (schema-for "test-event"))
            (plan (schema-for "test-plan"))
            (plan-entry (schema-for "test-plan-entry"))
            (mutations (schema-for "mutations")))
        (expect results :not :to-be nil)
        (expect (getf results :commands) :to-equal '("run" "watch"))
        (expect (getf results :reporters) :to-equal '("json"))
        (expect (getf results :schema-version) :to-be 6)
        (expect (getf results :streaming) :to-be nil)
        (expect (field-names results)
                :to-equal '("schemaVersion" "kind" "events"
                            "passed" "skipped" "todos" "failed" "errored"
                            "failedPaths" "erroredPaths"))

        (expect sexp-results :not :to-be nil)
        (expect (getf sexp-results :reporters) :to-equal '("sexp"))
        (expect (getf sexp-results :schema-version) :to-be 4)
        (expect (field-names sexp-results)
                :to-equal '("schema-version" "events"
                            "passed" "skipped" "todos" "failed" "errored"
                            "failed-paths" "errored-paths"))

        (expect event-stream :not :to-be nil)
        (expect (getf event-stream :commands) :to-equal '("run" "watch"))
        (expect (getf event-stream :reporters) :to-equal '("jsonl"))
        (expect (getf event-stream :schema-version) :to-be 3)
        (expect (getf event-stream :streaming) :to-be t)
        (expect (field-names event-stream)
                :to-equal '("schemaVersion" "kind" "event"))

        (expect plan :not :to-be nil)
        (expect (getf plan :commands) :to-equal '("list"))
        (expect (getf plan :reporters) :to-equal '("json" "sexp"))
        (expect (getf plan :schema-version) :to-be 3)
        (expect (getf plan :streaming) :to-be nil)
        (expect (field-names plan)
                :to-equal '("schemaVersion" "kind" "tests" "summary"))

        (expect plan-entry :not :to-be nil)
        (expect (getf plan-entry :commands) :to-equal '("list"))
        (expect (getf plan-entry :reporters) :to-equal '("jsonl"))
        (expect (getf plan-entry :schema-version) :to-be 2)
        (expect (getf plan-entry :streaming) :to-be t)
        (expect (field-names plan-entry)
                :to-equal '("schemaVersion" "kind" "test" "test.status"
                            "test.path" "test.pathString" "test.location"
                            "test.reason" "test.focused" "test.retry"
                            "test.timeoutMs" "test.concurrent" "test.tags"))

        (expect mutations :not :to-be nil)
        (expect (getf mutations :commands) :to-equal '())
        (expect (getf mutations :reporters) :to-equal '("json" "sexp"))
        (expect (getf mutations :schema-version) :to-be 1)
        (expect (getf mutations :streaming) :to-be nil)
        (expect (field-names mutations)
                :to-equal '("schemaVersion" "kind" "total" "killed"
                            "survived" "errored" "score" "results")))))

  (it "keeps reporter artifact schemas aligned with emitted artifacts"
    (labels ((schema-for (kind)
               (find-metadata-entry
                :kind kind (cl-weave:reporter-artifact-schemas))))
      (let* ((events (list (make-sample-event
                            :status :pass
                            :path '("schema" "result"))
                           (make-sample-event
                            :status :fail
                            :path '("schema" "failure")
                            :reason "boom")))
             (plan (list (cl-weave::make-test-plan-entry
                          :status :run
                          :path '("schema" "plan")
                          :location '(:file "tests/reporters.lisp")
                          :focused t
                          :retry 1
                          :timeout-ms 50
                          :concurrent t)))
             (mutations (run-mutations '(+ 1 1)
                                       (lambda (form mutation)
                                         (declare (ignore mutation))
                                         (= (eval form) 2))))
             (json-output (with-output-to-string (stream)
                            (cl-weave::report-json events stream)))
             (jsonl-output (with-output-to-string (stream)
                             (cl-weave::report-jsonl events stream)))
             (plan-output (with-output-to-string (stream)
                            (cl-weave::report-plan-json plan stream)))
             (plan-jsonl-output (with-output-to-string (stream)
                                  (cl-weave::report-plan-jsonl plan stream)))
             (mutation-output (with-output-to-string (stream)
                                (cl-weave:report-mutations-json mutations stream))))
        (let ((results (schema-for "test-results"))
              (results-start (schema-for "test-results-start"))
              (event-stream (schema-for "test-event"))
              (results-summary (schema-for "test-results-summary"))
              (plan-schema (schema-for "test-plan"))
              (plan-start (schema-for "test-plan-start"))
              (plan-entry (schema-for "test-plan-entry"))
              (plan-summary (schema-for "test-plan-summary"))
              (mutation-schema (schema-for "mutations")))
          (expect json-output
                  :to-contain
                  (format nil "\"schemaVersion\":~D,\"kind\":\"~A\""
                          (getf results :schema-version)
                          (getf results :kind)))
          (expect json-output :to-contain "\"events\":[")
          (expect json-output :to-contain "\"failedPaths\":[\"schema > failure\"]")

          (expect jsonl-output
                  :to-contain
                  (format nil "\"schemaVersion\":~D,\"kind\":\"~A\""
                          (getf results-start :schema-version)
                          (getf results-start :kind)))
          (expect jsonl-output
                  :to-contain
                  (format nil "\"schemaVersion\":~D,\"kind\":\"~A\""
                          (getf event-stream :schema-version)
                          (getf event-stream :kind)))
          (expect jsonl-output
                  :to-contain
                  (format nil "\"schemaVersion\":~D,\"kind\":\"~A\""
                          (getf results-summary :schema-version)
                          (getf results-summary :kind)))

          (expect plan-output
                  :to-contain
                  (format nil "\"schemaVersion\":~D,\"kind\":\"~A\""
                          (getf plan-schema :schema-version)
                          (getf plan-schema :kind)))
          (expect plan-output :to-contain "\"tests\":[")

          (expect plan-jsonl-output
                  :to-contain
                  (format nil "\"schemaVersion\":~D,\"kind\":\"~A\""
                          (getf plan-start :schema-version)
                          (getf plan-start :kind)))
          (expect plan-jsonl-output
                  :to-contain
                  (format nil "\"schemaVersion\":~D,\"kind\":\"~A\""
                          (getf plan-entry :schema-version)
                          (getf plan-entry :kind)))
          (expect plan-jsonl-output
                  :to-contain
                  (format nil "\"schemaVersion\":~D,\"kind\":\"~A\""
                          (getf plan-summary :schema-version)
                          (getf plan-summary :kind)))

          (expect mutation-output
                  :to-contain
                  (format nil "\"schemaVersion\":~D,\"kind\":\"~A\""
                          (getf mutation-schema :schema-version)
                          (getf mutation-schema :kind)))
          (expect mutation-output :to-contain "\"score\":")
          (expect mutation-output :to-contain "\"results\":[")))))

  (it "summarizes results and plans in one stable schema pass"
    (let ((events (list
                   (make-sample-event :status :fail :path (quote ("suite" "fail-1")))
                   (make-sample-event :status :unknown :path (quote ("suite" "unknown")))
                   (make-sample-event :status :error :path (quote ("suite" "error-1")))
                   (make-sample-event :status :fail :path (quote ("suite" "fail-2")))
                   (make-sample-event :status :pass :path (quote ("suite" "pass")))
                   (make-sample-event :status :skip :path (quote ("suite" "skip")))
                   (make-sample-event :status :todo :path (quote ("suite" "todo")))))
          (plan (list
                 (cl-weave::make-test-plan-entry :status :run :path (quote ("suite" "run-1")))
                 (cl-weave::make-test-plan-entry :status :unknown :path (quote ("suite" "unknown")))
                 (cl-weave::make-test-plan-entry :status :skip :path (quote ("suite" "skip")))
                 (cl-weave::make-test-plan-entry :status :todo :path (quote ("suite" "todo")))
                 (cl-weave::make-test-plan-entry :status :run :path (quote ("suite" "run-2"))))))
      (expect (cl-weave::result-summary events)
              :to-equal
              (quote (:total 7 :passed 1 :skipped 1 :todos 1 :failed 2 :errored 1
                      :failed-paths ("suite > fail-1" "suite > fail-2")
                      :errored-paths ("suite > error-1"))))
      (expect (cl-weave::plan-summary plan)
              :to-equal
              (quote (:total 5 :runnable 2 :skipped 1 :todos 1)))
      (expect (cl-weave::result-summary nil)
              :to-equal
              (quote (:total 0 :passed 0 :skipped 0 :todos 0 :failed 0 :errored 0
                      :failed-paths nil :errored-paths nil)))
      (expect (cl-weave::plan-summary nil)
              :to-equal
              (quote (:total 0 :runnable 0 :skipped 0 :todos 0))))))
