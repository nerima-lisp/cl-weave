(in-package #:cl-weave)

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
