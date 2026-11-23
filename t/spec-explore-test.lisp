(in-package #:cl-weave/spec-test)

(defmacro exploration-signals-error (type form)
  `(expect (handler-case (progn ,form :no-error)
             (,type () :signalled))
           :to-be :signalled))

(defun exploration-trace-summary (result)
  (mapcar (lambda (step)
            (list (trace-step-action step) (trace-step-params step)
                  (trace-step-state step)))
          (spec-violation-trace (spec-result-violation result))))

(describe "spec exhaustive exploration"
  (it "enumerates all six states from multiple initial states"
    (let ((result (explore-spec (chooser) :check-deadlock nil
                                         :symmetry nil :temporal nil)))
      (expect (spec-result-mode result) :to-be :exhaustive)
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-states-found result) :to-be 6)
      (expect (spec-result-depth-reached result) :to-be 2)
      (expect (getf (spec-result-statistics result) :initial-states) :to-be 2)
      (expect (getf (spec-result-statistics result) :transitions) :to-be 15)))

  (it "returns the first initial invariant violation before deadlock"
    (let* ((spec (specification bad-init ()
                   (:variables x) (:init (x (:in (list 0 1))))
                   (:invariant positive (> x 0))))
           (result (explore-spec spec :symmetry nil :temporal nil))
           (violation (spec-result-violation result)))
      (expect (spec-violation-kind violation) :to-be :invariant)
      (expect (spec-violation-property violation) :to-be 'positive)
      (expect (exploration-trace-summary result) :to-equal '((nil nil (x 0))))))

  (it "reports an initial deadlock and permits explicitly disabling it"
    (let* ((spec (specification stuck () (:variables x) (:init (x 0))))
           (result (explore-spec spec :symmetry nil :temporal nil)))
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :deadlock)
      (expect (exploration-trace-summary result) :to-equal '((nil nil (x 0))))
      (expect (spec-result-passed-p
               (explore-spec spec :check-deadlock nil :symmetry nil :temporal nil))
              :to-be t)))

  (it "honors the specification deadlock setting and explicit override"
    (let ((spec (make-spec :name 'no-deadlock :variables '(x)
                           :init (lambda () '((x 0))) :check-deadlock nil)))
      (expect (spec-result-passed-p (explore-spec spec :symmetry nil :temporal nil)) :to-be t)
      (expect (spec-violation-kind
               (spec-result-violation
                (explore-spec spec :check-deadlock t :symmetry nil :temporal nil)))
              :to-be :deadlock)))

  (it "finds the shortest invariant counterexample in successor order"
    (let* ((spec (specification branching ()
                   (:variables x) (:init (x 0))
                   (:action pick (:for (v (list 1 2)))
                     (:guard (= x 0)) (:next (x v)))
                   (:action advance (:guard (= x 1)) (:next (x 3)))
                   (:invariant safe (< x 2))))
           (result (explore-spec spec :check-deadlock nil :symmetry nil :temporal nil)))
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :invariant)
      (expect (exploration-trace-summary result)
              :to-equal '((nil nil (x 0)) (pick (2) (x 2))))))

  (it "checks an action property even when its target was visited"
    (let* ((spec (specification back-edge ()
                   (:variables x) (:init (x (:in (list 0 1))))
                   (:action back (:guard (= x 1)) (:next (x 0)))
                   (:action-property increasing (< x (next x)))))
           (result (explore-spec spec :check-deadlock nil :symmetry nil :temporal nil)))
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :action-property)
      (expect (spec-violation-property (spec-result-violation result)) :to-be 'increasing)
      (expect (exploration-trace-summary result)
              :to-equal '((nil nil (x 1)) (back nil (x 0))))))

  (it "does not truncate at the state limit if successors are all visited"
    (let* ((spec (specification cycle () (:variables x)
                   (:init (x (:in (list 0 1))))
                   (:action flip (:next (x (- 1 x))))))
           (result (explore-spec spec :max-states 2 :symmetry nil :temporal nil)))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-truncated result) :to-be nil)
      (expect (spec-result-states-found result) :to-be 2)
      (expect (getf (spec-result-statistics result) :transitions) :to-be 2)))

  (it "treats a self-loop as enabled and not as an action-property violation"
    (let* ((spec (specification loop-only () (:variables x) (:init (x 0))
                   (:action stay (:next (x x)))
                   (:action-property impossible nil)))
           (result (explore-spec spec :symmetry nil :temporal nil)))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-states-found result) :to-be 1)
      (expect (getf (spec-result-statistics result) :transitions) :to-be 1)))

  (it "rejects zero depth and invalid state bounds before searching"
    (exploration-signals-error spec-configuration-error
      (explore-spec (counter) :max-depth 0 :symmetry nil :temporal nil))
    (exploration-signals-error spec-configuration-error
      (explore-spec (counter) :max-states 0 :symmetry nil :temporal nil))
    (exploration-signals-error spec-configuration-error
      (explore-spec (counter) :max-depth -1 :symmetry nil :temporal nil))
    (exploration-signals-error spec-configuration-error
      (explore-spec (counter) :max-states 1.5 :symmetry nil :temporal nil)))

  (it "reports depth truncation and requires explicit bounded acceptance"
    (let ((result (explore-spec (counter) :max-depth 1 :check-deadlock nil
                                          :symmetry nil :temporal nil))
          (bounded (explore-spec (counter) :max-depth 1 :check-deadlock nil
                                           :symmetry nil :temporal nil :allow-bounded t)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-result-truncation-reason result) :to-be :max-depth)
      (expect (spec-result-states-found result) :to-be 2)
      (expect (spec-result-depth-reached result) :to-be 1)
      (expect (spec-result-passed-p bounded) :to-be t)))

  (it "does not truncate at the depth limit when no action is enabled"
    (let ((result (explore-spec (counter :limit 1) :max-depth 1 :check-deadlock nil
                                                     :symmetry nil :temporal nil)))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-states-found result) :to-be 2)
      (expect (spec-result-depth-reached result) :to-be 1)
      (expect (spec-result-truncated result) :to-be nil)))

  (it "truncates on a new state after reaching the state limit"
    (let ((result (explore-spec (counter) :max-states 2 :check-deadlock nil
                                          :symmetry nil :temporal nil))
          (bounded (explore-spec (counter) :max-states 2 :check-deadlock nil
                                           :symmetry nil :temporal nil :allow-bounded t)))
      (expect (spec-result-truncation-reason result) :to-be :max-states)
      (expect (spec-result-states-found result) :to-be 2)
      (expect (spec-result-depth-reached result) :to-be 1)
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-result-passed-p bounded) :to-be t)))

  (it "prioritizes an action violation over a simultaneous state limit"
    (let* ((spec (specification broken-step () (:variables x) (:init (x 0))
                   (:action inc (:next (x (1+ x))))
                   (:action-property never nil)))
           (result (explore-spec spec :max-states 1 :symmetry nil :temporal nil
                                      :allow-bounded t)))
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :action-property)
      (expect (spec-result-passed-p result) :to-be nil)))

  (it "fills the initial-check violation trace"
    (let ((result (explore-spec (chooser) :symmetry nil :temporal nil
                                :initial-check
                                (lambda (state)
                                  (when (= (state-ref state 'x) 1)
                                    (make-spec-violation :kind :refinement))))))
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :refinement)
      (expect (exploration-trace-summary result) :to-equal '((nil nil (x 1 y 0))))))

  (it "calls step-check on transitions to visited states and fills its trace"
    (let* ((spec (specification back-check () (:variables x)
                   (:init (x (:in (list 0 1))))
                   (:action back (:guard (= x 1)) (:next (x 0)))))
           (result (explore-spec spec :check-deadlock nil :symmetry nil :temporal nil
                                 :step-check (lambda (transition)
                                               (declare (ignore transition))
                                               (make-spec-violation :kind :refinement)))))
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :refinement)
      (expect (exploration-trace-summary result)
              :to-equal '((nil nil (x 1)) (back nil (x 0)))))))

(describe "spec exhaustive exploration ordering"
  (it "reports a shallower initial deadlock before a later invariant violation"
    (let* ((spec (specification shallower-deadlock ()
                   (:variables x) (:init (x (:in (list 1 0))))
                   (:action advance (:guard (= x 1)) (:next (x 2)))
                   (:invariant below-two (< x 2))))
           (result (explore-spec spec :symmetry nil :temporal nil)))
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :deadlock)
      (expect (exploration-trace-summary result) :to-equal '((nil nil (x 0)))))))

(describe "spec exhaustive exploration result metadata"
  (it "records examined properties and limits on a complete safety check"
    (let* ((spec (specification metadata-success ()
                   (:variables x) (:init (x 0))
                   (:action inc (:guard (= x 0)) (:next (x 1)))
                   (:action stay (:guard (= x 1)) (:next (x x)))
                   (:invariant safe (<= x 1))
                   (:action-property increasing (< x (next x)))))
           (result (explore-spec spec :max-states 7 :max-depth 3
                                      :symmetry nil :temporal nil)))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-checked-properties result) :to-equal '(safe increasing :deadlock))
      (expect (spec-result-limits result) :to-equal '(:max-states 7 :max-depth 3))))

  (it "records declared safety properties when the initial state violates an invariant"
    (let* ((spec (specification metadata-violation ()
                   (:variables x) (:init (x 0))
                   (:action inc (:next (x (1+ x))))
                   (:invariant positive (> x 0))
                   (:action-property increasing (< x (next x)))))
           (result (explore-spec spec :max-states 7 :max-depth 3
                                      :symmetry nil :temporal nil)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-result-checked-properties result) :to-equal '(positive increasing))
      (expect (spec-result-limits result) :to-equal '(:max-states 7 :max-depth 3))))

  (it "records limits and excludes unexamined temporal properties on truncation"
    (let* ((spec (make-spec :name 'metadata-truncated :variables '(x)
                            :init (lambda () '((x 0)))
                            :actions (list (make-spec-action
                                            :name 'inc :guard (constantly t)
                                            :update (lambda (s) (list 'x (1+ (state-ref s 'x))))))
                            :invariants (list (make-spec-invariant :name 'safe :predicate (constantly t)))
                            :temporal-properties (list (make-spec-temporal-property
                                                        :name 'eventual :kind :eventually
                                                        :predicate (constantly t)))))
           (result (explore-spec spec :max-states 7 :max-depth 1 :symmetry nil
                                      :check-deadlock nil :allow-bounded t)))
      (expect (spec-result-truncated result) :to-be t)
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-result-liveness-requested result) :to-equal '(eventual))
      (expect (spec-result-checked-properties result) :to-equal '(safe))
      (expect (spec-result-limits result) :to-equal '(:max-states 7 :max-depth 1))))

  (it "checks the complete graph and records selected temporal properties"
    (let* ((spec (make-spec :name 'metadata-temporal :variables '(x)
                            :init (lambda () '((x 0)))
                            :actions (list (make-spec-action :name 'stay :guard (constantly t)
                                                            :update (lambda (s) (declare (ignore s)) nil)))
                            :temporal-properties (list (make-spec-temporal-property
                                                        :name 'never :kind :eventually
                                                        :predicate (constantly nil)))))
           (result (explore-spec spec :max-states 7 :max-depth 3 :symmetry nil
                                      :check-deadlock nil :temporal '(never))))
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :temporal)
      (expect (spec-violation-property (spec-result-violation result)) :to-be 'never)
      (expect (lasso-p (spec-violation-trace (spec-result-violation result))) :to-be t)
      (expect (spec-result-checked-properties result) :to-equal '(never))
      (expect (spec-result-limits result) :to-equal '(:max-states 7 :max-depth 3)))))

(describe "spec exhaustive exploration temporal selection"
  (it "rejects an unknown temporal name before evaluating Init"
    (let* ((init-called nil)
           (spec (make-spec :name 'temporal-selection :variables '(x)
                            :init (lambda () (setf init-called t) '((x 0)))
                            :temporal-properties (list (make-spec-temporal-property
                                                        :name 'known :kind :always
                                                        :predicate (constantly t))))))
      (exploration-signals-error spec-configuration-error
        (explore-spec spec :symmetry nil :temporal '(missing)))
      (expect init-called :to-be nil)
      (exploration-signals-error spec-configuration-error
        (explore-spec spec :symmetry nil :temporal '(known missing)))
      (expect init-called :to-be nil)))

  (it "checks a declared name without checking unselected properties"
    (let* ((spec (make-spec :name 'selected-temporal :variables '(x)
                            :init (lambda () '((x 0)))
                            :temporal-properties (list (make-spec-temporal-property
                                                        :name 'good :kind :always
                                                        :predicate (constantly t))
                                                       (make-spec-temporal-property
                                                        :name 'bad :kind :eventually
                                                        :predicate (constantly nil)))
                            :check-deadlock nil))
           (result (explore-spec spec :symmetry nil :temporal '(good))))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-checked-properties result) :to-equal '(good)))))

(describe "spec exhaustive exploration boundary regressions"
  (it "caps initial states at max-states and reports depth zero"
    (let ((result (explore-spec (chooser) :max-states 1 :symmetry nil :temporal nil)))
      (expect (spec-result-truncation-reason result) :to-be :max-states)
      (expect (spec-result-states-found result) :to-be 1)
      (expect (spec-result-depth-reached result) :to-be 0)
      (expect (spec-result-passed-p result) :to-be nil)))

  (it "returns every step of a deadlock trace beyond depth one"
    (let ((result (explore-spec (counter :limit 2) :symmetry nil :temporal nil)))
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :deadlock)
      (expect (exploration-trace-summary result)
              :to-equal '((nil nil (x 0)) (inc nil (x 1)) (inc nil (x 2))))
      (expect (spec-result-states-found result) :to-be 3)
      (expect (spec-result-depth-reached result) :to-be 2)))

  (it "finds a same-depth invariant at discovery before expanding a deadlock"
    (let* ((spec (specification initial-order () (:variables x)
                   (:init (x (:in (list 0 1))))
                   (:invariant zero (= x 0))))
           (result (explore-spec spec :symmetry nil :temporal nil)))
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :invariant)
      (expect (exploration-trace-summary result) :to-equal '((nil nil (x 1))))
      (expect (spec-result-states-found result) :to-be 2)
      (expect (spec-result-depth-reached result) :to-be 0)))

  (it "rejects malformed temporal and deadlock options before Init"
    (let* ((called nil)
           (spec (make-spec :name 'invalid-options :variables '(x)
                            :init (lambda () (setf called t) '((x 0))))))
      (exploration-signals-error spec-configuration-error
        (explore-spec spec :symmetry nil :temporal :bad))
      (expect called :to-be nil)
      (exploration-signals-error spec-configuration-error
        (explore-spec spec :symmetry nil :temporal nil :check-deadlock :bad))
      (expect called :to-be nil)))

  (it "includes a dead end at max-depth in the graph for temporal checking"
    (let* ((spec (make-spec :name 'boundary-graph :variables '(x)
                            :init (lambda () '((x 0)))
                            :actions (list (make-spec-action
                                            :name 'advance
                                            :guard (lambda (s) (= (state-ref s 'x) 0))
                                            :update (lambda (s) (declare (ignore s)) '(x 1))))
                            :temporal-properties (list (make-spec-temporal-property
                                                        :name 'always-zero :kind :always
                                                        :predicate (lambda (s) (= (state-ref s 'x) 0))))
                            :check-deadlock nil))
           (result (explore-spec spec :max-depth 1 :symmetry nil)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind (spec-result-violation result)) :to-be :temporal)
      (expect (spec-result-truncated result) :to-be nil)
      (expect (spec-result-states-found result) :to-be 2)
      (expect (spec-result-depth-reached result) :to-be 1)))

  (it "lists action properties for a self-loop-only check"
    (let* ((spec (specification self-loop-metadata () (:variables x) (:init (x 0))
                   (:action stay (:next (x x)))
                   (:action-property never nil)))
           (result (explore-spec spec :symmetry nil :temporal nil :check-deadlock nil)))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-checked-properties result) :to-equal '(never))
      (expect (spec-result-states-found result) :to-be 1)
      (expect (spec-result-depth-reached result) :to-be 0))))

(describe "spec exhaustive exploration invalid temporal options"
  (it "rejects each non-list temporal option before Init"
    (let* ((called nil)
           (spec (make-spec :name 'invalid-temporal :variables '(x)
                            :init (lambda () (setf called t) '((x 0)))
                            :temporal-properties (list (make-spec-temporal-property
                                                        :name 'p1 :kind :always
                                                        :predicate (constantly t))))))
      (dolist (option (list 'p1 :p1 t "p1"))
        (exploration-signals-error spec-configuration-error
          (explore-spec spec :symmetry nil :temporal option))
        (expect called :to-be nil)))))
