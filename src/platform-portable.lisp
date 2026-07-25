(in-package #:cl-weave)

(setf *platform-capabilities*
      (remove :timeout *platform-capabilities* :test #'eq)
      *platform-timeout-caller* nil
      *platform-timeout-condition-predicate* nil)
