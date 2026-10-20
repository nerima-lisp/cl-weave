(in-package #:cl-weave/cli)

(eval-when
  (:compile-toplevel :load-toplevel :execute)
  (defvar *run-coverage-context* nil)
  (defstruct run-coverage-context
    run-options
    around-input-loading
    around-coverage-consumer
    callback-condition)
  (define-condition cli-callback-failure (error)
    ((condition :initarg :condition :reader cli-callback-failure-condition))))

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
        "Unable to locate ASDF system ~S. Run cl-weave from the project root, ~
         pass --load path/to/system.asd, or configure CL_SOURCE_REGISTRY."
        system))))

(defun partition-cli-load-files (options)
  "Split OPTIONS's --load files into ASD files and plain Lisp source files,
each in its original relative order."
  (let ((asd-files (quote ()))
        (source-files (quote ())))
    (dolist (file (cli-options-load-files options))
      (if (pathname-asd-file-p (uiop:ensure-pathname file))
          (push file asd-files)
          (push file source-files)))
    (values (nreverse asd-files) (nreverse source-files))))

(defun load-cli-asd-files (asd-files)
  (dolist (file asd-files)
    (asdf:load-asd file)))

(defun load-cli-coverage-systems (options)
  (when (cli-options-coverage options)
    (dolist (system (cli-options-coverage-systems options))
      (ensure-requested-system-visible system options)
      (asdf:load-system system :force t))))

(defun load-cli-requested-systems (options)
  "Load OPTIONS's requested systems, forcing a recompile under coverage. A
system already force-loaded by LOAD-CLI-COVERAGE-SYSTEMS is skipped here; the
membership check runs against a hash table built once, not the raw
coverage-systems list, so it stays O(1) per requested system."
  (let* ((coverage-p (cli-options-coverage options))
         (coverage-systems (make-hash-table :test (function equal))))
    (dolist (system (cli-options-coverage-systems options))
      (setf (gethash system coverage-systems) t))
    (dolist (system (cli-options-systems options))
      (unless (and coverage-p (gethash system coverage-systems))
        (ensure-requested-system-visible system options)
        (if coverage-p
            (asdf:load-system system :force t)
            (asdf:load-system system))))))

(defun load-cli-source-files (source-files)
  (dolist (file source-files)
    (load file)))

(defun load-requested-inputs (options)
  (multiple-value-bind (asd-files source-files)
      (partition-cli-load-files options)
    (load-cli-asd-files asd-files)
    (load-cli-coverage-systems options)
    (load-cli-requested-systems options)
    (load-cli-source-files source-files)))

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

(defun run-execution-argument-pairs (options)
  (let* ((system-pathnames
           (loop for system in (cli-options-coverage-systems options)
                 do (ensure-requested-system-visible system options)
                 append (cl-weave::asdf-system-files system)))
         (arguments (run-all-options-from-environment options)))
    (setf (getf arguments :coverage-include-pathnames)
          (append system-pathnames
                  (getf arguments :coverage-include-pathnames)))
    (run-options-with-attempt-observer
     (merge-run-option-plists arguments (run-option-overrides)))))

(defun call-list-command (options stream)
  (let ((arguments
          (merge-run-option-plists
           (append (run-all-options-from-environment options)
                   (list :stream stream))
           (run-option-overrides))))
    (apply #'cl-weave:list-tests
           (loop for key in '(:reporter :name-filter :shard :order :seed
                              :retry :timeout-ms :stream)
                 append (list key (getf arguments key))))))

