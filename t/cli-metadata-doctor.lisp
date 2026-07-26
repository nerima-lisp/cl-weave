(in-package #:cl-weave/test)

(describe "cli metadata doctor"
  (it "prints machine-readable doctor output"
    (let ((options (parse-cli '("doctor" "--reporter" "json"))))
      (let ((output (with-output-to-string (stream)
                      (cl-weave/cli::report-doctor options stream))))
        (expect output :to-contain "\"kind\":\"doctor-report\"")
        (expect output :to-contain "\"schemaVersion\":1")
        (expect output :to-contain "\"status\":\"")
        (expect output :to-contain "\"runtime\"")
        (expect output :to-contain "\"checks\"")
        (expect output :to-contain "\"name\":\"command-metadata\"")
        (expect output :to-contain "\"name\":\"workspace-asd-files\""))))

  (it "renders doctor output from the parsed CLI options"
    (let* ((options (parse-cli '("doctor" "definitely-missing-system"
                       "--reporter" "json"
                       "--output" "doctor.json")))
           (output (with-output-to-string (stream)
                     (cl-weave/cli::report-doctor options stream))))
      (expect output :to-contain "\"name\":\"requested-system\"")
      (expect output :to-contain "\"status\":\"fail\"")
      (expect output :to-contain "definitely-missing-system")
      (expect output :to-contain "\"name\":\"output-target\"")
      (expect output :to-contain "doctor.json")))

  (it "allows Lisp-native doctor output"
    (let ((options (parse-cli '("doctor" "--reporter" "sexp"))))
      (let ((output (with-output-to-string (stream)
                      (cl-weave/cli::report-doctor options stream))))
        (expect output :to-contain ":KIND \"doctor-report\"")
        (expect output :to-contain ":CHECKS")
        (expect output :to-contain ":RUNTIME"))))

  (it "treats doctor without a positional system as runtime-only diagnostics"
    (let* ((options (parse-cli '("doctor" "--reporter" "json")))
           (report (cl-weave/cli::doctor-report options))
           (checks (getf report :checks))
           (requested-system
             (find-metadata-entry :name "requested-system" checks))
           (output-target
             (find-metadata-entry :name "output-target" checks)))
      (expect (getf requested-system :status) :to-equal "pass")
      (expect (getf requested-system :summary)
              :to-contain "runtime-only mode")
      (expect (getf output-target :status) :to-equal "pass")
      (expect (getf output-target :summary)
              :to-contain "standard output")))

  (it "reports requested-system failures independently from runtime diagnostics"
    (let* ((options (parse-cli '("doctor" "definitely-missing-system" "--output" "doctor.json")))
           (report (cl-weave/cli::doctor-report options))
           (checks (getf report :checks))
           (cl-weave-system
             (find-metadata-entry :name "cl-weave-system" checks))
           (requested-system
             (find-metadata-entry :name "requested-system" checks))
           (output-target
             (find-metadata-entry :name "output-target" checks)))
      (expect (getf cl-weave-system :status) :to-equal "pass")
      (expect (getf requested-system :status) :to-equal "fail")
      (expect (getf requested-system :summary)
              :to-contain "definitely-missing-system")
      (expect (getf output-target :summary)
              :to-contain "doctor.json")))

)
