(in-package #:cl-weave/cli)

(defun report-framework-metadata (options stream)
  (let ((metadata (cl-weave/metadata:framework-metadata)))
    (case (metadata-reporter options)
      (:json (cl-weave/metadata::write-framework-metadata-json metadata stream))
      (:sexp (write metadata :stream stream :pretty t)
             (terpri stream)))))

(defun report-doctor (options stream)
  (let ((report (doctor-report options)))
    (case (doctor-reporter options)
      (:json (write-doctor-report-json report stream))
      (:sexp (write report :stream stream :pretty t)
             (terpri stream)))
    ;; The doctor command's result reflects its report so a failing check
    ;; surfaces as a non-zero process exit that CI can gate on. A warning is
    ;; advisory and still succeeds; only an outright failure is unsuccessful.
    (not (string= (getf report :status) "fail"))))
