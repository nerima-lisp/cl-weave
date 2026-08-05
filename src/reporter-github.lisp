(in-package #:cl-weave)

(defun event-message (event)
  (or (test-event-reason event)
      (when (test-event-condition event)
        (princ-to-string (test-event-condition event)))
      (status-marker (test-event-status event))))

(defun event-detail-string (event)
  (with-output-to-string (stream)
    (when (test-event-condition event)
      (format stream "~A~%" (test-event-condition event)))
    (dolist (condition (test-event-secondary-conditions event))
      (format stream "secondary condition: ~A~%" condition))
    (report-assertion-detail (test-event-assertion event) stream)))

(defun github-escape-table (mappings)
  (let ((table (make-hash-table)))
    (dolist (mapping mappings table)
      (setf (gethash (car mapping) table) (cdr mapping)))))

(defparameter *github-data-escapes*
  (github-escape-table (list (cons #\% "%25")
                              (cons #\Return "%0D")
                              (cons #\Newline "%0A")))
  "Character substitutions for GitHub Actions workflow-command data values.")

(defun github-escaped-string (value escapes)
  (with-output-to-string (stream)
    (loop for char across (princ-to-string value)
          for replacement = (gethash char escapes)
          do (write-string (or replacement (string char)) stream))))

(defun github-escaped-data (value)
  (github-escaped-string value *github-data-escapes*))

(defparameter *github-property-escapes*
  (github-escape-table (list (cons #\% "%25")
                              (cons #\Return "%0D")
                              (cons #\Newline "%0A")
                              (cons #\: "%3A")
                              (cons #\, "%2C")))
  "Character substitutions for GitHub Actions workflow-command property values.")

(defun github-escaped-property (value)
  (github-escaped-string value *github-property-escapes*))

(defun github-annotatable-event-p (event)
  (member (test-event-status event) '(:fail :error)))

(defun github-event-file (event)
  (getf (test-event-location event) :file))

(defun github-event-message (event)
  (with-output-to-string (stream)
    (format stream "~A [~A]"
            (path-string (test-event-path event))
            (json-status-string (test-event-status event)))
    (let ((detail (event-detail-string event)))
      (when (plusp (length detail))
        (format stream "~%~A" detail)))))

(defun report-github-event (event stream)
  (write-string "::error" stream)
  (let ((file (github-event-file event)))
    (when file
      (format stream " file=~A" (github-escaped-property file))))
  (format stream "::~A~%" (github-escaped-data (github-event-message event))))

(defun report-github-summary (events stream)
  (let ((summary (result-summary events)))
    (format stream "cl-weave: ~D passed, ~D skipped, ~D todo, ~D failed, ~D errored, ~D total~%"
            (getf summary :passed)
            (getf summary :skipped)
            (getf summary :todos)
            (getf summary :failed)
            (getf summary :errored)
            (getf summary :total))))

(defun report-github (events stream)
  (dolist (event events)
    (when (github-annotatable-event-p event)
      (report-github-event event stream)))
  (report-github-summary events stream)
  (values))
