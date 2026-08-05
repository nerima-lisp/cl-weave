(in-package #:cl-weave)

(defun suite-hook-path (suite phase)
  (append (mapcar #'suite-name (rest (suite-lineage suite)))
          (list (string-downcase (symbol-name phase)))))

(defun make-suite-hook-event (suite phase causes)
  (make-test-event
   :status :error
   :path (suite-hook-path suite phase)
   :condition (make-condition 'hook-failure :phase phase :causes causes)
   :elapsed-internal-time 0))


(defun link-collection-segments (head head-last tail tail-last)
   (cond
     ((null head) (values tail tail-last))
     ((null tail) (values head head-last))
     (t
      (setf (cdr head-last) tail)
      (values head tail-last))))

(defun continue-with-linked-segments (continue head head-last tail tail-last)
  (multiple-value-call continue
    (link-collection-segments head head-last tail tail-last)))
 (defun collect-suite-events/k
    (suite control continue filter
     &optional ancestor-focused suppressed-status suppressed-reason
       inherited-execution-mode)
  (if (or (execution-control-stopped control)
          (not (selected-suite-p suite filter ancestor-focused)))
      (funcall continue nil nil)
      (let ((active-execution-mode
              (effective-suite-execution-mode suite inherited-execution-mode)))
        (multiple-value-bind (active-status active-reason)
            (suite-suppression suite suppressed-status suppressed-reason)
          (if active-status
              (collect-children/k suite
                                  (ordered-children suite (suite-children suite))
                                  control continue filter ancestor-focused
                                  active-status active-reason active-execution-mode)
              (let ((before-errors
                      (call-hooks/collect-errors (suite-hook suite before-all)))
                    (after-called-p nil)
                    (after-errors nil))
                (labels ((run-after-hooks ()
                           (unless after-called-p
                             (setf after-called-p t
                                   after-errors
                                   (call-hooks/collect-errors
                                    (reverse (suite-hook suite after-all)))))
                           after-errors)
                         (finish (events events-last)
                           (let* ((after-errors (run-after-hooks))
                                  (before-events
                                    (when before-errors
                                      (list (record-event/control
                                             control
                                             (make-suite-hook-event
                                              suite :before-all before-errors)))))
                                  (after-events
                                    (when after-errors
                                      (list (record-event/control
                                             control
                                             (make-suite-hook-event
                                              suite :after-all after-errors))))))
                             (multiple-value-bind (with-before with-before-last)
                                 (link-collection-segments
                                  before-events before-events events events-last)
                               (continue-with-linked-segments
                                continue with-before with-before-last
                                after-events after-events)))))
                  (unwind-protect
                       (if before-errors
                           (finish nil nil)
                           (collect-children/k
                            suite
                            (ordered-children suite (suite-children suite))
                            control (function finish) filter ancestor-focused
                            nil nil active-execution-mode))
                    (run-after-hooks)))))))))



(defun collect-children/k
    (suite children control continue filter
     &optional ancestor-focused suppressed-status suppressed-reason
       execution-mode)
  (macrolet ((recur (remaining next-continue)
  `(collect-children/k
    suite
    ,remaining
    control
    ,next-continue
    filter
    ancestor-focused
    suppressed-status
    suppressed-reason
    execution-mode)))
    (labels ((continue-with-tail
                 (head-events head-last remaining)
               (recur remaining
                      (lambda (tail tail-last)
                        (continue-with-linked-segments
                         continue head-events head-last tail tail-last))))
             (continue-with-event (event)
               (let ((events (list event)))
                 (if (execution-control-stopped control)
                     (funcall continue events events)
                     (recur (rest children)
                            (lambda (tail tail-last)
                              (continue-with-linked-segments
                               continue events events tail tail-last)))))))
      (if (or (null children) (execution-control-stopped control))
          (funcall continue nil nil)
          (let ((child (first children)))
            (multiple-value-bind (step payload rest-children)
                (describe-event-collection-step
                 suite
                 child
                 children
                 control
                 filter
                 ancestor-focused
                 suppressed-status
                 suppressed-reason
                 execution-mode)
              (ecase step
                (:skip
                 (recur (rest children) continue))
                (:collect-suite
                 (collect-suite-events/k
                  child
                  control
                  (lambda (events events-last)
                    (if (execution-control-stopped control)
                        (funcall continue events events-last)
                        (continue-with-tail
                         events events-last (rest children))))
                  filter
                  payload
                  suppressed-status
                  suppressed-reason
                  execution-mode))
                (:collect-concurrent
                 (let ((events
                         (mapcar (lambda (event)
                                   (record-event/control control event))
                                 (run-concurrent-test-cases suite payload))))
                   (continue-with-tail
                    events (last events) rest-children)))
                (:collect-test
                 (continue-with-event payload)))))))))



(defstruct collection-options
  name-filter
  location-filter
  test-path-filter
  include-tags
  exclude-tags
  bail
  shard
  order
  seed
  retry
  timeout-ms
  max-workers)

(defun normalize-collection-options
    (&key name-filter location-filter test-path-filter
          include-tags exclude-tags bail shard order seed
          retry timeout-ms max-workers)
  (make-collection-options
   :name-filter
   (and name-filter (normalized-test-filter name-filter))
   :location-filter
   (and location-filter (normalize-location-filter location-filter))
   :test-path-filter
   (and test-path-filter (normalize-test-path-filter test-path-filter))
   :include-tags
   (and include-tags (normalize-tags include-tags "include-tags"))
   :exclude-tags
   (and exclude-tags (normalize-tags exclude-tags "exclude-tags"))
   :bail (and bail (normalize-bail bail))
   :shard (and shard (normalize-shard shard))
   :order (if order (normalize-sequence-order order) :defined)
   :seed (if seed (normalize-sequence-seed seed) 0)
   :retry (if retry (normalize-retry-count retry) 0)
   :timeout-ms (and timeout-ms (normalize-timeout-ms timeout-ms))
   :max-workers (and max-workers (normalize-max-workers max-workers))))

(defun call-with-collection-context (suite options continue)
  (let* ((location-filter
           (collection-options-location-filter options))
         (location-filter-index
           (when location-filter
             (let ((index
                     (make-hash-table
                      :test #'equal
                      :size (length location-filter))))
               (dolist (pathname location-filter index)
                 (setf (gethash pathname index) t)))))
         (test-path-filter
           (collection-options-test-path-filter options))
         (test-path-index
           (when test-path-filter
             (let ((index
                     (make-hash-table
                      :test #'equal
                      :size (length test-path-filter))))
               (dolist (path test-path-filter index)
                 (setf (gethash path index) t))))))
    (multiple-value-bind (focus-enabled focus-index)
        (build-focus-index suite)
      (let ((filter
              (make-selection-filter
               :focus-enabled focus-enabled
               :focus-index focus-index
               :name-filter (collection-options-name-filter options)
               :location-filter location-filter
               :location-filter-index location-filter-index
               :test-path-filter test-path-filter
               :test-path-index test-path-index
               :include-tags (collection-options-include-tags options)
               :exclude-tags (collection-options-exclude-tags options))))
        (multiple-value-bind (selected-tests selected-suites test-paths)
            (collect-selection-indexes
             suite filter (collection-options-shard options))
          (setf (selection-filter-test-paths filter) test-paths
                (selection-filter-selected-tests filter) selected-tests
                (selection-filter-selected-suites filter) selected-suites))
        (let ((*collection-test-paths*
                (selection-filter-test-paths filter))
              (*test-sequence-order* (collection-options-order options))
              (*test-sequence-seed* (collection-options-seed options))
              (*default-retry* (collection-options-retry options))
              (*default-timeout-ms* (collection-options-timeout-ms options))
              (*max-workers* (collection-options-max-workers options)))
          (funcall continue filter))))))

(defparameter +default-strict-empty-collection-null-accessors+
  (list (function collection-options-name-filter)
        (function collection-options-location-filter)
        (function collection-options-test-path-filter)
        (function collection-options-include-tags)
        (function collection-options-exclude-tags)
        (function collection-options-bail)
        (function collection-options-shard)
        (function collection-options-timeout-ms)
        (function collection-options-max-workers))
  "Collection-options accessors that must all return NIL, alongside the
default :order/:seed/:retry values, for the options to qualify for the
strict-empty collection fast path.")

(defun default-strict-empty-collection-options-p (options)
  (and (every (lambda (accessor) (null (funcall accessor options)))
              +default-strict-empty-collection-null-accessors+)
       (eq (collection-options-order options) :defined)
       (eql (collection-options-seed options) 0)
       (eql (collection-options-retry options) 0)))

(defparameter +strict-empty-lineage-null-accessors+
  (list (function suite-focus) (function suite-skip-reason)
        (function suite-todo-reason) (function suite-execution-mode)
        (function suite-before-each) (function suite-around-each)
        (function suite-after-each))
  "Suite accessors that must all return NIL, for every suite in a lineage,
for the lineage to qualify for the strict-empty collection fast path.")

(defun strict-empty-lineage-eligible-p (lineage)
  (every
   (lambda (current)
     (every (lambda (accessor) (null (funcall accessor current)))
            +strict-empty-lineage-null-accessors+))
   lineage))

(defparameter +strict-empty-test-null-accessors+
  (list (function test-case-focus) (function test-case-skip-reason)
        (function test-case-todo-reason) (function test-case-retry)
        (function test-case-timeout-ms) (function test-case-execution-mode)
        (function test-case-expected-failure-reason)
        (function test-case-watch-dependencies))
  "Test-case accessors that must all return NIL for a test to qualify for
the strict-empty collection fast path.")

(defun strict-empty-test-eligible-p (test)
  (and (test-case-p test)
       (every (lambda (accessor) (null (funcall accessor test)))
              +strict-empty-test-null-accessors+)
       (let ((marker (test-case-trusted-empty-function test)))
         (and marker
              (eq marker (test-case-function test))))))

(defun strict-empty-batch-eligible-p
    (suite &optional (lineage (suite-lineage suite)))
  (and (null (suite-before-all suite))
       (null (suite-after-all suite))
       (strict-empty-lineage-eligible-p lineage)
       (every #'strict-empty-test-eligible-p
              (suite-children suite))))

(defun collect-strict-empty-batch-events
    (suite &optional (lineage (suite-lineage suite)))
  (let ((path-prefix
          (mapcar #'suite-name (rest lineage))))
    (loop for test in (suite-children suite)
          collect
          (make-pass-event-with-path
           test
           (append path-prefix
                   (list (test-case-name test)))
           (get-internal-real-time)))))

(defun try-collect-strict-empty-batch-events (suite options)
  (if (default-strict-empty-collection-options-p options)
      (let ((lineage (suite-lineage suite)))
        (if (strict-empty-batch-eligible-p suite lineage)
            (values
             (collect-strict-empty-batch-events suite lineage)
             t)
            (values nil nil)))
      (values nil nil)))

(defun collect-events-with-options (suite options)
  (let ((suite (snapshot-suite suite)))
    (with-runner-condition-propagation (nil)
      (multiple-value-bind (events collected-p)
          (try-collect-strict-empty-batch-events suite options)
        (if collected-p
            events
            (call-with-collection-context
             suite
             options
             (lambda (filter)
               (collect-suite-events/k
                suite
                (make-execution-control
                 :bail-limit
                 (if (eq (collection-options-bail options) t)
                     1
                     (collection-options-bail options)))
                (lambda (events events-last)
                  (declare (ignore events-last))
                  events)
                filter))))))))

(defun collect-events
    (suite &key name-filter location-filter test-path-filter
                include-tags exclude-tags bail shard order seed
                retry timeout-ms max-workers)
  (collect-events-with-options
   suite
   (normalize-collection-options
    :name-filter name-filter
    :location-filter location-filter
    :test-path-filter test-path-filter
    :include-tags include-tags
    :exclude-tags exclude-tags
    :bail bail
    :shard shard
    :order order
    :seed seed
    :retry retry
    :timeout-ms timeout-ms
    :max-workers max-workers)))



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
