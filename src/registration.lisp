(in-package #:cl-weave)

(defun split-reasoned-body (body default-reason)
  (if (and body (stringp (first body)))
      (values (first body) (rest body))
      (values default-reason body)))

(defun registration-proper-list-p (value)
  (cond
    ((null value) t)
    ((atom value) nil)
    (t
     (labels ((walk (slow fast)
                (cond
                  ((null fast) t)
                  ((atom fast) nil)
                  ((null (cdr fast)) t)
                  ((atom (cdr fast)) nil)
                  (t
                   (let ((next-slow (cdr slow))
                         (next-fast (cddr fast)))
                     (and (not (eq next-slow next-fast))
                          (walk next-slow next-fast)))))))
       (walk value value)))))

(defun suite-registration-form (name forms options)
  `(register-suite ,name
                   (lambda () ,@forms)
                   ,@options
                   ,@(source-location-option)))

(defun registration-syntax-error (format-control &rest arguments)
  ;; Format eagerly: the arguments may be circular, and a condition holding
  ;; them raw would explode when printed outside this *PRINT-CIRCLE* binding.
  (error "~A"
         (let ((*print-circle* t))
           (apply #'format nil format-control arguments))))

(defun format-each-case-name (target format-string case index)
  (handler-case
      (apply #'format nil format-string case)
    (error (condition)
      (error "~S case ~D does not match format string ~S: ~A"
             target index format-string condition))))

(defun validate-suite-each-syntax (cases name bindings target)
  (unless (registration-proper-list-p cases)
    (registration-syntax-error
     "~S requires CASES to be a literal proper list, got ~S." target cases))
  (unless (stringp name)
    (registration-syntax-error
     "~S requires NAME to be a literal format string, got ~S." target name))
  (unless (registration-proper-list-p bindings)
    (registration-syntax-error
     "~S requires BINDINGS to be a literal proper list, got ~S." target bindings))
  (loop for case in cases
        for index from 0
        unless (registration-proper-list-p case)
          do (registration-syntax-error
              "~S case ~D must be a literal proper list, got ~S."
              target index case))
  (values))

(defun suite-each-cases (cases name bindings forms target)
  (validate-suite-each-syntax cases name bindings target)
  (loop for case in cases
        for index from 0
        collect `(,target ,(format-each-case-name target name case index)
                   (destructuring-bind ,bindings ',case
                     ,@forms))))

(defun reasoned-each-cases (cases name bindings body target wrapper default-reason
                            include-body-p)
  (validate-suite-each-syntax cases name bindings target)
  (multiple-value-bind (reason forms) (split-reasoned-body body default-reason)
    (unless include-body-p
      (when forms
        (error "~S does not accept a test body; only an optional reason string is allowed."
               target)))
    (loop for case in cases
          for index from 0
          collect `(,wrapper ,(format-each-case-name target name case index)
                     ,reason
                     ,@(when include-body-p
                         `((destructuring-bind ,bindings ',case
                             ,@forms)))))))

(defmacro define-suite-each-macro (name target)
  `(defmacro ,name (cases suite-name bindings &body body)
     `(progn ,@(suite-each-cases cases suite-name bindings body ',target))))

(defmacro define-reasoned-each-macro (name wrapper default-reason include-body-p)
  `(defmacro ,name (cases suite-name bindings &body body)
     `(progn ,@(reasoned-each-cases cases suite-name bindings body
                                    ',name ',wrapper
                                    ,default-reason
                                    ,include-body-p))))

(defmacro define-suite-registration-macro (name options-form)
  `(defmacro ,name (suite-name &body body)
     (suite-registration-form suite-name body ,options-form)))

(defmacro define-reasoned-suite-registration-macro (name option-key default-reason)
  `(defmacro ,name (suite-name &body body)
     (multiple-value-bind (reason forms) (split-reasoned-body body ,default-reason)
       (suite-registration-form suite-name forms (list ,option-key reason)))))

(defmacro define-registration-family (plain-macro reasoned-macro &rest specifications)
  `(progn
     ,@(loop for specification in specifications
             collect (destructuring-bind (kind name &rest arguments) specification
                       (ecase kind
                         (:plain `(,plain-macro ,name ,@arguments))
                         (:reasoned `(,reasoned-macro ,name ,@arguments)))))))

(define-registration-family define-suite-registration-macro
    define-reasoned-suite-registration-macro
  (:plain describe nil)
  (:plain describe-only '(:focus t))
  (:plain describe-concurrent '(:execution-mode :concurrent))
  (:plain describe-sequential '(:execution-mode :sequential))
  (:reasoned describe-skip :skip-reason "skipped")
  (:reasoned describe-todo :todo-reason "todo"))

(define-registration-family define-suite-each-macro define-reasoned-each-macro
  (:plain describe-each describe)
  (:plain describe-only-each describe-only)
  (:reasoned describe-skip-each describe-skip "skipped" t)
  (:reasoned describe-todo-each describe-todo "todo" t))

(defun conditional-registration-form (condition reg-name body active-macro skip-macro
                                       skip-reason skip-includes-body-p skip-branch-first-p)
  (let ((active-form `(,active-macro ,reg-name ,@body))
        (skip-form `(,skip-macro ,reg-name ,skip-reason
                                  ,@(when skip-includes-body-p body))))
    (if skip-branch-first-p
        `(if ,condition ,skip-form ,active-form)
        `(if ,condition ,active-form ,skip-form))))

(defmacro define-conditional-registration-macro
    (macro-name active-macro skip-macro skip-reason skip-includes-body-p
     skip-branch-first-p)
  `(defmacro ,macro-name (condition reg-name &body body)
     (conditional-registration-form condition reg-name body
                                     ',active-macro ',skip-macro
                                     ,skip-reason ,skip-includes-body-p
                                     ,skip-branch-first-p)))

(define-conditional-registration-macro describe-skip-if describe describe-skip
    "conditional skip" t t)

(define-conditional-registration-macro describe-run-if describe describe-skip
    "conditional run-if" t nil)

(defun source-location-form ()
  `',(let ((pathname (or *compile-file-pathname* *load-pathname*)))
       (when pathname
         (list :file (namestring pathname)))))

(defun source-location-option ()
  `(:location ,(source-location-form)))

