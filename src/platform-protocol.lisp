(in-package #:cl-weave)

(define-condition platform-capability-unavailable (error)
  ((capability :initarg :capability
               :reader platform-capability-unavailable-capability)
   (implementation :initarg :implementation
                   :reader platform-capability-unavailable-implementation))
  (:report
   (lambda (condition stream)
     (format stream "cl-weave: platform capability ~S is unavailable on ~A."
             (platform-capability-unavailable-capability condition)
             (platform-capability-unavailable-implementation condition)))))

(define-condition platform-timeout (error) ())

(defvar *platform-capabilities* nil)
(defvar *platform-timeout-caller* nil)
;; Predicate that recognizes the platform's raw timeout interrupt (e.g. an
;; SBCL sb-ext:timeout) before it is translated into PLATFORM-TIMEOUT. Portable
;; code uses PLATFORM-TIMEOUT-INTERRUPT-P so it can let that interrupt propagate
;; instead of swallowing it as an ordinary serious-condition.
(defvar *platform-timeout-condition-predicate* nil)

(defun platform-timeout-interrupt-p (condition)
  (and *platform-timeout-condition-predicate*
       (funcall *platform-timeout-condition-predicate* condition)))

(defun platform-capability-available-p (capability)
  (not (null (member capability *platform-capabilities* :test #'eq))))

(defun require-platform-capability (capability)
  (unless (platform-capability-available-p capability)
    (error 'platform-capability-unavailable
           :capability capability
           :implementation (lisp-implementation-type)))
  capability)

(defun call-with-platform-timeout/k (timeout-seconds callable continue)
  (if timeout-seconds
      (progn
        (require-platform-capability :timeout)
        (funcall *platform-timeout-caller*
                 timeout-seconds callable continue))
      (funcall continue (funcall callable))))
