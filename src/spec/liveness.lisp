(in-package #:cl-weave/spec)

(defun liveness-edges (graph state)
  (state-table-ref (state-graph-edges graph) state))

(defun liveness-step (transition state)
  (if transition
      (make-trace-step :action (spec-transition-action transition)
                       :params (spec-transition-params transition)
                       :state (spec-transition-to transition))
      (make-trace-step :state state)))

(defun liveness-enabled-mask (graph state conditions)
  (loop with mask = 0
        for condition in conditions for index from 0
        when (some (lambda (edge)
                     (and (eq (spec-fairness-condition-action condition)
                              (spec-transition-action edge))
                          (not (equal state (spec-transition-to edge)))))
                   (liveness-edges graph state))
          do (setf mask (logior mask (ash 1 index)))
        finally (return mask)))

(defun liveness-taken-mask (edge conditions)
  (if (and edge (not (equal (spec-transition-from edge)
                            (spec-transition-to edge))))
      (loop with mask = 0
            for condition in conditions for index from 0
            when (eq (spec-fairness-condition-action condition)
                     (spec-transition-action edge))
              do (setf mask (logior mask (ash 1 index)))
            finally (return mask))
      0))

(defun liveness-fair-cycle-p (conditions enabled disabled taken)
  (loop for condition in conditions for index from 0
        for bit = (ash 1 index)
        always (or (not (zerop (logand bit taken)))
                   (ecase (spec-fairness-condition-kind condition)
                     (:weak (not (zerop (logand bit disabled))))
                     (:strong (zerop (logand bit enabled)))))))

(defun liveness-cycle (graph anchor property conditions)
  ;; Product states retain the facts needed to evaluate a repeated walk.
  (let* ((kind (spec-temporal-property-kind property))
         (predicate (spec-temporal-property-predicate property))
         (consequent (spec-temporal-property-consequent property))
         (all-bits (1- (ash 1 (length conditions))))
         (queue (make-array 16 :adjustable t :fill-pointer 0))
         (seen (make-state-table)))
    (vector-push-extend (list anchor 0 0 0 nil nil) queue)
    (setf (state-table-ref seen (list anchor 0 0 0 nil)) t)
    (loop for position from 0 while (< position (length queue)) for (state enabled disabled taken bad path) = (aref queue position)
          for state-enabled = (liveness-enabled-mask graph state conditions)
          for new-enabled = (logior enabled state-enabled)
          for new-disabled = (logior disabled (logandc2 all-bits state-enabled))
          for new-bad = (or bad (not (funcall predicate state)))
          do (dolist (edge (cons nil (liveness-edges graph state)))
               (let* ((next (if edge (spec-transition-to edge) state))
                      (new-taken (logior taken (liveness-taken-mask edge conditions)))
                      (new-path (cons (liveness-step edge state) path)))
                 (when (and (or (not (member kind '(:eventually :infinitely-often)))
                                (not (funcall predicate next)))
                            (or (not (eq kind :leads-to))
                                (not (funcall consequent next))))
                   (when (and (equal next anchor)
                              (or (not (eq kind :eventually-always)) new-bad)
                              (liveness-fair-cycle-p conditions new-enabled
                                                     new-disabled new-taken))
                     (return-from liveness-cycle (nreverse new-path)))
                   (let ((key (list next new-enabled new-disabled new-taken new-bad)))
                     (unless (nth-value 1 (state-table-ref seen key))
                       (setf (state-table-ref seen key) t)
                       (vector-push-extend
                        (list next new-enabled new-disabled new-taken new-bad new-path)
                        queue)))))))
    nil))

(defun liveness-counterexample (graph property conditions)
  (let* ((kind (spec-temporal-property-kind property))
         (predicate (spec-temporal-property-predicate property))
         (consequent (spec-temporal-property-consequent property))
         (queue (make-array 16 :adjustable t :fill-pointer 0))
         (seen (make-state-table)))
    (labels ((enqueue (state marked path)
               (let ((key (list state marked)))
                 (unless (nth-value 1 (state-table-ref seen key))
                   (setf (state-table-ref seen key) t)
                   (vector-push-extend (list state marked path) queue)))))
      (dolist (state (state-graph-initial-states graph))
        (unless (and (eq kind :eventually) (funcall predicate state))
          (enqueue state
                   (case kind
                     (:always (not (funcall predicate state)))
                     (:leads-to (and (funcall predicate state)
                                     (not (funcall consequent state)))))
                   (list (make-trace-step :state state)))))
      (loop for position from 0 while (< position (length queue)) for (state marked path) = (aref queue position)
            do (when (and (or (not (member kind '(:always :leads-to))) marked)
                          (or (not (eq kind :infinitely-often))
                              (not (funcall predicate state))))
                 (let ((cycle (liveness-cycle graph state property conditions)))
                   (when cycle
                     (return-from liveness-counterexample
                       (make-lasso :prefix (reverse path) :cycle cycle)))))
               (dolist (edge (liveness-edges graph state))
                 (let* ((next (spec-transition-to edge))
                        (next-marked
                          (case kind
                            (:always (or marked (not (funcall predicate next))))
                            (:leads-to (or (and marked (not (funcall consequent next)))
                                           (and (funcall predicate next)
                                                (not (funcall consequent next))))))))
                   (unless (and (eq kind :eventually) (funcall predicate next))
                     (enqueue next next-marked (cons (liveness-step edge state) path)))))))
    nil))

(defun check-temporal-properties (spec graph &key (properties :all))
  (unless (state-graph-complete-p graph)
    (signal-spec-error 'spec-configuration-error
                       "Temporal properties require a complete state graph."))
  (loop for property in (spec-temporal-properties spec)
        for trace = (when (or (eq properties :all)
                              (member (spec-temporal-property-name property) properties))
                      (liveness-counterexample graph property
                                               (spec-fairness-conditions spec)))
        when trace
          collect (make-spec-violation :kind :temporal
                                       :property (spec-temporal-property-name property)
                                       :trace trace
                                       :detail (list :kind (spec-temporal-property-kind property)))))
