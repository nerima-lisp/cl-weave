(in-package #:cl-weave)

(defparameter *smart-assertion-operators*
  '(= /= < <= > >= eql equal equalp string= string-equal))

(defun smart-assertion-operator-p (operator)
  (member operator *smart-assertion-operators* :test #'eq))

(defun signal-smart-assertion-failure (form matcher actual expected)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher matcher
    :actual actual
    :expected expected
    :negated nil
    :pass nil)))

(defun operand-report-form (source value)
  (list :form source :value value))

(defun smart-predicate-form-p (form)
  (and (consp form)
       (symbolp (first form))
       (smart-assertion-operator-p (first form))
       (rest form)))

(defun expand-smart-predicate-assertion (actual form)
  (let* ((operator (first actual))
         (operands (rest actual))
         (values (loop for operand in operands collect (gensym "OPERAND-")))
         (report-forms (loop for operand in operands
                             for value in values
                             collect `(operand-report-form ',operand ,value))))
    `(progn
       (record-assertion)
       (let ,(loop for value in values
                   for operand in operands
                   collect `(,value ,operand))
         (if (,operator ,@values)
             (progn
               ;; Only the reporting list is skipped on the passing path when
               ;; journaling is off, keeping the common case allocation-free.
               (when (journaling-active-p)
                 (record-smart-assertion-frame
                  ',form ',operator (list ,@report-forms) ',actual t))
               t)
             (let ((reports (list ,@report-forms)))
               (when (journaling-active-p)
                 (record-smart-assertion-frame
                  ',form ',operator reports ',actual nil))
               (signal-smart-assertion-failure
                ',form ',operator reports ',actual)))))))

(defun expand-smart-truthy-assertion (actual form)
  (let ((value (gensym "ACTUAL-")))
    `(progn
       (record-assertion)
       (let ((,value ,actual))
         (when (journaling-active-p)
           (record-smart-assertion-frame
            ',form :truthy ,value t (and ,value t)))
         (unless ,value
           (signal-smart-assertion-failure
            ',form
            :truthy
            ,value
            t))
         t))))

(defun expand-smart-assertion (actual form)
  (if (smart-predicate-form-p actual)
      (expand-smart-predicate-assertion actual form)
      (expand-smart-truthy-assertion actual form)))

(defun expand-matcher-expectation (macro-name actual expectation &key negated)
  (unless (and (listp expectation) expectation)
    (error "~A requires a matcher form" macro-name))
  (let* ((matcher-designator (first expectation))
         (expected-forms (rest expectation))
         (tokens
           (append
            (when negated (list :not))
            (list matcher-designator)
            expected-forms))
         (value (gensym "ACTUAL")))
    `(progn
       (record-assertion)
       (let ((,value ,actual))
         (assert-expectation
          ,value
          (list ,@tokens)
          (quote (,macro-name ,actual ,@expectation))
          nil)))))

(defun ensure-expect-thunk (thunk matcher form)
  (unless (functionp thunk)
    (signal-assertion-failure
     (make-assertion-detail
      :form form
      :matcher matcher
      :actual (list :callable nil :value thunk)
      :expected '(:callable t)
      :negated nil
      :pass nil)))
  thunk)

(defparameter *expect-poll-default-timeout-ms* 1000)
(defparameter *expect-poll-default-interval-ms* 50)

(defun unknown-plist-keys (plist allowed-keys)
  (loop for (key nil) on plist by #'cddr
        unless (member key allowed-keys :test #'eq)
          collect key))

(defun normalize-expect-poll-options (options form)
  (let ((raw-options options))
    (unless (or (null raw-options)
                (option-plist-form-p raw-options))
      (error "cl-weave: EXPECT-POLL options in ~S must be a property list, got ~S."
             form
             raw-options))
    (let ((unknown-keys (unknown-plist-keys raw-options '(:timeout-ms :interval-ms))))
      (when unknown-keys
        (error "cl-weave: EXPECT-POLL options in ~S contain unsupported keys ~S."
               form
               unknown-keys))
      (let ((timeout-ms (if (plist-key-present-p raw-options :timeout-ms)
                            (getf raw-options :timeout-ms)
                            *expect-poll-default-timeout-ms*))
            (interval-ms (if (plist-key-present-p raw-options :interval-ms)
                             (getf raw-options :interval-ms)
                             *expect-poll-default-interval-ms*)))
        (unless (and (realp timeout-ms) (not (minusp timeout-ms)))
          (error "cl-weave: EXPECT-POLL :timeout-ms in ~S must be a non-negative real, got ~S."
                 form
                 timeout-ms))
        (unless (and (realp interval-ms) (not (minusp interval-ms)))
          (error "cl-weave: EXPECT-POLL :interval-ms in ~S must be a non-negative real, got ~S."
                 form
                 interval-ms))
        (list :timeout-ms timeout-ms
              :interval-ms interval-ms)))))

(define-record-class poll-state
  (deadline timeout-ms interval-ms attempts last-value last-condition last-detail))

(defun milliseconds-to-internal-time (milliseconds)
  (/ (* milliseconds internal-time-units-per-second) 1000))

(defun make-initial-poll-state (timeout-ms interval-ms)
  (make-poll-state
   :deadline (+ (get-internal-real-time)
                (milliseconds-to-internal-time timeout-ms))
   :timeout-ms timeout-ms
   :interval-ms interval-ms
   :attempts 0))

(defun poll-deadline-reached-p (state)
  (>= (get-internal-real-time) (poll-state-deadline state)))

(defun poll-last-assertion-report (detail)
  (list :matcher (assertion-detail-matcher detail)
        :actual (assertion-detail-actual detail)
        :expected (assertion-detail-expected detail)
        :negated (assertion-detail-negated detail)
        :pass (assertion-detail-pass detail)))

(defun signal-expect-poll-timeout (form state)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher :poll
    :actual (append
             (list :attempts (poll-state-attempts state)
                   :timeout-ms (poll-state-timeout-ms state)
                   :interval-ms (poll-state-interval-ms state)
                   :last-value (poll-state-last-value state))
             (when (poll-state-last-condition state)
               (list :last-condition
                     (rejected-thunk-report (poll-state-last-condition state))))
             (when (poll-state-last-detail state)
               (list :last-assertion
                     (poll-last-assertion-report (poll-state-last-detail state)))))
    :expected '(:state :pass)
    :negated nil
    :pass nil)))

(defun call-poll-thunk/k (callable pass-k reject-k)
  (multiple-value-bind (accepted-p result)
      (handler-case
          (values t (funcall callable))
        (condition (condition)
          (values nil condition)))
    (funcall (if accepted-p pass-k reject-k) result)))

(defun assess-poll-value/k (value expectation form pass-k retry-k)
  (multiple-value-bind (pass detail)
      (handler-case
          (assert-expectation value expectation form)
        (assertion-failure (condition)
          (values nil (failure-detail condition))))
    (funcall (if pass pass-k retry-k) detail)))

(defun poll-step/k (callable expectation form state pass-k retry-k timeout-k)
  (incf (poll-state-attempts state))
  (call-poll-thunk/k
   callable
   (lambda (value)
     (setf (poll-state-last-value state) value
           (poll-state-last-condition state) nil)
     (assess-poll-value/k
      value expectation form
      (lambda (detail)
        (setf (poll-state-last-detail state) detail)
        (if (poll-deadline-reached-p state)
            (funcall timeout-k state)
            (funcall pass-k value)))
      (lambda (detail)
        (setf (poll-state-last-detail state) detail)
        (if (poll-deadline-reached-p state)
            (funcall timeout-k state)
            (funcall retry-k state)))))
   (lambda (condition)
     (setf (poll-state-last-condition state) condition
           (poll-state-last-detail state) nil)
     (if (poll-deadline-reached-p state)
         (funcall timeout-k state)
         (funcall retry-k state)))))

(defun call-polling-expectation-thunk (thunk expectation options form)
  (let* ((callable (ensure-expect-thunk thunk :poll form))
         (normalized-options (normalize-expect-poll-options options form))
         (timeout-ms (getf normalized-options :timeout-ms))
         (interval-ms (getf normalized-options :interval-ms))
         (state (make-initial-poll-state timeout-ms interval-ms)))
    (loop
      (poll-step/k
       callable expectation form state
       (lambda (value)
         (return-from call-polling-expectation-thunk value))
       (lambda (next-state)
         (declare (ignore next-state))
         (when (plusp interval-ms)
           (sleep (/ interval-ms 1000.0))))
       (lambda (timed-out-state)
         (signal-expect-poll-timeout form timed-out-state))))))

(defun rejected-thunk-report (condition)
  (list :state :rejected
        :condition-type (type-of condition)
        :message (princ-to-string condition)))

(defun resolved-thunk-report (value)
  (list :state :resolved :value value))

(defun call-resolving-expectation-thunk (thunk form)
  (let ((callable (ensure-expect-thunk thunk :resolves form)))
    (handler-case
        (funcall callable)
      (condition (condition)
        (signal-assertion-failure
         (make-assertion-detail
          :form form
          :matcher :resolves
          :actual (rejected-thunk-report condition)
          :expected '(:state :resolved)
          :negated nil
          :pass nil))))))

(defun call-rejecting-expectation-thunk (thunk form)
  (let ((callable (ensure-expect-thunk thunk :rejects form)))
    (multiple-value-bind (rejected-p result)
        (handler-case
            (values nil (funcall callable))
          (condition (condition)
            (values t condition)))
      (if rejected-p
          result
          (signal-assertion-failure
           (make-assertion-detail
            :form form
            :matcher :rejects
            :actual (resolved-thunk-report result)
            :expected '(:state :rejected)
            :negated nil
            :pass nil))))))
