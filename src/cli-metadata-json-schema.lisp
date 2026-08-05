(in-package #:cl-weave/metadata)

(defmacro define-json-plist-array-writer (name fields)
  `(defun ,name (entries stream)
     (write-json-plist-array entries ,fields stream)))

(defmacro define-json-plist-object-writer (name fields)
  `(defun ,name (entry stream)
     (write-json-plist-object entry ,fields stream)))

(defmacro define-json-plist-array-schema (fields-name writer-name fields)
  `(progn
     (defparameter ,fields-name ,fields)
     (define-json-plist-array-writer ,writer-name ,fields-name)))

(defmacro define-json-plist-object-schema (fields-name writer-name fields)
  `(progn
     (defparameter ,fields-name ,fields)
     (define-json-plist-object-writer ,writer-name ,fields-name)))

(defmacro define-json-plist-field-writer (name record)
  `(defun ,name (field ,record stream)
     (destructuring-bind (record-key json-key writer) field
       (write-json-key json-key stream)
       (funcall writer (getf ,record record-key) stream))))

(defmacro define-json-plist-object-emitter (name fields field-writer)
  `(defun ,name (record stream)
     (write-char #\{ stream)
     (loop for field in ,fields
           for firstp = t then nil
           unless firstp do (write-char #\, stream)
           do (,field-writer field record stream))
     (write-char #\} stream)
     (terpri stream)))

(defmacro define-json-plist-object-endpoint (fields-name writer-name emitter-name
                                             record-name fields)
  `(progn
     (defparameter ,fields-name ,fields)
     (define-json-plist-field-writer ,writer-name ,record-name)
     (define-json-plist-object-emitter ,emitter-name ,fields-name ,writer-name)))
