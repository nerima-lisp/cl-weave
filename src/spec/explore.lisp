(in-package #:cl-weave/spec)

(defstruct (explore-node (:constructor make-explore-node (state depth parent transition)))
  state depth parent transition)

(defun explore-node-trace (node)
  (loop for current = node then (explore-node-parent current)
        while current
        for transition = (explore-node-transition current)
        collect (make-trace-step :state (explore-node-state current)
                                 :action (when transition (spec-transition-action transition))
                                 :params (when transition (spec-transition-params transition)))
          into steps
        finally (return (nreverse steps))))

(defun explore-spec (spec &key (max-states *default-max-states*)
                               (max-depth *default-max-depth*) allow-bounded
                               (check-deadlock :spec) (symmetry t) (temporal :all)
                               initial-check step-check)
  (unless (and (integerp max-states) (plusp max-states)
               (integerp max-depth) (plusp max-depth))
    (signal-spec-error 'spec-configuration-error "Search limits must be positive integers."))
  (unless (eq temporal :all)
    (dolist (name temporal)
      (unless (find name (spec-temporal-properties spec) :key (function spec-temporal-property-name))
        (signal-spec-error (quote spec-configuration-error)
                           "Unknown temporal property ~S." name))))
  (let* ((properties (if (eq temporal :all)
                         (mapcar #'spec-temporal-property-name (spec-temporal-properties spec))
                         temporal))
         (canonicalizer (when symmetry (spec-state-canonicalizer spec)))
         (deadlock-p (if (eq check-deadlock :spec)
                         (spec-check-deadlock spec) check-deadlock)))
    (when (and canonicalizer properties)
      (signal-spec-error 'spec-configuration-error
                         "Symmetry and temporal properties cannot be checked together."))
    (let* ((initial-states (spec-initial-states spec))
           (visited (make-state-table))
           (graph (when properties
                    (make-state-graph :spec spec :initial-states initial-states)))
           (queue (list nil))
           (tail queue)
           (states-found 0)
           (depth-reached 0)
           (transitions-count 0)
           (truncation nil)
           (checked-depth -1)
           (invariants-checked nil)
           (actions-checked nil)
           (temporal-checked nil)
           (deadlock-checked nil))
      (labels ((key (state) (if canonicalizer (funcall canonicalizer state) state))
               (enqueue (node)
                 (setf (cdr tail) (list node) tail (cdr tail)))
               (result (&optional violation)
                 (make-spec-result :spec-name (spec-name spec) :mode :exhaustive
                                   :violation violation :states-found states-found
                                   :depth-reached depth-reached
                                   :truncated (not (null truncation))
                                   :truncation-reason truncation
                                   :liveness-requested properties :allow-bounded allow-bounded
                                   :checked-properties
                                   (append (when invariants-checked
                                             (mapcar (function spec-invariant-name) (spec-invariants spec)))
                                           (when actions-checked
                                             (mapcar (function spec-action-property-name)
                                                     (spec-action-properties spec)))
                                           (when temporal-checked
                                             (loop for property in (spec-temporal-properties spec)
                                                   for name = (spec-temporal-property-name property)
                                                   when (member name properties) collect name))
                                           (when deadlock-checked (list :deadlock)))
                                   :limits (list :max-states max-states :max-depth max-depth)
                                   :statistics (list :transitions transitions-count
                                                     :initial-states (length initial-states))))
               (fail (violation node)
                 (setf (spec-violation-trace violation) (explore-node-trace node))
                 (return-from explore-spec (result violation)))
               (check-state (node initial-p)
                 (setf invariants-checked t)
                 (let* ((state (explore-node-state node))
                        (violation (first (spec-check-invariants spec state))))
                   (when violation
                     (fail (make-spec-violation :kind :invariant :property violation
                                                :detail (list :state state)) node))
                   (when initial-p
                     (let ((extra (and initial-check (funcall initial-check state))))
                       (when extra (fail extra node))))))
               (discover (node initial-p)
                 (let* ((state (explore-node-state node))
                        (state-key (key state)))
                   (unless (nth-value 1 (state-table-ref visited state-key))
                     (if (= states-found max-states)
                         (progn (check-state node initial-p)
                                (setf truncation :max-states))
                         (progn
                           (setf (state-table-ref visited state-key) node)
                           (incf states-found)
                           (setf depth-reached (max depth-reached (explore-node-depth node)))
                           (check-state node initial-p)
                           (enqueue node)))))))
        (dolist (state initial-states)
          (discover (make-explore-node state 0 nil nil) t)
          (when truncation (return-from explore-spec (result))))
        (loop while (cdr queue)
              for node = (pop (cdr queue))
              for state = (explore-node-state node)
              for depth = (explore-node-depth node)
              do (when (null (cdr queue)) (setf tail queue))
                 (unless (= depth checked-depth)
                   (setf checked-depth depth)
                   (when deadlock-p (setf deadlock-checked t))
                   ;; Check this level before finding violations one step deeper.
                   (dolist (peer (cons node (loop for next in (cdr queue)
                                                 while (= (explore-node-depth next) depth)
                                                 collect next)))
                     (let* ((peer-state (explore-node-state peer))
                            (blocked (spec-deadlock-p spec peer-state)))
                       (when (and blocked deadlock-p)
                         (fail (make-spec-violation :kind :deadlock
                                                    :detail (list :state peer-state)) peer))
                       (when (and (= depth max-depth) (not blocked) (null truncation))
                         (setf truncation :max-depth)))))
                 (unless (= depth max-depth)
                     (let ((transitions (spec-successors spec state)))
                       (incf transitions-count (length transitions))
                       (when graph (setf (state-table-ref (state-graph-edges graph) state) transitions))
                       (dolist (transition transitions)
                         (let* ((next (spec-transition-to transition))
                                (child (make-explore-node next (1+ depth) node transition))
                                (property (progn
                                            (unless (equal state next) (setf actions-checked t))
                                            (first (spec-check-action-properties spec state next)))))
                           (when property
                             (fail (make-spec-violation
                                    :kind :action-property :property property
                                    :detail (list :from state :to next
                                                  :action (spec-transition-action transition)
                                                  :params (spec-transition-params transition))) child))
                           (let ((extra (and step-check (funcall step-check transition))))
                             (when extra (fail extra child)))
                           (discover child nil)
                           (when (eq truncation :max-states)
                             (return-from explore-spec (result))))))))
        (when (and graph (null truncation))
          (setf (state-graph-complete-p graph) t
                temporal-checked t)
          (let ((violation (first (check-temporal-properties spec graph :properties properties))))
            (when violation (return-from explore-spec (result violation)))))
        (result)))))
