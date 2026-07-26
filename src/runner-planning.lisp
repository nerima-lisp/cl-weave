(in-package #:cl-weave)

(defun suite-suppression (suite inherited-status inherited-reason)
  (cond
    (inherited-status
     (values inherited-status inherited-reason))
    ((suite-todo-reason suite)
     (values :todo (suite-todo-reason suite)))
    ((suite-skip-reason suite)
     (values :skip (suite-skip-reason suite)))
    (t
     (values nil nil))))

(defun suppressed-test-event (suite test status reason)
  (make-event status suite test (get-internal-real-time) :reason reason))

(defun planned-test-status (test suppressed-status)
  (or suppressed-status
      (when (test-case-todo-reason test) :todo)
      (when (test-case-skip-reason test) :skip)
      :run))

(defun planned-test-reason (test suppressed-status suppressed-reason status)
  (if suppressed-status
      suppressed-reason
      (ecase status
        (:run nil)
        (:todo (test-case-todo-reason test))
        (:skip (test-case-skip-reason test)))))

(defun effective-suite-execution-mode (suite inherited-mode)
  (or (suite-execution-mode suite)
      inherited-mode))

(defun effective-test-execution-mode (test inherited-mode)
  (or (test-case-execution-mode test)
      inherited-mode))

(defun effective-concurrent-test-case-p (test inherited-mode)
  (and (test-case-p test)
       (eq (effective-test-execution-mode test inherited-mode) :concurrent)))

(defun make-plan-entry
    (suite test status reason filter ancestor-focused execution-mode)
  (declare (ignore suite))
  (make-test-plan-entry-record
   (gethash test (selection-filter-test-paths filter))
   status
   reason
   (and (selection-filter-focus-enabled filter)
        (or ancestor-focused (test-case-focus test)))
   (retry-count test)
   (effective-timeout-ms test)
   (effective-concurrent-test-case-p test execution-mode)
   (test-case-location test)
   (test-case-tags test)))

(defun concurrent-batching-enabled-p (control suppressed-status)
  (and (null suppressed-status)
       (null (execution-control-bail-limit control))))

(defun collect-leading-concurrent-tests
    (suite children filter ancestor-focused execution-mode)
  (labels ((walk (remaining selected)
             (let ((child (first remaining)))
               (if (and (effective-concurrent-test-case-p child execution-mode)
                        (selected-test-case-p suite child filter ancestor-focused))
                   (walk (rest remaining) (cons child selected))
                   (values (nreverse selected) remaining)))))
    (walk children '())))

(defun classify-selected-child (suite child filter ancestor-focused)
  (cond
    ((suite-p child)
     (let ((child-focused (or ancestor-focused (suite-focus child))))
       (if (selected-child-suite-p child filter child-focused)
           (values :suite child-focused)
           (values :skip nil))))
    ((test-case-p child)
     (values (if (selected-child-test-p suite child filter ancestor-focused)
                 :test
                 :skip)
             nil))
    (t
     (values :skip nil))))

(defun describe-event-collection-step
    (suite child children control filter ancestor-focused
     suppressed-status suppressed-reason execution-mode)
  (multiple-value-bind (selection-kind child-focused)
      (classify-selected-child suite child filter ancestor-focused)
    (ecase selection-kind
      (:suite
       (values :collect-suite child-focused nil nil))
      (:test
       (if (and (effective-concurrent-test-case-p child execution-mode)
                (concurrent-batching-enabled-p control suppressed-status))
           (multiple-value-bind (tests rest-children)
               (collect-leading-concurrent-tests
                suite children filter ancestor-focused execution-mode)
             (values :collect-concurrent tests rest-children nil))
           (values :collect-test
                   (record-event/control
                    control
                    (if suppressed-status
                        (suppressed-test-event suite child suppressed-status suppressed-reason)
                        (run-test-case/internal suite child)))
                   nil
                   nil)))
      (:skip
       (values :skip nil nil nil)))))

(defun describe-plan-collection-step
    (suite child filter ancestor-focused suppressed-status suppressed-reason execution-mode)
  (multiple-value-bind (selection-kind child-focused)
      (classify-selected-child suite child filter ancestor-focused)
    (ecase selection-kind
      (:suite
       (values :collect-suite child-focused nil))
      (:test
       (let* ((status (planned-test-status child suppressed-status))
              (reason (planned-test-reason child suppressed-status suppressed-reason status))
              (entry (make-plan-entry
                      suite
                      child
                      status
                      reason
                      filter
                      ancestor-focused
                      execution-mode)))
         (values :collect-test entry nil)))
      (:skip
       (values :skip nil nil)))))
