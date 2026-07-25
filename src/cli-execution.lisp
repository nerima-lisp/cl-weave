(in-package #:cl-weave/cli)

(defmacro with-cli-snapshot-settings ((options) &body body)
  `(let ((cl-weave:*update-snapshots* (cli-options-update-snapshots ,options))
         (cl-weave:*snapshot-directory*
           (or (cli-options-snapshot-directory ,options)
               cl-weave:*snapshot-directory*))
         (cl-weave:*snapshot-file-name*
           (or (cli-options-snapshot-file ,options)
               cl-weave:*snapshot-file-name*)))
     ,@body))

(defmacro with-cli-journal-settings ((options) &body body)
  "Bind the time-travel toggles from OPTIONS: --journal enables the execution
journal and --random-seed drives deterministic replay. Both ride in the runner's
dynamic environment, so worker threads inherit them."
  `(let ((cl-weave:*journal-enabled*
           (or (cli-options-journal ,options)
               cl-weave:*journal-enabled*))
         (cl-weave:*test-random-seed*
           (or (cli-options-random-seed ,options)
               cl-weave:*test-random-seed*)))
     ,@body))

(defun command-dispatch-kind (options)
  (cond
    ((eq (cli-options-command options) :doctor) :doctor)
    ((eq (cli-options-command options) :metadata) :metadata)
    ((cli-options-list options) :list)
    ((cli-options-watch options) :watch)
    (t :run)))

(defun ensure-valid-reporter-for-command (options)
  (case (command-dispatch-kind options)
    (:doctor
     (doctor-reporter options)
     t)
    (:metadata
     (metadata-reporter options)
     t)
    (:list
     (unless (member (cli-options-reporter options)
                     (cl-weave:list-reporters))
       (error 'cli-error
              :message "cl-weave: list mode supports spec, sexp, json, and jsonl reporters."))
     t)
    ((:run :watch)
     (handler-case
         (progn
           (cl-weave::ensure-run-reporter (cli-options-reporter options))
           t)
       (error (condition)
         (error 'cli-error :message (princ-to-string condition)))))))

(defun ensure-watch-command-system (options)
  (when (eq (command-dispatch-kind options) :watch)
    (cond
      ((null (cli-options-systems options))
       (error 'cli-error
              :message "Watch mode requires SYSTEM as a positional argument or --system SYSTEM."))
      ((rest (cli-options-systems options))
       (error 'cli-error
              :message "Watch mode accepts exactly one SYSTEM target.")))))

(defun pathname-asd-file-p (pathname)
  (let ((type (pathname-type pathname)))
    (and type (string-equal type "asd"))))

(defun pathname-directory-pathname (pathname)
  (uiop:pathname-directory-pathname (uiop:ensure-pathname pathname)))

(defun load-file-asd-directory (pathname)
  (let ((resolved (uiop:ensure-pathname pathname)))
    (pathname-directory-pathname
     (if (pathname-asd-file-p resolved)
         resolved
         (or (probe-file resolved) resolved)))))

(defun system-bootstrap-directories (options)
  (remove-duplicates
   (cons (uiop:getcwd)
         (loop for file in (cli-options-load-files options)
               collect (load-file-asd-directory file)))
   :test #'equal))

(defun directory-asd-files (directory)
  (sort (copy-list (directory (merge-pathnames "*.asd" directory)))
        #'string<
        :key #'namestring))

(defun system-bootstrap-asd-files (system options)
  (let ((asd-name (format nil "~A.asd" (asdf:primary-system-name system))))
    (remove-duplicates
      (loop for directory in (system-bootstrap-directories options)
            for pathname = (merge-pathnames asd-name directory)
            when (uiop:file-exists-p pathname)
              collect pathname)
      :test
      #'equal)))

(defun ensure-requested-system-visible (system options)
  (unless (asdf:find-system system nil)
    (loop for pathname in (system-bootstrap-asd-files system options)
          until (asdf:find-system system nil)
          do (asdf:load-asd pathname)))
  (unless (asdf:find-system system nil)
    (error
      'cli-error
      :message
      (format
        nil
        "Unable to locate ASDF system ~S. Run cl-weave from the project root, pass --load path/to/system.asd, or configure CL_SOURCE_REGISTRY."
        system))))

(defun load-requested-inputs (options)
  (let ((asd-files (quote ()))
        (source-files (quote ())))
    (dolist (file (cli-options-load-files options))
      (if (pathname-asd-file-p (uiop:ensure-pathname file))
          (push file asd-files)
          (push file source-files)))
    (dolist (file (nreverse asd-files))
      (asdf:load-asd file))
    (when (cli-options-coverage options)
      (dolist (system (cli-options-coverage-systems options))
        (ensure-requested-system-visible system options)
        (asdf:load-system system :force t)))
    (dolist (system (cli-options-systems options))
      (unless (and
               (cli-options-coverage options)
               (member
                system
                (cli-options-coverage-systems options)
                :test
                (function string=)))
        (ensure-requested-system-visible system options)
        (if (cli-options-coverage options)
            (asdf:load-system system :force t)
            (asdf:load-system system))))
    (dolist (file (nreverse source-files))
      (load file))))

(defun prepare-coverage-compilation (options)
  (when (cli-options-coverage options)
    (cl-weave::require-coverage-support)
    (let ((policy (find-symbol "STORE-COVERAGE-DATA" "SB-COVER")))
      (unless policy
        (error 'cli-error :message "SB-COVER compiler policy is not available."))
      (proclaim `(optimize (,policy 3))))))

(defun call-with-output-stream (options callback)
  (let ((output-file (cli-options-output-file options)))
    (if output-file
        (with-open-file (stream output-file
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (funcall callback stream))
        (funcall callback *standard-output*))))

(defun shared-execution-argument-pairs (options)
  (list :reporter (cli-options-reporter options)
        :name-filter (cli-options-name-filter options)
        :shard (cli-options-shard options)
        :order (cli-options-order options)
        :seed (cli-options-seed options)))

(defun run-execution-argument-pairs (options)
  (let ((system-pathnames
          (loop for system in (cli-options-coverage-systems options)
                do (ensure-requested-system-visible system options)
                append (cl-weave::asdf-system-files system))))
  (append (shared-execution-argument-pairs options)
          (list :bail (cli-options-bail options)
                :coverage (cli-options-coverage options)
                :coverage-output (cli-options-coverage-output options)
                :coverage-report-directory
                (cli-options-coverage-report-directory options)
                :coverage-include-pathnames
                (append system-pathnames
                        (cli-options-coverage-include-pathnames options))
                :coverage-exclude-pathnames
                (cli-options-coverage-exclude-pathnames options)
                :coverage-minimum-expression
                (cli-options-coverage-minimum-expression options)
                :coverage-minimum-branch
                (cli-options-coverage-minimum-branch options)
                :pass-with-no-tests (cli-options-pass-with-no-tests options)
                :retry (cli-options-retry options)
                :timeout-ms (cli-options-test-timeout-ms options)
                :max-workers (cli-options-max-workers options)))))

(defun call-list-command (options stream)
  (apply #'cl-weave:list-tests
         (append (shared-execution-argument-pairs options)
                 (list :retry (cli-options-retry options)
                       :timeout-ms (cli-options-test-timeout-ms options)
                       :stream stream))))

(defun call-run-command (options stream)
  (apply #'cl-weave:run-all
         (append (run-execution-argument-pairs options)
                 (list :stream stream))))

(defun watch-command-call-arguments (options)
  (values
   (first (cli-options-systems options))
   (append (run-execution-argument-pairs options)
           (list :include-dependencies t
                 :once (cli-options-watch-once options)
                 :interval (cli-options-watch-interval options)))))

(defun command-execution-plan (options)
  (case (command-dispatch-kind options)
    (:doctor
     (list :kind :doctor))
    (:metadata
     (list :kind :metadata))
    (:list
     (list :kind :list))
    (:watch
     (multiple-value-bind (system arguments)
         (watch-command-call-arguments options)
       (list :kind :watch
             :system system
             :arguments arguments)))
    (:run
     (list :kind :run))))

(defun command-plan-stream-callback (plan options)
  (case (getf plan :kind)
    (:doctor
     (lambda (stream)
       (report-doctor options stream)))
    (:metadata
     (lambda (stream)
       (report-framework-metadata options stream)))
    (:list
     (lambda (stream)
       (call-list-command options stream)))
    (:watch
     (let ((system (getf plan :system))
           (arguments (getf plan :arguments)))
       (lambda (stream)
         (apply #'cl-weave:watch-system
                system
                (append arguments
                        (list :stream stream
                              :status-stream *error-output*))))))
    (:run
     (lambda (stream)
       (call-run-command options stream)))))

(defun command-plan-success-kind-p (plan)
  (member (getf plan :kind) '(:doctor :metadata :list) :test #'eq))

(defun execute-command-plan (plan options)
  (let ((result
          (call-with-output-stream
           options
           (command-plan-stream-callback plan options))))
    (if (command-plan-success-kind-p plan)
        t
        result)))

(defun run-command (options)
  (ensure-valid-reporter-for-command options)
  (ensure-watch-command-system options)
  (unless (eq (command-dispatch-kind options) :doctor)
    (prepare-coverage-compilation options)
    (load-requested-inputs options))
  (with-cli-snapshot-settings (options)
    (with-cli-journal-settings (options)
      (execute-command-plan (command-execution-plan options) options))))

#+sbcl
(defun process-arguments ()
  (let ((argv (rest sb-ext:*posix-argv*)))
    (if (and argv (string= (first argv) "--"))
        (rest argv)
        argv)))

#-sbcl
(defun process-arguments ()
  (error 'cli-error :message "cl-weave CLI currently requires SBCL."))

#+sbcl
(defun exit-process (code)
  (sb-ext:exit :code code))

#-sbcl
(defun exit-process (code)
  (uiop:quit code))

(defun main (&optional (argv (process-arguments)))
  (handler-case
      (let ((options (parse-cli-arguments argv)))
        (cond
          ((cli-options-version options)
           (format *standard-output* "cl-weave ~A~%" (cli-version))
           (exit-process 0))
          ((cli-options-help options)
           (write-string (cli-usage) *standard-output*)
           (exit-process 0))
          ((run-command options)
           (exit-process 0))
          (t
           (exit-process 1))))
    (cli-error (condition)
      (format *error-output* "cl-weave: ~A~%~%~A" condition (cli-usage))
      (exit-process 2))))
