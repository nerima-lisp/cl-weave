(in-package #:cl-weave)

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
                  2)))))

(defparameter *default-max-workers* (detect-default-max-workers))

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

