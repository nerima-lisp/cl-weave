(in-package #:cl-weave)

(defparameter *logic-where-option-keywords* '(:limit :max-steps)
  "Recognized leading option keywords in a logic-where/logic-run/
test-plan-where/journal-where clause list, consumed by
SPLIT-LOGIC-WHERE-FORMS before the relation clauses begin.")

(defun split-logic-where-forms (forms)
  (let ((limit nil)
        (limit-present-p nil)
        (max-steps nil)
        (max-steps-present-p nil)
        (clauses forms))
    (loop while (and clauses
                     (consp (first clauses))
                     (member (first (first clauses)) *logic-where-option-keywords*))
          for option = (pop clauses)
          do (unless (= 2 (length option))
               (error "cl-weave: ~S expects exactly one value, got ~S."
                      (first option) option))
             (ecase (first option)
               (:limit
                (when limit-present-p
                  (error "cl-weave: duplicate :limit logic option."))
                (setf limit (second option)
                      limit-present-p t))
               (:max-steps
                (when max-steps-present-p
                  (error "cl-weave: duplicate :max-steps logic option."))
                (setf max-steps (second option)
                      max-steps-present-p t))))
    (unless clauses
      (error "cl-weave: logic where macros require at least one relation clause."))
    (dolist (clause clauses)
      (validate-logic-clause clause))
    (values clauses limit limit-present-p max-steps max-steps-present-p)))

(defun build-logic-query-form (operator program forms)
  (multiple-value-bind (clauses limit limit-present-p max-steps max-steps-present-p)
      (split-logic-where-forms forms)
    `(,operator ,program ',clauses
                ,@(when limit-present-p `(:limit ,limit))
                ,@(when max-steps-present-p `(:max-steps ,max-steps)))))

(defmacro define-logic-query-macro (name operator)
  `(defmacro ,name (program &body forms)
     (build-logic-query-form ',operator program forms)))

(defmacro define-logic-query-family (&rest specifications)
  `(progn
     ,@(loop for (name operator) in specifications
             collect `(define-logic-query-macro ,name ,operator))))

(defun validate-logic-clause (clause)
  (unless (and (consp clause) (keywordp (first clause)))
    (error "cl-weave: logic clauses must be non-empty keyword relation lists, got ~S."
           clause)))

(defun test-plan-entry-fact (path relation value)
  (list relation path value))

(defun test-plan-entry-flag-fact (path relation)
  (list relation path))

(defmacro logic-program (&body entries)
  `(list ,@(mapcar (lambda (entry) `',entry) entries)))

(define-logic-query-family
    (logic-where logic-query)
    (logic-run logic-query)
    (test-plan-where query-test-plan)
    (journal-where query-journal))

(defun test-plan-entry-facts (entry)
  (let* ((path (test-plan-entry-path entry))
         (status (test-plan-entry-status entry))
         (retry (test-plan-entry-retry entry))
         (reason (test-plan-entry-reason entry))
         (focused (test-plan-entry-focused entry))
         (timeout-ms (test-plan-entry-timeout-ms entry))
         (concurrent (test-plan-entry-concurrent entry))
         (location (test-plan-entry-location entry)))
    (append (list (test-plan-entry-flag-fact path :test)
                  (test-plan-entry-fact path :status status)
                  (test-plan-entry-fact path :retry retry))
            (when reason
              (list (test-plan-entry-fact path :reason reason)))
            (when focused
              (list (test-plan-entry-flag-fact path :focused)))
            (when timeout-ms
              (list (test-plan-entry-fact path :timeout-ms timeout-ms)))
            (when concurrent
              (list (test-plan-entry-flag-fact path :concurrent)))
            (when location
              (list (test-plan-entry-fact path :location location))))))

(defun test-plan-facts (plan)
  (mapcan #'test-plan-entry-facts plan))

(defun normalize-test-plan-query-input (value)
  (if (and (listp value)
           (every #'test-plan-entry-p value))
      (test-plan-facts value)
      value))

(defun query-test-plan (plan-or-program clauses &key limit max-steps)
  (logic-query (normalize-test-plan-query-input plan-or-program)
               clauses
               :limit limit
               :max-steps max-steps))

(defun journal-frame-facts (frame)
  "Turn one JOURNAL-FRAME into relation facts keyed by its index: (:frame
index), (:kind index kind), (:form index form), (:actual index actual),
(:expected index expected), (:pass index generalized-boolean), and
(:elapsed-internal-time index ticks) always; (:matcher index matcher) only
when the frame has one, mirroring how TEST-PLAN-ENTRY-FACTS omits absent
optional fields."
  (let ((index (journal-frame-index frame))
        (matcher (journal-frame-matcher frame)))
    (append (list (list :frame index)
                  (list :kind index (journal-frame-kind frame))
                  (list :form index (journal-frame-form frame))
                  (list :actual index (journal-frame-actual frame))
                  (list :expected index (journal-frame-expected frame))
                  (list :pass index (and (journal-frame-pass frame) t))
                  (list :elapsed-internal-time index
                        (journal-frame-elapsed-internal-time frame)))
            (when matcher
              (list (list :matcher index matcher))))))

(defun journal-facts (frames)
  "Turn a list of JOURNAL-FRAMEs (as returned by REPLAY-TEST, a TEST-EVENT's
journal, or WITH-EXECUTION-JOURNAL) into a flat relation program, ready for
LOGIC-QUERY, LOGIC-RUN, or JOURNAL-WHERE."
  (mapcan #'journal-frame-facts frames))

(defun normalize-journal-query-input (value)
  (if (and (listp value) (every #'journal-frame-p value))
      (journal-facts value)
      value))

(defun query-journal (frames-or-program clauses &key limit max-steps)
  "Query a time-travel timeline declaratively. FRAMES-OR-PROGRAM is either a
list of JOURNAL-FRAMEs or an already-expanded fact program, so derived views
can layer on top of JOURNAL-FACTS the same way QUERY-TEST-PLAN layers on
TEST-PLAN-FACTS -- for example a rule finding the first failing assertion
after a passing shrink step, expressed as relations instead of a hand-rolled
timeline walk."
  (logic-query (normalize-journal-query-input frames-or-program)
               clauses
               :limit limit
               :max-steps max-steps))
