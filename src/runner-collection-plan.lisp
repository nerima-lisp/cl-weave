(in-package #:cl-weave)

(declaim (ftype (function (suite list function selection-filter
                           &optional t t t t)
                          *)
                collect-children-plan/k))

(defun collect-suite-plan/k
    (suite continue filter
     &optional ancestor-focused suppressed-status suppressed-reason
       inherited-execution-mode)
  (if (selected-suite-p suite filter ancestor-focused) (let ((active-execution-mode
              (effective-suite-execution-mode suite inherited-execution-mode)))
        (multiple-value-bind (active-status active-reason)
            (suite-suppression suite suppressed-status suppressed-reason)
          (collect-children-plan/k
           suite
           (ordered-children suite (suite-children suite))
           continue
           filter
           ancestor-focused
           active-status
           active-reason
           active-execution-mode))) (funcall continue nil nil)))

(defun collect-children-plan/k
    (suite children continue filter
     &optional ancestor-focused suppressed-status suppressed-reason
       execution-mode)
  (macrolet ((recur (remaining next-continue)
               (list 'collect-children-plan/k
                     'suite
                     remaining
                     next-continue
                     'filter
                     'ancestor-focused
                     'suppressed-status
                     'suppressed-reason
                     'execution-mode)))
    (labels ((continue-with-tail (entries entries-last)
               (recur (rest children)
                      (lambda (tail tail-last)
                        (continue-with-linked-segments
                         continue entries entries-last tail tail-last))))
             (continue-with-entry (entry)
               (let ((entries (list entry)))
                 (recur (rest children)
                        (lambda (tail tail-last)
                          (continue-with-linked-segments
                           continue entries entries tail tail-last))))))
      (if children (let ((child (first children)))
            (multiple-value-bind (step payload)
                (describe-plan-collection-step
                 suite
                 child
                 filter
                 ancestor-focused
                 suppressed-status
                 suppressed-reason
                 execution-mode)
              (ecase step
                (:skip
                 (recur (rest children) continue))
                (:collect-suite
                 (collect-suite-plan/k
                  child
                  #'continue-with-tail
                  filter
                  payload
                  suppressed-status
                  suppressed-reason
                  execution-mode))
                (:collect-test
                 (continue-with-entry payload))))) (funcall continue nil nil)))))

(defun collect-test-plan-with-options (suite options)
  (let ((suite (snapshot-suite suite)))
    (call-with-collection-context
     suite
     options
     (lambda (filter)
       (collect-suite-plan/k
        suite
        (lambda (entries entries-last)
          (declare (ignore entries-last))
          entries)
        filter)))))

(defun collect-test-plan
    (suite &key name-filter location-filter test-path-filter
                include-tags exclude-tags shard order seed retry
                timeout-ms)
  (collect-test-plan-with-options
   suite
   (normalize-collection-options
    :name-filter name-filter
    :location-filter location-filter
    :test-path-filter test-path-filter
    :include-tags include-tags
    :exclude-tags exclude-tags
    :shard shard
    :order order
    :seed seed
    :retry retry
    :timeout-ms timeout-ms)))
