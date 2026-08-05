(in-package #:cl-weave)

(defun make-logic-rule (&key head (body nil))
  (vector 'logic-rule head body))

(defun logic-rule-p (value)
  (and (simple-vector-p value)
       (= (length value) 3)
       (eq (svref value 0) 'logic-rule)))

(defun logic-rule-head (rule)
  (svref rule 1))

(defun logic-rule-body (rule)
  (svref rule 2))

(defun logic-variable-p (value)
  (and (symbolp value)
       (< 0 (length (symbol-name value)))
       (char= #\? (char (symbol-name value) 0))))

(defun logic-binding-value (variable bindings)
  (let ((binding (assoc variable bindings)))
    (if binding
        (values (cdr binding) t)
        (values nil nil))))

(defun logic-walk (value bindings &optional seen)
  (let ((current value)
        (visited (make-hash-table :test (function eq))))
    (dolist (variable seen)
      (setf (gethash variable visited) t))
    (loop
      (unless (logic-variable-p current)
        (return current))
      (when (gethash current visited)
        (return current))
      (setf (gethash current visited) t)
      (multiple-value-bind (bound found-p)
          (logic-binding-value current bindings)
        (unless found-p
          (return current))
        (setf current bound)))))

(defun reject-cyclic-logic-value ()
  (error "cl-weave: cyclic logic value is not supported."))

(defun ensure-acyclic-logic-value (value bindings)
  (let ((active (make-hash-table :test (function eq)))
        (stack (list (cons :visit value))))
    (loop while stack
          for frame = (pop stack)
          do (if (eq (car frame) :leave)
                 (remhash (cdr frame) active)
                 (let ((part (logic-walk (cdr frame) bindings)))
                   (when (consp part)
                     (when (gethash part active)
                       (reject-cyclic-logic-value))
                     (setf (gethash part active) t)
                     (push (cons :leave part) stack)
                     (push (cons :visit (cdr part)) stack)
                     (push (cons :visit (car part)) stack)))))
    value))

(defun extend-logic-binding (variable value bindings)
  (acons variable value bindings))

(defun logic-occurs-in-p (variable value bindings)
  (ensure-acyclic-logic-value value bindings)
  (let ((stack (list value)))
    (loop while stack
          for part = (logic-walk (pop stack) bindings)
          do (cond
               ((eql variable part)
                (return-from logic-occurs-in-p t))
               ((consp part)
                (push (cdr part) stack)
                (push (car part) stack))))
    nil))

(defun unify-logic-values (left right bindings)
  (ensure-acyclic-logic-value left bindings)
  (ensure-acyclic-logic-value right bindings)
  (let ((pending (list (cons left right)))
        (current-bindings bindings))
    (loop while pending
          for pair = (pop pending)
          for resolved-left = (logic-walk (car pair) current-bindings)
          for resolved-right = (logic-walk (cdr pair) current-bindings)
          do (cond
               ((and (consp resolved-left) (consp resolved-right))
                (push (cons (cdr resolved-left) (cdr resolved-right)) pending)
                (push (cons (car resolved-left) (car resolved-right)) pending))
               ((logic-variable-p resolved-left)
                (if (logic-occurs-in-p resolved-left resolved-right current-bindings)
                    (return-from unify-logic-values (values nil nil))
                    (setf current-bindings
                          (extend-logic-binding resolved-left
                                                resolved-right
                                                current-bindings))))
               ((logic-variable-p resolved-right)
                (if (logic-occurs-in-p resolved-right resolved-left current-bindings)
                    (return-from unify-logic-values (values nil nil))
                    (setf current-bindings
                          (extend-logic-binding resolved-right
                                                resolved-left
                                                current-bindings))))
               ((not (equal resolved-left resolved-right))
                (return-from unify-logic-values (values nil nil)))))
    (values current-bindings t)))

(defun rebuild-logic-cons-structure (value transform-part)
  "Iteratively rebuild the cons structure of VALUE without recursing, so an
arbitrarily long proper list does not consume call stack. Each part
encountered -- starting with VALUE itself -- is passed through
TRANSFORM-PART first; a consp result is decomposed and its car/cdr walked
the same way, and anything else becomes a leaf of the rebuilt structure.
RESOLVE-LOGIC-VALUE and INSTANTIATE-LOGIC-TERM share this shape and differ
only in what TRANSFORM-PART does with a raw part."
  (let ((pending (list (cons :visit value)))
        (rebuilt '()))
    (loop while pending
          for frame = (pop pending)
          do (if (eq frame :combine)
                 (let ((right (pop rebuilt))
                       (left (pop rebuilt)))
                   (push (cons left right) rebuilt))
                 (let ((part (funcall transform-part (cdr frame))))
                   (if (consp part)
                       (progn
                         (push :combine pending)
                         (push (cons :visit (cdr part)) pending)
                         (push (cons :visit (car part)) pending))
                       (push part rebuilt)))))
    (pop rebuilt)))

(defun resolve-logic-value (value bindings)
  (ensure-acyclic-logic-value value bindings)
  (rebuild-logic-cons-structure
   value
   (lambda (part) (logic-walk part bindings))))

(defun normalize-logic-bindings (bindings)
  (nreverse
   (mapcar (lambda (binding)
             (cons (car binding)
                   (resolve-logic-value (cdr binding) bindings)))
           bindings)))

(defun collect-logic-variables (value)
  (ensure-acyclic-logic-value value nil)
  (let ((pending (list value))
        (variables (quote ())))
    (loop while pending
          for part = (pop pending)
          do (cond
               ((logic-variable-p part)
                (push part variables))
               ((consp part)
                (push (cdr part) pending)
                (push (car part) pending))))
    (nreverse variables)))

(defun project-logic-bindings (bindings variables)
  (let ((normalized (normalize-logic-bindings bindings)))
    (loop for variable in variables
          for binding = (assoc variable normalized)
          when binding
            collect binding)))

(defun logic-rule-indicator-p (value)
  (eq value :-))

(defun logic-rule-form-p (form)
  (and (consp form)
       (logic-rule-indicator-p (first form))))

(defun normalize-logic-rule-form (form)
  (unless (and (consp form) (consp (rest form)))
    (error "cl-weave: logic rule requires a head and optional body, got ~S." form))
  (make-logic-rule :head (second form)
                   :body (cddr form)))

(defun normalize-logic-program (program)
  (let ((normalized '()))
    (dolist (entry program (nreverse normalized))
      (push (if (logic-rule-form-p entry)
                (normalize-logic-rule-form entry)
                entry)
            normalized))))

(defun fresh-logic-variable (variable rule-id)
  (make-symbol (format nil "~A/~D" (symbol-name variable) rule-id)))

(defun instantiate-logic-term (term mapping rule-id)
  (ensure-acyclic-logic-value term nil)
  (rebuild-logic-cons-structure
   term
   (lambda (part)
     (if (logic-variable-p part)
         (multiple-value-bind (renamed present-p)
             (gethash part mapping)
           (if present-p
               renamed
               (let ((fresh (fresh-logic-variable part rule-id)))
                 (setf (gethash part mapping) fresh)
                 fresh)))
         part))))

(defun instantiate-logic-rule (rule rule-id)
  (let ((mapping (make-hash-table :test #'eq)))
    (make-logic-rule
     :head (instantiate-logic-term (logic-rule-head rule) mapping rule-id)
     :body (let ((instantiated '()))
             (dolist (goal (logic-rule-body rule) (nreverse instantiated))
               (push (instantiate-logic-term goal mapping rule-id)
                     instantiated))))))

(defun logic-entry-head (entry)
  (if (logic-rule-p entry)
      (logic-rule-head entry)
      entry))

(defun logic-entry-body (entry)
  (if (logic-rule-p entry)
      (logic-rule-body entry)
      '()))

(defun logic-below-limit-p (results limit)
  (or (null limit) (< (length results) limit)))

(defun remove-duplicate-logic-variables (variables)
  (let ((unique '()))
    (dolist (variable variables (nreverse unique))
      (unless (member variable unique :test #'eq)
        (push variable unique)))))

(defun make-logic-search-frame (pending bindings)
  (list pending bindings))

(defun logic-search-frame-pending (frame)
  (first frame))

(defun logic-search-frame-bindings (frame)
  (second frame))

(define-condition logic-search-exhausted (error)
  ((steps :initarg :steps :reader logic-search-exhausted-steps)
   (limit :initarg :limit :reader logic-search-exhausted-limit)
   (pending :initarg :pending :reader logic-search-exhausted-pending)
   (partial-results :initarg :partial-results
                    :reader logic-search-exhausted-partial-results))
  (:report (lambda (condition stream)
             (format stream
                     "cl-weave: logic query exhausted its ~D step limit with ~D frames pending."
                     (logic-search-exhausted-limit condition)
                     (logic-search-exhausted-pending condition)))))

(defun validate-logic-query-bound (name value)
  (unless (or (null value)
              (and (integerp value) (plusp value)))
    (error "cl-weave: ~A must be NIL or a positive integer, got ~S."
           name value)))

(defun logic-query (program clauses &key limit max-steps)
  (validate-logic-query-bound "logic-query limit" limit)
  (validate-logic-query-bound "logic-query max-steps" max-steps)
  (ensure-acyclic-logic-value program nil)
  (let ((normalized-program (normalize-logic-program program))
        (query-variables
          (remove-duplicate-logic-variables (collect-logic-variables clauses)))
        (frames (list (make-logic-search-frame clauses nil)))
        (results nil)
        (steps 0)
        (next-rule-id 0))
    (block search
      (labels ((enforce-logic-search-step-limit ()
                 (when (and max-steps (>= steps max-steps))
                   (restart-case
                       (error 'logic-search-exhausted
                              :steps steps
                              :limit max-steps
                              :pending (length frames)
                              :partial-results (reverse results))
                     (return-partial-results ()
                       :report "Return the results found before the step budget was exhausted."
                       (return-from search (nreverse results)))
                     (increase-limit (new-limit)
                       :report "Continue the logic query with a larger step limit."
                       (unless (and (integerp new-limit) (> new-limit steps))
                         (error "cl-weave: increased logic step limit must exceed ~D, got ~S."
                                steps new-limit))
                       (setf max-steps new-limit)))))
               (match-logic-search-candidate (candidate goal rest-goals bindings)
                 (let* ((rule-p (logic-rule-p candidate))
                        (rule-id next-rule-id)
                        (instantiated (if rule-p
                                           (instantiate-logic-rule candidate rule-id)
                                           candidate))
                        (head (logic-entry-head instantiated))
                        (body (logic-entry-body instantiated)))
                   (when rule-p
                     (incf next-rule-id))
                   (multiple-value-bind (next-bindings matched-p)
                       (unify-logic-values goal head bindings)
                     (when matched-p
                       (make-logic-search-frame (append body rest-goals) next-bindings)))))
               (expand-logic-search-frame (frame)
                 (let ((pending (logic-search-frame-pending frame))
                       (bindings (logic-search-frame-bindings frame)))
                   (if (null pending)
                       (push (project-logic-bindings bindings query-variables) results)
                       (let* ((goal (first pending))
                              (rest-goals (rest pending))
                              (matched-frames
                                (loop for candidate in normalized-program
                                      for new-frame = (match-logic-search-candidate
                                                        candidate goal rest-goals bindings)
                                      when new-frame collect new-frame)))
                         (setf frames (append matched-frames frames)))))))
        (loop while (and frames (logic-below-limit-p results limit))
              do (enforce-logic-search-step-limit)
                 (incf steps)
                 (expand-logic-search-frame (pop frames)))
        (nreverse results)))))

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
