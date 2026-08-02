(in-package #:cl-weave)

(defvar *reporter-artifact-schemas*)

(defun event-duration-seconds (event)
  (/ (test-event-elapsed-internal-time event)
     internal-time-units-per-second))

(defun event-duration-ms (event)
  (* (event-duration-seconds event) 1000))

(defun status-marker (status)
  (ecase status
    (:pass "PASS")
    (:skip "SKIP")
    (:todo "TODO")
    (:fail "FAIL")
    (:error "ERROR")))

(defun path-string (path)
  (format nil "~{~A~^ > ~}" path))

(defun dotted-path-string (path)
  (if path
      (format nil "~{~A~^.~}" path)
      "cl-weave"))

(defun xml-escaped-string (value)
  (with-output-to-string (stream)
    (loop for char across (princ-to-string value)
          for code = (char-code char)
          do (case code
               (60 (write-string "&lt;" stream))
               (62 (write-string "&gt;" stream))
               (38 (write-string "&amp;" stream))
               (34 (write-string "&quot;" stream))
               (39 (write-string "&apos;" stream))
               (t
                (if (or (member code '(9 10 13))
                        (<= #x20 code #xd7ff)
                        (<= #xe000 code #xfffd)
                        (<= #x10000 code #x10ffff))
                    (write-char char stream)
                    (write-char #\? stream)))))))

(defparameter *result-summary-field-specs*
  '((:status :pass :plist-key :passed :json-key "passed")
    (:status :skip :plist-key :skipped :json-key "skipped")
    (:status :todo :plist-key :todos :json-key "todos")
    (:status :fail :plist-key :failed :json-key "failed")
    (:status :error :plist-key :errored :json-key "errored")))

(defparameter *plan-summary-field-specs*
  '((:status :run :plist-key :runnable :json-key "runnable")
    (:status :skip :plist-key :skipped :json-key "skipped")
    (:status :todo :plist-key :todos :json-key "todos")))

(defmacro define-reporter-artifact-schemas (&body schemas)
  "Define reporter schema data after validating its declarative contract."
  (labels ((property-present-p (plist property)
             (loop for (key) on plist by #'cddr
                   thereis (eq key property)))
           (require-property (plist property context)
             (unless (property-present-p plist property)
               (error "~A must declare ~S." context property))
             (getf plist property))
           (ensure-unique (values context)
             (let ((seen (make-hash-table :test #'equal)))
               (dolist (value values)
                 (when (gethash value seen)
                   (error "~A contains duplicate ~S." context value))
                 (setf (gethash value seen) t)))))
    (ensure-unique (mapcar (lambda (schema)
                             (require-property schema :kind "Reporter schema"))
                           schemas)
                   "Reporter schema kinds")
    (dolist (schema schemas)
      (let ((kind (getf schema :kind)))
        (dolist (property '(:commands :reporters :schema-version
                            :streaming :fields))
          (require-property schema property
                            (format nil "Reporter schema ~S" kind)))
        (let ((fields (getf schema :fields)))
          (ensure-unique
           (mapcar (lambda (field)
                     (require-property field :name
                                       (format nil "Field in schema ~S" kind)))
                   fields)
           (format nil "Field names in reporter schema ~S" kind))
          (dolist (field fields)
            (require-property field :kind
                              (format nil "Field ~S in schema ~S"
                                      (getf field :name) kind))
            (require-property field :required
                              (format nil "Field ~S in schema ~S"
                                      (getf field :name) kind)))))))
  `(defparameter *reporter-artifact-schemas* ',schemas))

(defun reporter-artifact-schemas ()
  "Return structured reporter artifact schema metadata."
  (copy-tree *reporter-artifact-schemas*))

(defun result-summary (events)
  (let ((total 0)
        (passed 0)
        (skipped 0)
        (todos 0)
        (failed 0)
        (errored 0)
        (failed-paths nil)
        (failed-paths-tail nil)
        (errored-paths nil)
        (errored-paths-tail nil))
    (dolist (event events)
      (incf total)
      (case (test-event-status event)
        (:pass (incf passed))
        (:skip (incf skipped))
        (:todo (incf todos))
        (:fail
         (incf failed)
         (let ((path (list (path-string (test-event-path event)))))
           (if failed-paths-tail
               (setf (cdr failed-paths-tail) path
                     failed-paths-tail path)
               (setf failed-paths path
                     failed-paths-tail path))))
        (:error
         (incf errored)
         (let ((path (list (path-string (test-event-path event)))))
           (if errored-paths-tail
               (setf (cdr errored-paths-tail) path
                     errored-paths-tail path)
               (setf errored-paths path
                     errored-paths-tail path))))))
    (list :total total
          :passed passed
          :skipped skipped
          :todos todos
          :failed failed
          :errored errored
          :failed-paths failed-paths
          :errored-paths errored-paths)))

(defun plan-summary (plan)
  (let ((total 0)
        (runnable 0)
        (skipped 0)
        (todos 0))
    (dolist (entry plan)
      (incf total)
      (case (test-plan-entry-status entry)
        (:run (incf runnable))
        (:skip (incf skipped))
        (:todo (incf todos))))
    (list :total total
          :runnable runnable
          :skipped skipped
          :todos todos)))

(defmacro define-sexp-reporter
    (name (collection stream) &key tag schema-version summary-fn payload-key
                                    serializer-fn)
  "Define NAME as a function of (COLLECTION STREAM) that prints an
S-expression artifact (TAG :SCHEMA-VERSION SCHEMA-VERSION ...summary...
PAYLOAD-KEY (serialized elements)) to STREAM, where the summary plist
comes from SUMMARY-FN and each element is serialized by SERIALIZER-FN."
  `(defun ,name (,collection ,stream)
     ;; *print-circle* keeps the serializer from hanging on a circular value in
     ;; a journaled/asserted slot (matching the cycle-safe JSON reporter) while
     ;; still emitting a READ-able form via #N= labels.
     (let ((*print-pretty* nil)
           (*print-circle* t)
           (summary (,summary-fn ,collection)))
       (prin1 (append (list ,tag :schema-version ,schema-version)
                      summary
                      (list ,payload-key (mapcar #',serializer-fn ,collection)))
              ,stream))
     (terpri ,stream)
     (values)))
