(in-package #:cl-weave)

(defparameter *tap-non-diagnostic-statuses*
  (let ((table (make-hash-table :test (quote eq))))
    (dolist (status (quote (:pass :skip :todo)) table)
      (setf (gethash status table) t))))

(defparameter *tap-assertion-field-specs*
  (list (cons "form" (function assertion-detail-form))
        (cons "matcher" (function assertion-detail-matcher))
        (cons "actual" (function assertion-detail-actual))
        (cons "expected" (function assertion-detail-expected))))

(defun tap-line-string (value)
  (with-output-to-string (stream)
    (loop for char across (princ-to-string value)
          do (case char
               ((#\Newline #\Return #\Tab) (write-char #\Space stream))
               (t (write-char char stream))))))

(defun tap-quoted-string (value)
  (format nil "\"~A\"" (json-escaped-string (tap-line-string value))))

(defun tap-directive (event)
  (let ((reason (test-event-reason event)))
    (ecase (test-event-status event)
      (:skip (format nil " # SKIP~@[ ~A~]" (when reason (tap-line-string reason))))
      (:todo (format nil " # TODO~@[ ~A~]" (when reason (tap-line-string reason))))
      ((:pass :fail :error) ""))))

(defun report-tap-assertion-field (detail field-spec stream)
  (format stream "    ~A: ~A~%"
          (car field-spec)
          (tap-quoted-string (prin1-to-string (funcall (cdr field-spec) detail)))))

(defun report-tap-assertion (detail stream)
  (when detail
    (format stream "  assertion:~%")
    (dolist (field-spec *tap-assertion-field-specs*)
      (report-tap-assertion-field detail field-spec stream))
    (format stream "    negated: ~:[false~;true~]~%"
            (assertion-detail-negated detail))))

(defun report-tap-diagnostics (event stream)
  (unless (gethash (test-event-status event) *tap-non-diagnostic-statuses*)
    (format stream "  ---~%")
    (format stream "  status: ~A~%"
            (tap-quoted-string (json-status-string (test-event-status event))))
    (when (test-event-condition event)
      (format stream "  condition: ~A~%"
              (tap-quoted-string (princ-to-string (test-event-condition event)))))
    (dolist (condition (test-event-secondary-conditions event))
      (format stream "  secondary condition: ~A~%"
              (tap-quoted-string (princ-to-string condition))))
    (report-tap-assertion (test-event-assertion event) stream)
    (format stream "  ...~%")))

(defun report-tap (events stream)
  (format stream "TAP version 13~%")
  (format stream "1..~D~%" (length events))
  (loop for event in events
        for index from 1
        for status = (test-event-status event)
        do (progn
             (format stream "~:[not ok~;ok~] ~D - ~A~A~%"
                     (gethash status *tap-non-diagnostic-statuses*)
                     index
                     (tap-line-string (path-string (test-event-path event)))
                     (tap-directive event))
             (report-tap-diagnostics event stream)))
  (values))