(defun call-run-command (options stream)
  (let ((arguments (run-execution-argument-pairs options)))
    (unless (member :stream arguments)
      (setf arguments (append arguments (list :stream stream))))
    (apply #'cl-weave:run-all arguments)))

(defun watch-command-call-arguments (options)
  (let ((arguments
          (run-execution-argument-pairs options)))
    (values
     (first (cli-options-systems options))
     (merge-run-option-plists
      arguments
      (list :include-dependencies t
            :once (cli-options-watch-once options)
            :interval (cli-options-watch-interval options))))))

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
         (let ((arguments (copy-list arguments)))
           (unless (member :stream arguments)
             (setf arguments (append arguments (list :stream stream))))
           (unless (member :status-stream arguments)
             (setf arguments
                   (append arguments (list :status-stream *error-output*))))
           (apply #'cl-weave:watch-system system arguments)))))
    (:run
     (lambda (stream)
       (call-run-command options stream)))))

(defparameter *command-plan-pure-query-kinds* '(:metadata :list)
  "Command plan :KIND values whose stream callback always succeeds once it
emits output. DOCTOR is a health check rather than a pure query, so it is
intentionally excluded: its callback returns the pass/fail of the report and
that result governs the process exit code.")

(defun command-plan-success-kind-p (plan)
  "PLAN succeeds as soon as its stream callback runs; see
*COMMAND-PLAN-PURE-QUERY-KINDS* for which :KIND values that covers."
  (member (getf plan :kind) *command-plan-pure-query-kinds* :test #'eq))

(defun execute-command-plan (plan options)
  (let ((result
          (call-with-output-stream
           options
           (command-plan-stream-callback plan options))))
    (if (command-plan-success-kind-p plan)
        t
        result)))

(defun run-command (options)
  (let* ((options (cli-options-with-run-overrides options))
         (context *run-coverage-context*)
         (input-callback
           (and context
                (run-coverage-context-around-input-loading context)))
         (coverage-callback
           (and context
                (run-coverage-context-around-coverage-consumer context)))
         (cl-weave::*coverage-consumer-wrapper*
           (when coverage-callback
             (lambda (kind thunk)
               (call-with-cli-callback
                context coverage-callback thunk kind)))))
    (ensure-valid-reporter-for-command options)
    (ensure-watch-command-system options)
    (unless (eq (command-dispatch-kind options) :doctor)
      (prepare-coverage-compilation options)
      (if input-callback
          (call-with-cli-callback
           context input-callback
           (lambda () (load-requested-inputs options)))
          (load-requested-inputs options)))
    (with-cli-snapshot-settings (options)
      (with-cli-journal-settings (options)
        (execute-command-plan (command-execution-plan options) options)))))

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
  (exit-process (run-coverage argv)))

(defun call-with-cli-callback (context callback thunk &optional (kind nil kind-supplied-p))
  (if (null callback)
      (funcall thunk)
      (let ((calls 0)
            (thunk-condition nil))
        (labels ((guarded-thunk ()
                   (incf calls)
                   (unless (= calls 1)
                     (error "A cl-weave callback must invoke its thunk exactly once."))
                   (handler-case
                       (funcall thunk)
                     (serious-condition (condition)
                       (setf thunk-condition condition)
                       (error condition)))))
          (handler-case
              (let ((result
                      (if kind-supplied-p
                          (funcall callback kind #'guarded-thunk)
                          (funcall callback #'guarded-thunk))))
                (unless (= calls 1)
                  (error "A cl-weave callback must invoke its thunk exactly once."))
                result)
            (serious-condition (condition)
              (if (eq condition thunk-condition)
                  (error condition)
                  (progn
                    (setf (run-coverage-context-callback-condition context)
                          condition)
                    (error 'cli-callback-failure :condition condition)))))))))

(defun run-option-overrides ()
  (and *run-coverage-context*
       (run-coverage-context-run-options *run-coverage-context*)))

(defun merge-run-option-plists (base overrides)
  (let ((result (copy-list base)))
    (loop for (key value) on overrides by #'cddr
          for position = (position key result :test #'eq)
          do (if position
                 (setf (nth (1+ position) result) value)
                 (setf result (append result (list key value)))))
    result))

(defun cli-options-with-run-overrides (options)
  (let ((effective (copy-cli-options options)))
    (loop for (key value) on (run-option-overrides) by #'cddr
          for field = (case key
                        (:reporter :reporter)
                        (:name-filter :name-filter)
                        (:shard :shard)
                        (:order :order)
                        (:seed :seed)
                        (:bail :bail)
                        (:coverage :coverage)
                        (:coverage-output :coverage-output)
                        (:coverage-report-directory :coverage-report-directory)
                        (:coverage-include-pathnames :coverage-include-pathnames)
                        (:coverage-exclude-pathnames :coverage-exclude-pathnames)
                        (:coverage-minimum-expression :coverage-minimum-expression)
                        (:coverage-minimum-branch :coverage-minimum-branch)
                        (:pass-with-no-tests :pass-with-no-tests)
                        (:retry :retry)
                        (:timeout-ms :test-timeout-ms)
                        (:max-workers :max-workers))
          when field
            do (set-cli-option-field effective field value))
    effective))

(defun run-options-with-attempt-observer (arguments)
  (let ((observer (getf arguments :on-test-attempt-complete))
        (context *run-coverage-context*))
    (if observer
        (progn
          (setf (getf arguments :on-test-attempt-complete)
                (lambda (path assertion-count)
                  (handler-case
                      (funcall observer path assertion-count)
                    (serious-condition (condition)
                      (when context
                        (setf
                         (run-coverage-context-callback-condition context)
                         condition))
                      (error 'cli-callback-failure :condition condition)))))
          arguments)
        arguments)))

(defun run-coverage (argv &key run-options around-input-loading around-coverage-consumer)
  (let* ((context
           (make-run-coverage-context
            :run-options run-options
            :around-input-loading around-input-loading
            :around-coverage-consumer around-coverage-consumer))
         (*run-coverage-context* context))
    (handler-case
        (let ((options (parse-cli-arguments argv)))
          (cond
            ((cli-options-version options)
             (format *standard-output* "cl-weave ~A~%" (cli-version))
             0)
            ((cli-options-help options)
             (write-string (cli-usage) *standard-output*)
             0)
            (t
             (handler-bind
                 ((cl-weave::coverage-cleanup-failure
                    (lambda (condition)
                      (declare (ignore condition))
                      (let ((callback-condition
                              (run-coverage-context-callback-condition context)))
                        (when callback-condition
                          (error 'cli-callback-failure
                                 :condition callback-condition))))))
               (if (run-command options) 0 1)))))
      (cli-callback-failure (condition)
        (error (cli-callback-failure-condition condition)))
      (cli-error (condition)
        (format *error-output* "cl-weave: ~A~%~%~A" condition (cli-usage))
        2))))
