(in-package #:cl-weave)

(defun todo-or-skip-suppression (todo-reason skip-reason)
  (cond
    (todo-reason (values :todo todo-reason))
    (skip-reason (values :skip skip-reason))
    (t (values nil nil))))

(defun suite-suppression (suite inherited-status inherited-reason)
  (if inherited-status
      (values inherited-status inherited-reason)
      (todo-or-skip-suppression (suite-todo-reason suite) (suite-skip-reason suite))))

(defun suppressed-test-event (suite test status reason)
  (make-event status suite test (get-internal-real-time) :reason reason))

(defun planned-test-suppression (test suppressed-status suppressed-reason)
  (if suppressed-status
      (values suppressed-status suppressed-reason)
      (multiple-value-bind (status reason)
          (todo-or-skip-suppression
           (test-case-todo-reason test) (test-case-skip-reason test))
        (values (or status :run) reason))))

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
    (test status reason filter ancestor-focused execution-mode)
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

(defun collected-test-event (suite test suppressed-status suppressed-reason)
  (if suppressed-status
      (suppressed-test-event suite test suppressed-status suppressed-reason)
      (run-test-case/internal suite test)))

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
                    (collected-test-event suite child suppressed-status suppressed-reason))
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
       (multiple-value-bind (status reason)
           (planned-test-suppression child suppressed-status suppressed-reason)
         (values :collect-test
                 (make-plan-entry
                  child
                  status
                  reason
                  filter
                  ancestor-focused
                  execution-mode)
                 nil)))
      (:skip
       (values :skip nil nil)))))
