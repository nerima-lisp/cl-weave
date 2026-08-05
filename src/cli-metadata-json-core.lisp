(in-package #:cl-weave/metadata)

(defun metadata-symbol-name (symbol)
  (string-downcase (symbol-name symbol)))

(defun write-json-key (key stream)
  (cl-weave::write-json-string key stream)
  (write-char #\: stream))

(defun write-json-number (value stream)
  (write value :stream stream))

(defun write-json-string-value (value stream)
  (cl-weave::write-json-string value stream))

(defun write-json-boolean (value stream)
  (write-string (if value "true" "false") stream))

(defun write-json-array (values element-writer stream)
  (write-char #\[ stream)
  (loop for value in values
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (funcall element-writer value stream))
  (write-char #\] stream))

(defun write-json-object-fields (fields stream)
  (write-char #\{ stream)
  (loop for field in fields
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (destructuring-bind (key writer) field
             (write-json-key key stream)
             (funcall writer stream)))
  (write-char #\} stream))

(defmacro json-field (key value-form writer stream)
  `(list ,key
         (lambda (,stream)
           (,writer ,value-form ,stream))))

(defun call-json-helper (helper value stream)
  (funcall (etypecase helper
             (function helper)
             (symbol (symbol-function helper)))
           value
           stream))

(defun transform-json-value (transformer value)
  (if transformer
      (funcall (etypecase transformer
                 (function transformer)
                 (symbol (symbol-function transformer)))
               value)
      value))

(defun plist-json-field-entry (plist field-spec)
  (destructuring-bind (plist-key json-key writer &optional transformer) field-spec
    (let ((value (transform-json-value transformer (getf plist plist-key))))
      (list json-key
            (lambda (stream)
              (call-json-helper writer value stream))))))

(defun write-json-plist-object (plist field-specs stream)
  (write-json-object-fields
   (mapcar (lambda (field-spec)
             (plist-json-field-entry plist field-spec))
           field-specs)
   stream))

(defun write-json-plist-array (values field-specs stream)
  (write-json-array
   values
   (lambda (value item-stream)
     (write-json-plist-object value field-specs item-stream))
   stream))

(defun write-json-string-list (values stream)
  (write-json-array values #'write-json-string-value stream))

(defun write-json-nullable-string (value stream)
  (if value
      (cl-weave::write-json-string value stream)
      (write-string "null" stream)))

(defun write-json-command-choices (command-choices stream)
  (write-json-array
   command-choices
   (lambda (entry item-stream)
     (destructuring-bind (command choices) entry
       (write-json-object-fields
        (list (json-field "command" command write-json-string-value item-stream)
              (json-field "choices" choices write-json-string-list item-stream))
        item-stream)))
   stream))
