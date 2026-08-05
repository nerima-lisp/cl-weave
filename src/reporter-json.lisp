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

(defun json-write-boolean (value stream)
  "Write VALUE to STREAM as the JSON literal true or false."
  (write-string (if value "true" "false") stream))

(defun json-write-nullable-integer (value stream)
  "Write VALUE to STREAM as a JSON number, or the JSON literal null when
VALUE is NIL."
  (if value
      (princ value stream)
      (write-string "null" stream)))

(defmacro json-write-fields (stream &body fields)
  "Write a JSON object literal to a stream. Each entry in FIELDS is
(KEY-STRING VALUE-FORM): KEY-STRING is the JSON key, and VALUE-FORM is
a form evaluated for its side effect of writing exactly one JSON value
to STREAM. STREAM is evaluated exactly once (bound to a fresh
variable), but VALUE-FORM must still reference the original STREAM
symbol as written at the call site, since it runs in the caller lexical
scope where that symbol names the same underlying stream object."
  (let ((stream-var (gensym "STREAM")))
    `(let ((,stream-var ,stream))
       (write-char #\{ ,stream-var)
       ,@(loop for (key value-form) in fields
               for firstp = t then nil
               append (if firstp
                          (list `(write-json-string ,key ,stream-var)
                                `(write-char #\: ,stream-var)
                                value-form)
                          (list `(write-char #\, ,stream-var)
                                `(write-json-string ,key ,stream-var)
                                `(write-char #\: ,stream-var)
                                value-form)))
       (write-char #\} ,stream-var))))

(defun json-write-assertion (detail stream)
  (if detail
      (json-write-fields stream
        ("form" (json-write-printed-value (assertion-detail-form detail) stream))
        ("matcher" (json-write-printed-value (assertion-detail-matcher detail) stream))
        ("actual" (json-write-value (assertion-detail-actual detail) stream))
        ("expected" (json-write-value (assertion-detail-expected detail) stream))
        ("negated" (json-write-boolean (assertion-detail-negated detail) stream))
        ("pass" (json-write-boolean (assertion-detail-pass detail) stream)))
      (write-string "null" stream)))

(defun json-write-journal-frame (frame stream)
  (json-write-fields stream
    ("index" (princ (journal-frame-index frame) stream))
    ("kind" (write-json-string
             (string-downcase (symbol-name (journal-frame-kind frame)))
             stream))
    ("form" (json-write-printed-value (journal-frame-form frame) stream))
    ("matcher" (json-write-printed-value (journal-frame-matcher frame) stream))
    ("actual" (json-write-value (journal-frame-actual frame) stream))
    ("expected" (json-write-value (journal-frame-expected frame) stream))
    ("pass" (json-write-boolean (journal-frame-pass frame) stream))
    ("elapsedInternalTime"
     (princ (journal-frame-elapsed-internal-time frame) stream))))

(defun json-write-journal (frames stream)
  (json-write-sequence frames #'json-write-journal-frame stream))

(defun json-write-location (location stream)
  (let ((file (and location (getf location :file))))
    (if file
        (json-write-fields stream
          ("file" (write-json-string file stream)))
        (write-string "null" stream))))

(defun json-write-event (event stream)
  (json-write-fields stream
    ("status" (write-json-string (json-status-string (test-event-status event)) stream))
    ("path" (json-write-path (test-event-path event) stream))
    ("pathString" (write-json-string (path-string (test-event-path event)) stream))
    ("location" (json-write-location (test-event-location event) stream))
    ("seconds" (format stream "~,6F" (event-duration-seconds event)))
    ("durationMs" (format stream "~,3F" (event-duration-ms event)))
    ("condition"
     (json-write-nullable-string
      (when (test-event-condition event)
        (princ-to-string (test-event-condition event)))
      stream))
    ("secondaryConditions"
     (json-write-sequence
      (test-event-secondary-conditions event)
      (lambda (condition output)
        (write-json-string (princ-to-string condition) output))
      stream))
    ("reason" (json-write-nullable-string (test-event-reason event) stream))
    ("assertion" (json-write-assertion (test-event-assertion event) stream))
    ("timeline" (json-write-journal (test-event-journal event) stream))
    ("replaySeed" (json-write-nullable-integer (test-event-replay-seed event) stream))))
