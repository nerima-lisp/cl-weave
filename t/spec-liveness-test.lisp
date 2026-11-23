(in-package #:cl-weave/spec-test)

(defun liveness-graph (spec &optional (complete-p t))
  (let* ((initial (spec-initial-states spec))
         (edges (make-state-table))
         (queue (copy-list initial)))
    (loop while queue
          for state = (pop queue)
          unless (nth-value 1 (state-table-ref edges state))
            do (let ((transitions (spec-successors spec state)))
                 (setf (state-table-ref edges state) transitions)
                 (dolist (transition transitions)
                   (push (spec-transition-to transition) queue))))
    (make-state-graph :spec spec :initial-states initial :edges edges
                      :complete-p complete-p)))

(defun valid-liveness-step-p (graph from step)
  (let ((to (trace-step-state step)))
    (if (null (trace-step-action step))
        (and (null (trace-step-params step)) (equal from to))
        (some (lambda (edge)
                (and (eq (spec-transition-action edge) (trace-step-action step))
                     (equal (spec-transition-params edge) (trace-step-params step))
                     (equal (spec-transition-to edge) to)))
              (state-table-ref (state-graph-edges graph) from)))))

(defun valid-liveness-lasso-p (graph lasso)
  (let* ((prefix (lasso-prefix lasso))
         (cycle (lasso-cycle lasso))
         (first-step (first prefix)))
    (and prefix cycle
         (member (trace-step-state first-step) (state-graph-initial-states graph)
                 :test #'equal)
         (null (trace-step-action first-step))
         (null (trace-step-params first-step))
         (loop for from in prefix for to in (rest prefix)
               always (valid-liveness-step-p graph (trace-step-state from) to))
         (loop with from = (trace-step-state (car (last prefix)))
               for step in cycle
               always (prog1 (valid-liveness-step-p graph from step)
                        (setf from (trace-step-state step))))
         (equal (trace-step-state (car (last cycle)))
                (trace-step-state (car (last prefix)))))))

(defun checked-liveness-violations (spec &key (properties :all))
  (let* ((graph (liveness-graph spec))
         (violations (check-temporal-properties spec graph :properties properties)))
    (dolist (violation violations)
      (expect (spec-violation-kind violation) :to-be :temporal)
      (expect (valid-liveness-lasso-p graph (spec-violation-trace violation)) :to-be t))
    violations))

(defun liveness-toggle-spec (fairness)
  (make-spec :name 'toggle :variables '(x)
             :init (lambda () '((x 0)))
             :actions (list (make-spec-action :name 'toggle
                              :guard (constantly t)
                              :update (lambda (state)
                                        (list 'x (- 1 (state-ref state 'x))))))
             :temporal-properties
             (list (make-spec-temporal-property :name 'reach :kind :eventually
                                               :predicate (lambda (s) (= 1 (state-ref s 'x)))))
             :fairness-conditions
             (when fairness (list (make-spec-fairness-condition :kind fairness :action 'toggle)))))

(defun liveness-intermittent-spec (fairness)
  (make-spec :name 'intermittent :variables '(x)
             :init (lambda () '((x 0)))
             :actions
             (list (make-spec-action :name 'flip
                     :guard (lambda (s) (< (state-ref s 'x) 2))
                     :update (lambda (s) (list 'x (- 1 (state-ref s 'x)))))
                   (make-spec-action :name 'finish
                     :guard (lambda (s) (= (state-ref s 'x) 0))
                     :update (lambda (s) (declare (ignore s)) '(x 2))))
             :temporal-properties
             (list (make-spec-temporal-property :name 'done :kind :eventually
                                               :predicate (lambda (s) (= 2 (state-ref s 'x)))))
             :fairness-conditions
             (list (make-spec-fairness-condition :kind fairness :action 'finish) (make-spec-fairness-condition :kind :weak :action 'flip))))

(describe "spec liveness and fairness"
  (it "rejects an incomplete graph even without properties"
    (let ((spec (counter)))
      (expect (handler-case (progn (check-temporal-properties spec (liveness-graph spec nil)) :no-error)
                (spec-configuration-error () :signalled)) :to-be :signalled)))

  (it "returns no violations for zero temporal properties"
    (let ((spec (counter)))
      (expect (check-temporal-properties spec (liveness-graph spec)) :to-be nil)))

  (it "requires weak fairness to rule out stuttering while toggle stays enabled"
    (let ((violations (checked-liveness-violations (liveness-toggle-spec nil))))
      (expect (mapcar #'spec-violation-property violations) :to-equal '(reach))
      (expect (spec-violation-detail (first violations)) :to-equal '(:kind :eventually)))
    (expect (checked-liveness-violations (liveness-toggle-spec :weak)) :to-be nil))

  (it "distinguishes strong from weak fairness when enablement is intermittent"
    (expect (mapcar #'spec-violation-property
                    (checked-liveness-violations (liveness-intermittent-spec :weak)))
            :to-equal '(done))
    (expect (checked-liveness-violations (liveness-intermittent-spec :strong)) :to-be nil))

  (it "treats a deadlock as an infinite stuttering cycle"
    (let* ((spec (specification stopped () (:variables x) (:init (x 0))
                   (:temporal never-reached (:eventually (= x 1)))))
           (violation (first (checked-liveness-violations spec)))
           (cycle (lasso-cycle (spec-violation-trace violation))))
      (expect (length cycle) :to-be 1)
      (expect (trace-step-action (first cycle)) :to-be nil)
      (expect (trace-step-state (first cycle)) :to-equal '(x 0))))

  (it "does not count an explicit self-loop as a nonstuttering fair action"
    (let ((spec (specification self-loop () (:variables x) (:init (x 0))
                  (:action stay (:next (x x)))
                  (:fairness (:weak stay))
                  (:temporal never-reached (:eventually (= x 1))))))
      (expect (mapcar #'spec-violation-property (checked-liveness-violations spec))
              :to-equal '(never-reached))))

  (it "finds a cycle containing the initial state and respects multiple SCCs"
    (let ((spec (specification components () (:variables x) (:init (x 0))
                  (:action flip (:guard (< x 2)) (:next (x (- 1 x))))
                  (:action exit (:guard (= x 1)) (:next (x 2)))
                  (:fairness (:weak flip))
                  (:temporal reaches-exit (:eventually (= x 2))))))
      (expect (mapcar #'spec-violation-property (checked-liveness-violations spec))
              :to-equal '(reaches-exit))))

  (it "compares always with the invariant across all reachable states"
    (let ((spec (specification invariant-match () (:variables x) (:init (x 0))
                  (:action inc (:guard (< x 2)) (:next (x (1+ x))))
                  (:invariant bounded (< x 2))
                  (:temporal always-bounded (:always (< x 2))))))
      (let* ((graph (liveness-graph spec)) (failed nil))
        (map-state-table (lambda (state edges) (declare (ignore edges))
                           (when (spec-check-invariants spec state) (setf failed t)))
                         (state-graph-edges graph))
        (expect failed :to-be t)
        (expect (mapcar #'spec-violation-property (checked-liveness-violations spec))
                :to-equal '(always-bounded)))))

  (it "applies fairness to all instances of a quantified action together"
    (let ((spec (specification quantified () (:variables x) (:init (x 0))
                  (:action choose (:for (value '(0 1))) (:next (x value)))
                  (:fairness (:weak choose))
                  (:temporal reaches-one (:eventually (= x 1))))))
      (expect (checked-liveness-violations spec) :to-be nil)))

  (it "checks all five temporal forms and honors property selection"
    (let ((spec (specification formulas () (:variables x) (:init (x 0))
                  (:action flip (:next (x (- 1 x))))
                  (:fairness (:weak flip))
                  (:temporal always-zero (:always (= x 0)))
                  (:temporal eventually-one (:eventually (= x 1)))
                  (:temporal often-one (:infinitely-often (= x 1)))
                  (:temporal stays-one (:eventually-always (= x 1)))
                  (:temporal zero-to-one (:leads-to (= x 0) (= x 1))))))
      (expect (mapcar #'spec-violation-property (checked-liveness-violations spec))
              :to-equal '(always-zero stays-one))
      (expect (checked-liveness-violations spec :properties '(eventually-one often-one zero-to-one))
              :to-be nil))))

(describe "spec liveness and fairness cycles"
  (it "finds a fair subcycle inside a larger SCC"
    (let ((spec (specification subcycle () (:variables x) (:init (x 0))
                  (:action flip (:guard (< x 2)) (:next (x (- 1 x))))
                  (:action branch (:guard (= x 0)) (:next (x 2)))
                  (:action back (:guard (= x 2)) (:next (x 0)))
                  (:fairness (:weak flip))
                  (:temporal visits-branch (:eventually (= x 2))))))
      (expect (mapcar #'spec-violation-property (checked-liveness-violations spec))
              :to-equal '(visits-branch))))

  (it "combines fair actions in one repeating closed walk"
    (let ((spec (specification two-fair-actions () (:variables x) (:init (x 0))
                  (:action left (:guard (= x 0)) (:next (x 1)))
                  (:action right (:guard (= x 0)) (:next (x 2)))
                  (:action back (:guard (/= x 0)) (:next (x 0)))
                  (:fairness (:strong left) (:strong right) (:weak back))
                  (:temporal always-zero (:eventually-always (= x 0)))
                  (:temporal visits-left (:infinitely-often (= x 1)))
                  (:temporal visits-right (:infinitely-often (= x 2))))))
      (let* ((violations (checked-liveness-violations spec))
             (actions (mapcar #'trace-step-action
                              (lasso-cycle (spec-violation-trace (first violations))))))
        (expect (mapcar #'spec-violation-property violations) :to-equal '(always-zero))
        (expect (not (null (member 'left actions))) :to-be t)
        (expect (not (null (member 'right actions))) :to-be t))))

  (it "requires the consequent after each antecedent, not merely on a prior path"
    (let ((spec (specification response () (:variables x) (:init (x 0))
                  (:action step (:guard (< x 2)) (:next (x (1+ x))))
                  (:fairness (:weak step))
                  (:temporal first-to-middle (:leads-to (= x 0) (= x 1)))
                  (:temporal last-to-middle (:leads-to (= x 2) (= x 1)))
                  (:temporal often-middle (:infinitely-often (= x 1)))
                  (:temporal stays-last (:eventually-always (= x 2))))))
      (expect (mapcar #'spec-violation-property (checked-liveness-violations spec))
              :to-equal '(last-to-middle often-middle)))))
