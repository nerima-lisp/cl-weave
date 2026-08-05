(in-package #:cl-weave/cli)

(defmacro define-structured-reporter (command)
  (let ((name (intern (format nil "~A-REPORTER" command) *package*))
        (message (format nil
                         "cl-weave: ~A mode supports json and sexp reporters."
                         (string-downcase command))))
    `(defun ,name (options)
       (let ((reporter (cli-options-reporter options)))
         (cond
           ((eq reporter :spec) :json)
           ((member reporter '(:json :sexp)) reporter)
           (t (error 'cli-error :message ,message)))))))

(define-structured-reporter metadata)
(define-structured-reporter doctor)

(defun doctor-check-status (entry)
  (getf entry :status))

(defun doctor-overall-status (checks)
  (cond
    ((find :fail checks :key #'doctor-check-status) :fail)
    ((find :warn checks :key #'doctor-check-status) :warn)
    (t :pass)))

(defun doctor-check (name status summary)
  (list :name name
        :status status
        :summary summary))

(defmacro doctor-boolean-check (predicate name pass-status fail-status pass-message fail-message)
  (let ((result (gensym "RESULT")))
    `(let ((,result ,predicate))
       (doctor-check ,name
                     (if ,result ,pass-status ,fail-status)
                     (if ,result ,pass-message ,fail-message)))))

(defun doctor-runtime-metadata ()
  (list :lisp-implementation (lisp-implementation-type)
        :lisp-version (lisp-implementation-version)
        :machine-instance (machine-instance)
        :machine-type (machine-type)
        :machine-version (machine-version)
        :software-type (software-type)
        :software-version (software-version)
        :working-directory (uiop:getcwd)))

(defun visible-asdf-system-p (system-name)
  (and system-name
       (not (null (ignore-errors (asdf:find-system system-name nil))))))

(defun doctor-requested-system (options)
  (first (cli-options-systems options)))

(defun doctor-runtime-check ()
  (doctor-check "runtime" :pass
                (format nil "~A ~A on ~A"
                        (lisp-implementation-type)
                        (lisp-implementation-version)
                        (software-type))))

(defun doctor-cl-weave-system-check ()
  (doctor-boolean-check (visible-asdf-system-p "cl-weave")
                        "cl-weave-system"
                        :pass :fail
                        "ASDF can resolve the bundled cl-weave system."
                        "ASDF cannot resolve the bundled cl-weave system."))

(defun doctor-requested-system-check (requested-system)
  (multiple-value-bind (status summary)
      (cond
       ((null requested-system)
        (values :pass
                "No ASDF system was requested; doctor is running in runtime-only mode."))
       ((visible-asdf-system-p requested-system)
        (values :pass
                (format nil "ASDF can resolve the requested system ~A."
                        requested-system)))
       (t
        (values :fail
                (format nil "ASDF cannot resolve the requested system ~A."
                        requested-system))))
    (doctor-check "requested-system" status summary)))

(defun doctor-workspace-asd-files-check (asd-files)
  (doctor-boolean-check asd-files
                        "workspace-asd-files"
                        :pass :warn
                        (format nil "Found ~D .asd file(s) in the current working directory."
                                (length asd-files))
                        "No .asd files were found in the current working directory."))

(defun doctor-output-target-check (output-file)
  (doctor-check "output-target" :pass
                (if output-file
                    (format nil "Doctor output is configured to write to ~A."
                            output-file)
                    "Doctor output is configured to write to standard output.")))

(defun doctor-command-metadata-check (metadata)
  (doctor-boolean-check (member "doctor" (getf metadata :commands) :test #'string=)
                        "command-metadata"
                        :pass :fail
                        "Framework metadata advertises the doctor command."
                        "Framework metadata does not advertise the doctor command."))

(defun doctor-checks (options)
  (let* ((cwd (uiop:getcwd))
         (asd-files (directory-asd-files cwd))
         (metadata (cl-weave/metadata:framework-metadata))
         (requested-system (doctor-requested-system options))
         (output-file (cli-options-output-file options)))
    (list
     (doctor-runtime-check)
     (doctor-cl-weave-system-check)
     (doctor-requested-system-check requested-system)
     (doctor-workspace-asd-files-check asd-files)
     (doctor-output-target-check output-file)
     (doctor-command-metadata-check metadata))))

(defun doctor-report (&optional (options (make-cli-options)))
  (let* ((checks (doctor-checks options))
         (status (doctor-overall-status checks)))
    (list :schema-version 1
          :kind "doctor-report"
          :status (cl-weave/metadata::metadata-symbol-name status)
          :version (cl-weave/metadata::cli-version)
          :runtime (doctor-runtime-metadata)
          :checks
          (loop for entry in checks
                collect (list :name (getf entry :name)
                              :status (cl-weave/metadata::metadata-symbol-name
                                       (getf entry :status))
                              :summary (getf entry :summary))))))
