(in-package #:cl-weave)

(defun report-assertion-detail (detail stream)
  (when detail
    (format stream "~&    form: ~S" (assertion-detail-form detail))
    (when (assertion-detail-matcher detail)
      (format stream "~&    matcher: ~S" (assertion-detail-matcher detail))
      (format stream "~&    actual: ~S" (assertion-detail-actual detail))
      (format stream "~&    expected: ~S" (assertion-detail-expected detail))
      (format stream "~&    negated: ~S" (assertion-detail-negated detail)))))

(defun report-journal-frame (frame stream)
  (format stream "~&      ~A" (journal-frame-line frame)))

(defun report-journal-timeline (frames stream)
  (when frames
    (format stream "~&    timeline (~D frame~:P):" (length frames))
    (dolist (frame frames)
      (report-journal-frame frame stream))))

(defun report-replay-seed (seed stream)
  (when seed
    (format stream "~&    replay seed: ~D (bind *test-random-seed* to reproduce)"
            seed)))

(defun report-spec (events stream)
  (let ((summary (result-summary events)))
    (dolist (event events)
      (format stream "~&[~A] ~A (~,3Fs)"
              (status-marker (test-event-status event))
              (path-string (test-event-path event))
              (event-duration-seconds event))
      (when (test-event-reason event)
        (format stream "~&    reason: ~A" (test-event-reason event)))
      (unless (member (test-event-status event) '(:pass :skip :todo))
        (format stream "~&    condition: ~A" (test-event-condition event))
        (dolist (condition (test-event-secondary-conditions event))
          (format stream "~&    secondary condition: ~A" condition))
        (report-assertion-detail (test-event-assertion event) stream)
        (report-journal-timeline (test-event-journal event) stream)
        (report-replay-seed (test-event-replay-seed event) stream)))
    (format stream "~&~%~D passed, ~D skipped, ~D todo, ~D failed, ~D errored, ~D total~%"
            (getf summary :passed)
            (getf summary :skipped)
            (getf summary :todos)
            (getf summary :failed)
            (getf summary :errored)
            (getf summary :total))
    (values)))

;; The inverse, JOURNAL-FRAME-FROM-PLIST (journal.lisp), rebuilds a frame from
;; this plist; a round-trip test guards the two against key drift. Keep the keys
;; here in sync with that reader.
(defun serializable-journal-frame (frame)
  (list :index (journal-frame-index frame)
        :kind (journal-frame-kind frame)
        :form (journal-frame-form frame)
        :matcher (journal-frame-matcher frame)
        :actual (journal-frame-actual frame)
        :expected (journal-frame-expected frame)
        :pass (journal-frame-pass frame)
        :elapsed-internal-time (journal-frame-elapsed-internal-time frame)))

(defun serializable-event (event)
  (list :status (test-event-status event)
        :path (test-event-path event)
        :path-string (path-string (test-event-path event))
        :location (test-event-location event)
        :seconds (event-duration-seconds event)
        :duration-ms (event-duration-ms event)
        :condition (when (test-event-condition event)
                      (princ-to-string (test-event-condition event)))
        :secondary-conditions
        (mapcar #'princ-to-string (test-event-secondary-conditions event))
        :reason (test-event-reason event)
        :assertion (let ((detail (test-event-assertion event)))
                      (when detail
                        (list :form (assertion-detail-form detail)
                              :matcher (assertion-detail-matcher detail)
                              :actual (assertion-detail-actual detail)
                              :expected (assertion-detail-expected detail)
                              :negated (assertion-detail-negated detail)
                              :pass (assertion-detail-pass detail))))
        :timeline (mapcar #'serializable-journal-frame (test-event-journal event))
        :replay-seed (test-event-replay-seed event)))

(define-sexp-reporter report-sexp (events stream)
  :tag :cl-weave/results
  :schema-version 4
  :summary-fn result-summary
  :payload-key :events
  :serializer-fn serializable-event)

(defun json-write-results-summary-fields (summary stream)
  (json-write-summary-count-fields summary *result-summary-field-specs* stream)
  (write-string ",\"failedPaths\":" stream)
  (json-write-string-list (getf summary :failed-paths) stream)
  (write-string ",\"erroredPaths\":" stream)
  (json-write-string-list (getf summary :errored-paths) stream))

(defun report-json (events stream)
  (let ((summary (result-summary events)))
  (write-string "{" stream)
  (write-string "\"schemaVersion\":6" stream)
  (write-string ",\"kind\":\"test-results\"" stream)
  (json-write-results-summary-fields summary stream)
  (write-string ",\"events\":" stream)
  (json-write-sequence events #'json-write-event stream)
  (write-string "}" stream)
  (terpri stream)
  (values)))

(defun report-jsonl (events stream)
  (let ((summary (result-summary events)))
  (write-string "{\"schemaVersion\":1,\"kind\":\"test-results-start\",\"total\":" stream)
  (princ (getf summary :total) stream)
  (write-string "}" stream)
  (terpri stream)
  (dolist (event events)
    (write-string "{\"schemaVersion\":3,\"kind\":\"test-event\",\"event\":" stream)
    (json-write-event event stream)
    (write-string "}" stream)
    (terpri stream))
  (write-string "{\"schemaVersion\":1,\"kind\":\"test-results-summary\"" stream)
  (json-write-results-summary-fields summary stream)
  (write-string "}" stream)
  (terpri stream)
  (values)))
