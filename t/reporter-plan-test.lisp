(in-package #:cl-weave/test)

(describe "reporter test plans"
  (it "prints AI-readable S-expression test plans"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-plan-sexp
                     (list (cl-weave::make-test-plan-entry
                            :status :run
                           :path '("plan" "runs")
                            :location '(:file "tests/plan.lisp")
                            :focused t
                            :retry 2
                            :timeout-ms 250
                            :concurrent t)
                           (cl-weave::make-test-plan-entry
                            :status :skip
                            :path '("plan" "skips")
                            :reason "blocked"
                            :focused nil
                            :retry 0))
                     stream))))
      (expect output :to-contain ":CL-WEAVE/TEST-PLAN")
      (expect output :to-contain ":SCHEMA-VERSION 3")
      (expect output :to-contain ":RUNNABLE 1")
      (expect output :to-contain ":SKIPPED 1")
      (expect output :to-contain ":PATH-STRING \"plan > runs\"")
      (expect output :to-contain ":LOCATION")
      (expect output :to-contain ":FILE \"tests/plan.lisp\"")
      (expect output :to-contain ":FOCUSED T")
      (expect output :to-contain ":TIMEOUT-MS 250")
      (expect output :to-contain ":CONCURRENT T")))

  (it "prints AI-readable JSON test plans"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-plan-json
                     (list (cl-weave::make-test-plan-entry
                            :status :run
                            :path '("plan" "runs")
                            :location '(:file "tests/plan.lisp")
                            :focused t
                            :retry 2
                            :timeout-ms 250
                            :concurrent t)
                           (cl-weave::make-test-plan-entry
                            :status :skip
                            :path '("plan" "skips")
                            :reason "blocked"
                            :focused nil
                            :retry 0))
                     stream))))
      (expect output :to-contain "\"schemaVersion\":3")
      (expect output :to-contain "\"kind\":\"test-plan\"")
      (expect output :to-contain "\"runnable\":1")
      (expect output :to-contain "\"skipped\":1")
      (expect output :to-contain "\"status\":\"run\"")
      (expect output :to-contain "\"pathString\":\"plan > runs\"")
      (expect output :to-contain "\"location\":{\"file\":\"tests\\/plan.lisp\"}")
      (expect output :to-contain "\"focused\":true")
      (expect output :to-contain "\"retry\":2")
      (expect output :to-contain "\"timeoutMs\":250")
      (expect output :to-contain "\"concurrent\":true")
      (expect output :to-contain "\"reason\":\"blocked\"")))

  (it "prints AI-readable JSONL test plans"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-plan-jsonl
                     (list (cl-weave::make-test-plan-entry
                            :status :run
                            :path '("plan" "runs")
                            :location '(:file "tests/plan.lisp")
                            :focused t
                            :retry 2
                            :timeout-ms 250
                            :concurrent t)
                           (cl-weave::make-test-plan-entry
                            :status :skip
                            :path '("plan" "skips")
                            :reason "blocked"
                            :focused nil
                            :retry 0))
                     stream))))
      (expect (with-input-from-string (stream output)
                (loop for line = (read-line stream nil nil)
                      while line
                      count line))
              :to-be 4)
      (expect output :to-contain "\"kind\":\"test-plan-start\"")
      (expect output :to-contain "\"schemaVersion\":1,\"kind\":\"test-plan-start\"")
      (expect output :to-contain "\"kind\":\"test-plan-entry\"")
      (expect output :to-contain "\"schemaVersion\":2,\"kind\":\"test-plan-entry\"")
      (expect output :to-contain "\"test\":{\"status\":\"run\"")
      (expect output :to-contain "\"pathString\":\"plan > runs\"")
      (expect output :to-contain "\"kind\":\"test-plan-summary\"")
      (expect output :to-contain "\"schemaVersion\":1,\"kind\":\"test-plan-summary\"")
      (expect output :to-contain "\"runnable\":1")
      (expect output :to-contain "\"skipped\":1")))

)
