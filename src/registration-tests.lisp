(in-package #:cl-weave)

(defun option-plist-form-p (form)
  (and (consp form)
       (evenp (length form))
       (loop for (key nil) on form by #'cddr
             always (keywordp key))))

(defun plist-key-present-p (plist key)
  (loop for (candidate nil) on plist by #'cddr
        thereis (eq candidate key)))

(defmacro define-registration-option-accessors (&rest specifications)
  `(progn
     ,@(loop for (name key) on specifications by #'cddr
             collect `(defun ,(intern (format nil "TEST-REGISTRATION-OPTION-~A" name)
                                      *package*)
                          (options)
                        (getf options ,key)))))

(define-registration-option-accessors
    retry :retry
    timeout-ms :timeout-ms
    execution-mode :execution-mode
    tags :tags
    watch-depends-on :watch-depends-on)

(defun ensure-unique-option-keys (options)
  (loop with seen = '()
        for (key nil) on options by #'cddr
        when (member key seen)
          do (error "Duplicate test option ~S." key)
        do (push key seen))
  options)

(defparameter *test-registration-option-keys*
  '(:retry :timeout-ms :execution-mode :tags :watch-depends-on)
  "Option keys accepted by TEST-REGISTRATION-OPTIONS.")

(defun test-registration-options (options)
  (ensure-unique-option-keys options)
  (loop for (key nil) on options by #'cddr
        unless (member key *test-registration-option-keys*)
          do (error "Unknown test option ~S." key))
  (append
     (when (plist-key-present-p options :retry)
       `(:retry ,(test-registration-option-retry options)))
     (when (plist-key-present-p options :timeout-ms)
       `(:timeout-ms ,(test-registration-option-timeout-ms options)))
     (when (plist-key-present-p options :execution-mode)
       `(:execution-mode ,(test-registration-option-execution-mode options)))
     (when (plist-key-present-p options :tags)
       `(:tags ,(test-registration-option-tags options)))
     (when (plist-key-present-p options :watch-depends-on)
       `(:watch-depends-on
         ,(test-registration-option-watch-depends-on options)))))

(defun split-leading-option-plist (body)
  (if (and body (option-plist-form-p (first body)))
      (values (first body) (rest body))
      (values nil body)))

(defun test-registration-form (name forms options)
  (if forms
      `(register-test ,name (lambda () ,@forms)
                      ,@options
                      ,@(source-location-option))
      (let ((function (gensym "TEST-FUNCTION")))
        `(let ((,function (lambda ())))
           (register-test ,name ,function
                          :trusted-empty-function ,function
                          ,@options
                          ,@(source-location-option))))))

(defun test-options-with-registration-options (options prefix-options)
  (let* ((registration-options (test-registration-options options))
           (fixed-mode (test-registration-option-execution-mode prefix-options))
           (requested-mode (test-registration-option-execution-mode registration-options)))
    (when (and fixed-mode requested-mode (not (eql fixed-mode requested-mode)))
      (error "Execution mode ~S conflicts with fixed mode ~S."
             requested-mode fixed-mode))
    (append prefix-options
            (if fixed-mode
                (loop for (key value) on registration-options by #'cddr
                      unless (eq key :execution-mode)
                        append (list key value))
                registration-options))))

(defmacro define-test-registration-macro (name prefix-options)
  `(defmacro ,name (test-name &body body)
     (multiple-value-bind (options forms) (split-leading-option-plist body)
       (test-registration-form
        test-name
        forms
        (test-options-with-registration-options options ,prefix-options)))))

(defmacro define-reasoned-test-registration-macro (name option-key default-reason body-form)
  `(defmacro ,name (test-name &optional (reason ,default-reason))
     (test-registration-form test-name ,body-form (list ,option-key reason))))

(define-registration-family define-test-registration-macro
    define-reasoned-test-registration-macro
  (:plain it nil)
  (:plain it-only '(:focus t))
  (:plain it-concurrent '(:execution-mode :concurrent))
  (:plain it-sequential '(:execution-mode :sequential))
  (:plain it-fails '(:expected-failure-reason "expected failure"))
  (:reasoned it-skip :skip-reason "skipped" '(nil))
  (:reasoned it-todo :todo-reason "todo" '(nil)))

(define-registration-family define-suite-each-macro define-reasoned-each-macro
  (:plain it-each it)
  (:plain it-only-each it-only)
  (:plain it-concurrent-each it-concurrent)
  (:plain it-sequential-each it-sequential)
  (:plain it-fails-each it-fails)
  (:reasoned it-skip-each it-skip "skipped" nil)
  (:reasoned it-todo-each it-todo "todo" nil))

(define-conditional-registration-macro it-skip-if it it-skip "conditional skip" nil t)

(define-conditional-registration-macro it-run-if it it-skip "conditional run-if" nil nil)

(defun isolated-option-form (options key fallback)
  (if (plist-key-present-p options key)
      (getf options key)
      fallback))

(defun isolated-systems-option-form (options)
  (let ((systems (getf options :systems)))
    (cond
      ((null systems) ''("cl-weave"))
      ((and (listp systems)
            (not (eq (first systems) 'quote)))
       `',systems)
      (t systems))))

(defmacro it-isolated (name &body body)
  (let* ((options (when (and body (option-plist-form-p (first body)))
                    (first body)))
         (forms (if options (rest body) body))
         (timeout (isolated-option-form options :timeout '*isolated-timeout-seconds*))
         (package (isolated-option-form options :package (package-name *package*)))
         (keep-files (isolated-option-form options :keep-files nil))
         (systems (isolated-systems-option-form options))
         (form `(progn ,@forms)))
    `(it ,name
       (let ((result (run-isolated ',form
                                   :systems ,systems
                                   :package ,package
                                   :timeout ,timeout
                                   :keep-files ,keep-files)))
         (if (eq (isolated-result-status result) :pass)
             t
             (signal-isolated-failure result ',form))))))

(defmacro it-property (name bindings &body body)
  (unless (registration-proper-list-p bindings)
    (registration-syntax-error
     "IT-PROPERTY requires BINDINGS to be a literal proper list, got ~S." bindings))
  (loop for binding in bindings
        for index from 0
        unless (and (registration-proper-list-p binding)
                    (= (length binding) 2)
                    (symbolp (first binding))
                    (first binding))
          do (let ((*print-circle* t))
               (error "IT-PROPERTY binding ~D must have the form (NAME GENERATOR), got ~S."
                      index binding)))
  (let ((names (mapcar #'first bindings))
        (generators (mapcar #'second bindings)))
    `(it ,name
       (run-property
        (list ,@generators)
        (lambda ,names ,@body)
        ',names
        '(it-property ,name ,bindings ,@body)))))

(defparameter *fuzz-registration-option-keys*
  '(:trials :timeout-per-trial)
  "Option keys accepted by IT-FUZZ's OPTIONS plist.")

(defun %fuzz-options-plist (options)
  (unless (registration-proper-list-p options)
    (registration-syntax-error
     "IT-FUZZ requires OPTIONS to be a literal proper list, got ~S." options))
  (loop for (key value) on options by #'cddr
        unless (member key *fuzz-registration-option-keys*)
          do (registration-syntax-error
              "IT-FUZZ OPTIONS accepts only :TRIALS and :TIMEOUT-PER-TRIAL, got ~S." key)
        collect key
        collect value))

(defmacro it-fuzz (name bindings options &body body)
  "Fuzz test built on IT-PROPERTY's generator and shrinking machinery.

Unlike IT-PROPERTY, BODY is not a boolean predicate: a trial passes simply
by running without signaling an ERROR. Each trial runs under a
TIMEOUT-PER-TRIAL second budget (default 5); a trial that merely times out
is not evidence of a bug, so it counts as neither a pass nor a failure and
is skipped rather than shrunk. A trial that signals an ERROR is a failure,
and its generated inputs are minimized the same way a failing
IT-PROPERTY's are.

BINDINGS is a literal ((NAME GENERATOR)...) list, as in IT-PROPERTY.
OPTIONS is a literal property list accepting :TRIALS (default 100) and
:TIMEOUT-PER-TRIAL seconds (default 5, or NIL to disable the timeout)."
  (unless (registration-proper-list-p bindings)
    (registration-syntax-error
     "IT-FUZZ requires BINDINGS to be a literal proper list, got ~S." bindings))
  (loop for binding in bindings
        for index from 0
        unless (and (registration-proper-list-p binding)
                    (= (length binding) 2)
                    (symbolp (first binding))
                    (first binding))
          do (let ((*print-circle* t))
               (error "IT-FUZZ binding ~D must have the form (NAME GENERATOR), got ~S."
                      index binding)))
  (let* ((plist (%fuzz-options-plist options))
         (names (mapcar #'first bindings))
         (generators (mapcar #'second bindings))
         (trials (getf plist :trials 100))
         (timeout-per-trial (getf plist :timeout-per-trial 5)))
    `(it ,name
       (let ((*property-test-count* ,trials))
         (run-property
          (list ,@generators)
          (lambda ,names
            (handler-case
                (call-with-platform-timeout/k
                 ,timeout-per-trial
                 (lambda () ,@body)
                 #'identity)
              (platform-timeout () :fuzz-trial-timed-out)))
          ',names
          '(it-fuzz ,name ,bindings ,options ,@body))))))
