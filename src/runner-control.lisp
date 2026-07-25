(in-package #:cl-weave)

(defvar *test-name-filter* nil)
(defvar *test-sequence-order* :defined)
(defvar *test-sequence-seed* 0)
(defvar *default-retry* 0)
(defvar *default-timeout-ms* nil)
(defconstant +default-max-workers-cap+ 32)
  (defconstant +maximum-retry-count+ 1000)
  (defconstant +maximum-timeout-ms+ 86400000)
  (defconstant +maximum-worker-count+ 4096)
  (defconstant +maximum-bail-limit+ 1000000)
  (defconstant +maximum-shard-count+ 1000000)

  (progn
  #+(and sbcl unix)
  (defun online-processor-count ()
    (let ((count
            (sb-alien:alien-funcall
             (sb-alien:extern-alien "sysconf"
               (function sb-alien:long sb-alien:int))
             sb-unix:sc-nprocessors-onln)))
      (and (integerp count)
           (plusp count)
           count)))

  #-(and sbcl unix)
  (defun online-processor-count ()
    nil)

  (defun detect-default-max-workers ()
    (let ((detected (ignore-errors (online-processor-count))))
      (min +default-max-workers-cap+
           (max 2
                (if (and (integerp detected)
                         (plusp detected))
                    detected
                    2))))))

  (defparameter *default-max-workers* (detect-default-max-workers))
  (defvar *max-workers* nil)
(defvar *retry-budget-remaining* 0)
(defvar *runner-default-condition-handler-disabled* nil)
(defvar *runner-propagate-conditions* t)
(defvar *attempt-secondary-conditions* nil)

(defparameter *runner-dynamic-environment-variables*
  '(*root-suite*
    *current-suite*
    *test-context*
    *test-name-filter*
    *test-sequence-order*
    *test-sequence-seed*
    *default-retry*
    *retry-budget-remaining*
    *default-timeout-ms*
    *max-workers*
    *default-max-workers*
    *isolated-timeout-seconds*
    *snapshot-directory*
    *snapshot-file-name*
    *update-snapshots*
    *property-test-count*
    *property-seed*
    *recursive-generator-depth*
    *journal-enabled*
    *test-random-seed*))

(defconstant +stable-hash-modulus+ 4294967296)
(defconstant +stable-hash-offset+ 2166136261)
(defconstant +stable-hash-prime+ 16777619)

(defstruct execution-control
  bail-limit
  (failures 0)
  stopped)

(defmacro with-escape-continuation ((continue) &body body)
  (let ((tag (gensym "ESCAPE-TAG"))
        (value (gensym "VALUE")))
    `(let ((,tag (cons 'escape-continuation nil)))
       (catch ,tag
         (let ((,continue (lambda (,value)
                            (throw ,tag ,value))))
           ,@body)))))

(defun normalize-bail (bail)
  (cond
    ((null bail) nil)
    ((eq bail t) t)
    ((eql bail 0) nil)
    ((and (integerp bail)
          (<= 1 bail +maximum-bail-limit+))
     bail)
    (t
     (error "Bail must be NIL, T, 0, or an integer between 1 and ~D: ~S"
            +maximum-bail-limit+ bail))))

(defun failing-event-p (event)
  (member (test-event-status event) '(:fail :error)))

(defun record-event/control (control event)
  (when (and (execution-control-bail-limit control)
             (failing-event-p event))
    (incf (execution-control-failures control))
    (when (>= (execution-control-failures control)
              (execution-control-bail-limit control))
      (setf (execution-control-stopped control) t)))
  event)

