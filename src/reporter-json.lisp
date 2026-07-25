(in-package #:cl-weave)

(defun json-escaped-string (value)
  (with-output-to-string (stream)
    (loop for char across (princ-to-string value)
          for code = (char-code char)
          do (case code
               (34 (write-string "\\\"" stream))
               (92 (write-string "\\\\" stream))
               (47 (write-string "\\/" stream))
               (8 (write-string "\\b" stream))
               (9 (write-string "\\t" stream))
               (10 (write-string "\\n" stream))
               (12 (write-string "\\f" stream))
               (13 (write-string "\\r" stream))
               (t
                (if (< code 32)
                    (format stream "\\u~4,'0X" code)
                    (write-char char stream)))))))

(defun write-json-string (value stream)
  (format stream "\"~A\"" (json-escaped-string value)))

(defun json-status-string (status)
  (string-downcase (symbol-name status)))

(defun json-write-path (path stream)
  (json-write-string-list path stream))

(defun json-write-sequence (values writer stream)
  (write-char #\[ stream)
  (let ((first t))
    (map nil
         (lambda (value)
           (unless first
             (write-char #\, stream))
           (setf first nil)
           (funcall writer value stream))
         values))
  (write-char #\] stream))

(defun json-write-string-list (values stream)
  (json-write-sequence values #'write-json-string stream))

(defun event-path-strings-with-status (events status)
  (loop for event in events
        when (eq (test-event-status event) status)
          collect (path-string (test-event-path event))))

(defun json-write-summary-count-fields (summary field-specs stream)
  (loop for spec in field-specs
        do (format stream ",\"~A\":~D"
                   (getf spec :json-key)
                   (getf summary (getf spec :plist-key)))))

(defun json-write-nullable-string (value stream)
  (if value
      (write-json-string value stream)
      (write-string "null" stream)))

(defun json-write-printed-value (value stream)
  (let ((*print-circle* t)
        (*print-readably* nil))
    (write-json-string (prin1-to-string value) stream)))

(defvar *json-active-values* nil)

(defun call-with-json-composite (value stream writer)
  (if (gethash value *json-active-values*)
      (json-write-printed-value value stream)
      (unwind-protect
           (progn
             (setf (gethash value *json-active-values*) t)
             (funcall writer))
        (remhash value *json-active-values*))))

(defun proper-list-p (value)
  (loop with tortoise = value
        with hare = value
        do (cond
             ((null hare) (return t))
             ((atom hare) (return nil)))
           (setf hare (cdr hare))
           (cond
             ((null hare) (return t))
             ((atom hare) (return nil)))
           (setf hare (cdr hare)
                 tortoise (cdr tortoise))
           (when (eq tortoise hare)
             (return nil))))

(defun keyword-json-key (symbol)
  (let* ((source (string-downcase (symbol-name symbol)))
         (parts '())
         (start 0))
    (loop for position = (position #\- source :start start)
          do (if position
                 (progn
                   (push (subseq source start position) parts)
                   (setf start (1+ position)))
                 (progn
                   (push (subseq source start) parts)
                   (return))))
    (let ((ordered (nreverse parts)))
      (with-output-to-string (stream)
        (when ordered
          (write-string (first ordered) stream)
          (dolist (part (rest ordered))
            (when (plusp (length part))
              (write-char (char-upcase (char part 0)) stream)
              (write-string (subseq part 1) stream))))))))

(defun json-object-key-string (key)
  (typecase key
    (keyword (keyword-json-key key))
    (string key)
    (symbol (string-downcase (symbol-name key)))
    (t (princ-to-string key))))

(defun json-plist-p (value)
  (and (proper-list-p value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             always (keywordp (car tail)))))

(defun json-alist-p (value)
  ;; A JSON object is written from an association list of *dotted* pairs
  ;; (KEY . VALUE). Requiring `(atom (cdr entry))` is what distinguishes a
  ;; genuine alist from a list of plists such as the operand reports
  ;; ((:form A :value 1) (:form B :value 2)): the latter's entries are proper
  ;; lists (cdr is a cons), so they render as a JSON array of objects rather
  ;; than collapsing into one object with duplicate keys.
  (and (proper-list-p value)
       (every (lambda (entry)
                (and (consp entry)
                     (atom (cdr entry))
                     (let ((key (car entry)))
                       (or (keywordp key)
                           (stringp key)
                           (symbolp key)))))
              value)))

(declaim (notinline json-write-value json-write-vector json-write-cons))

(defun json-write-array (values stream)
  (json-write-sequence values #'json-write-value stream))

(defun json-write-object (pairs stream)
  (write-char #\{ stream)
  (loop for (key . value) in pairs
        for first = t then nil
        do (progn
             (unless first
               (write-string "," stream))
             (write-json-string (json-object-key-string key) stream)
             (write-char #\: stream)
             (json-write-value value stream)))
  (write-char #\} stream))

(defun json-write-vector (value stream)
  (call-with-json-composite
   value stream (lambda () (json-write-array value stream))))

(defun json-write-cons (value stream)
  (call-with-json-composite
   value stream
   (lambda ()
     (cond
       ((json-plist-p value)
        (json-write-object
         (loop for (key val) on value by #'cddr
               collect (cons key val))
         stream))
       ((json-alist-p value)
        (json-write-object value stream))
       ((proper-list-p value)
        (json-write-array value stream))
       (t
        (json-write-printed-value value stream))))))

(defun json-write-value (value stream)
  (let ((*json-active-values*
          (or *json-active-values* (make-hash-table :test #'eq))))
    (cond
      ((null value) (write-string "null" stream))
      ((eq value t) (write-string "true" stream))
      ((stringp value) (write-json-string value stream))
      ((characterp value) (write-json-string (string value) stream))
      ((integerp value) (princ value stream))
      ((numberp value) (json-write-printed-value value stream))
      ((pathnamep value) (write-json-string (namestring value) stream))
      ((keywordp value)
       (write-json-string (string-downcase (symbol-name value)) stream))
      ((vectorp value) (json-write-vector value stream))
      ((consp value) (json-write-cons value stream))
      ((symbolp value) (write-json-string (princ-to-string value) stream))
      (t (json-write-printed-value value stream)))))

(defun json-write-assertion (detail stream)
  (if detail
      (progn
        (write-string "{" stream)
        (write-string "\"form\":" stream)
        (json-write-printed-value (assertion-detail-form detail) stream)
        (write-string ",\"matcher\":" stream)
        (json-write-printed-value (assertion-detail-matcher detail) stream)
        (write-string ",\"actual\":" stream)
        (json-write-value (assertion-detail-actual detail) stream)
        (write-string ",\"expected\":" stream)
        (json-write-value (assertion-detail-expected detail) stream)
        (write-string ",\"negated\":" stream)
        (write-string (if (assertion-detail-negated detail) "true" "false") stream)
        (write-string ",\"pass\":" stream)
        (write-string (if (assertion-detail-pass detail) "true" "false") stream)
        (write-string "}" stream))
      (write-string "null" stream)))

(defun json-write-journal-frame (frame stream)
  (write-string "{\"index\":" stream)
  (princ (journal-frame-index frame) stream)
  (write-string ",\"kind\":" stream)
  (write-json-string (string-downcase (symbol-name (journal-frame-kind frame)))
                     stream)
  (write-string ",\"form\":" stream)
  (json-write-printed-value (journal-frame-form frame) stream)
  (write-string ",\"matcher\":" stream)
  (json-write-printed-value (journal-frame-matcher frame) stream)
  (write-string ",\"actual\":" stream)
  (json-write-value (journal-frame-actual frame) stream)
  (write-string ",\"expected\":" stream)
  (json-write-value (journal-frame-expected frame) stream)
  (write-string ",\"pass\":" stream)
  (write-string (if (journal-frame-pass frame) "true" "false") stream)
  (write-string ",\"elapsedInternalTime\":" stream)
  (princ (journal-frame-elapsed-internal-time frame) stream)
  (write-string "}" stream))

(defun json-write-journal (frames stream)
  (json-write-sequence frames #'json-write-journal-frame stream))

(defun json-write-location (location stream)
  (let ((file (and location (getf location :file))))
    (if file
        (progn
          (write-string "{\"file\":" stream)
          (write-json-string file stream)
          (write-string "}" stream))
        (write-string "null" stream))))

(defun json-write-event (event stream)
  (write-string "{" stream)
  (write-string "\"status\":" stream)
  (write-json-string (json-status-string (test-event-status event)) stream)
  (write-string ",\"path\":" stream)
  (json-write-path (test-event-path event) stream)
  (write-string ",\"pathString\":" stream)
  (write-json-string (path-string (test-event-path event)) stream)
  (write-string ",\"location\":" stream)
  (json-write-location (test-event-location event) stream)
  (format stream ",\"seconds\":~,6F" (event-duration-seconds event))
  (format stream ",\"durationMs\":~,3F" (event-duration-ms event))
  (write-string ",\"condition\":" stream)
  (json-write-nullable-string
   (when (test-event-condition event)
     (princ-to-string (test-event-condition event)))
   stream)
  (write-string ",\"secondaryConditions\":" stream)
  (json-write-sequence
   (test-event-secondary-conditions event)
   (lambda (condition output)
     (write-json-string (princ-to-string condition) output))
   stream)
  (write-string ",\"reason\":" stream)
  (json-write-nullable-string (test-event-reason event) stream)
  (write-string ",\"assertion\":" stream)
  (json-write-assertion (test-event-assertion event) stream)
  (write-string ",\"timeline\":" stream)
  (json-write-journal (test-event-journal event) stream)
  (write-string ",\"replaySeed\":" stream)
  (let ((seed (test-event-replay-seed event)))
    (if seed
        (princ seed stream)
        (write-string "null" stream)))
  (write-string "}" stream))
