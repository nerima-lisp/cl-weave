(in-package #:cl-weave)

(defmacro define-conditional-lock-macro (name arguments mutex-form)
  "Define NAME as a macro (ARGUMENTS &body BODY) that runs BODY inside
SB-THREAD:WITH-MUTEX on MUTEX-FORM when SB-THREAD is present, or evaluates
BODY directly otherwise. ARGUMENTS is NAME's own parameter list before
&BODY -- () for a lock guarding one fixed global mutex, or ((BINDING)) when
MUTEX-FORM is a template naming BINDING, substituted at NAME's own
expansion time with whatever expression NAME's caller supplies for it --
e.g. (mock-state-lock state) with a caller-supplied (spy-frame-state frame)
becomes (mock-state-lock (spy-frame-state frame))."
  (let ((binding-names (mapcar #'first arguments)))
    `(defmacro ,name (,@arguments &body body)
       (append
        (list #+sb-thread 'sb-thread:with-mutex #-sb-thread 'progn)
        #+sb-thread
        (list (list (sublis (list ,@(loop for binding in binding-names
                                           collect `(cons ',binding ,binding)))
                             ',mutex-form)))
        body))))

#+sbcl
(progn
  (pushnew :timeout *platform-capabilities* :test #'eq)
  (setf *platform-timeout-condition-predicate*
        (lambda (condition) (typep condition 'sb-ext:timeout)))
  (setf *platform-timeout-caller*
        (lambda (timeout-seconds callable continue)
          (handler-case
              (sb-ext:with-timeout timeout-seconds
                (funcall continue (funcall callable)))
            (sb-ext:timeout ()
              (error 'platform-timeout))))))

;; :ISOLATION (SB-EXT:RUN-PROGRAM-backed subprocess isolation, src/isolation.
;; lisp's RUN-ISOLATED) and :CONCURRENCY (SB-THREAD-backed parallel test
;; execution, src/runner-concurrency.lisp's RUN-CONCURRENT-TEST-CASES) are
;; each genuinely SBCL/OS-specific -- process spawning and native threads have
;; no portable ANSI CL equivalent -- so, like :TIMEOUT above, they are
;; capabilities to check for and degrade from gracefully, not things to fake
;; on another implementation. :CONCURRENCY specifically needs SB-THREAD, not
;; merely SBCL: an SBCL built without thread support has :SBCL but not
;; SB-THREAD, and RUN-CONCURRENT-TEST-CASES's own #+sb-thread/#-sb-thread
;; split already reads that condition directly rather than through this list,
;; so this mirrors it here for callers (tests, in particular) that want to
;; ask via PLATFORM-CAPABILITY-AVAILABLE-P instead of duplicating a reader
;; conditional of their own.
#+sbcl
(pushnew :isolation *platform-capabilities* :test #'eq)
#+sb-thread
(pushnew :concurrency *platform-capabilities* :test #'eq)
