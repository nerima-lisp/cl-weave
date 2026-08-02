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
