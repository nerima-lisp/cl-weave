(in-package #:cl-weave/spec-test)

(defun refinement-cycle (&key temporal fairness two-actions)
  (make-spec :name 'cycle :variables '(x) :init (lambda () '((x 0)))
             :actions (append
                       (list (make-spec-action :name 'advance
                                               :guard (lambda (s) (= (state-ref s 'x) 0))
                                               :update (lambda (s) (declare (ignore s)) '(x 1))))
                       (when two-actions
                         (list (make-spec-action :name 'alternate
                                                 :guard (lambda (s) (= (state-ref s 'x) 0))
                                                 :update (lambda (s) (declare (ignore s)) '(x 1)))))
                       (list (make-spec-action :name 'back
                                               :guard (lambda (s) (= (state-ref s 'x) 1))
                                               :update (lambda (s) (declare (ignore s)) '(x 0)))))
             :temporal-properties temporal :fairness-conditions fairness))

(describe "spec refinement"
  (it "accepts identity and records limits"
    (let* ((spec (refinement-cycle))
           (result (check-refinement spec spec #'identity :max-states 4 :max-depth 3)))
      (expect (spec-result-mode result) :to-be :refinement)
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-states-found result) :to-be 2)
      (expect (spec-result-checked-properties result) :to-equal '(:deadlock))
      (expect (spec-result-limits result) :to-equal '(:max-states 4 :max-depth 3))))

  (it "reports a mapped initial state outside the high initial states"
    (let* ((spec (refinement-cycle))
           (result (check-refinement spec spec (lambda (s) (declare (ignore s)) '(x 1))))
           (violation (spec-result-violation result)))
      (expect (spec-violation-kind violation) :to-be :refinement)
      (expect (spec-violation-detail violation)
              :to-equal '(:phase :init :low-from nil :low-to (x 0) :mapped-from nil :mapped-to (x 1)))
      (expect (mapcar #'trace-step-state (spec-violation-trace violation)) :to-equal '((x 0)))))

  (it "reports a mapped step that is neither a high step nor stuttering"
    (let* ((low (specification bad-refinement () (:variables x) (:init (x 0))
                  (:action jump (:next (x 2)))))
           (result (check-refinement low (refinement-cycle) #'identity))
           (violation (spec-result-violation result)))
      (expect (spec-violation-kind violation) :to-be :refinement)
      (expect (spec-violation-detail violation)
              :to-equal '(:phase :step :low-from (x 0) :low-to (x 2) :mapped-from (x 0) :mapped-to (x 2)))
      (expect (mapcar #'trace-step-action (spec-violation-trace violation)) :to-equal '(nil jump))
      (expect (mapcar #'trace-step-state (spec-violation-trace violation)) :to-equal '((x 0) (x 2)))))

  (it "accepts a mapping that collapses low steps into stuttering"
    (let ((result (check-refinement (refinement-cycle) (refinement-cycle)
                                    (lambda (s) (declare (ignore s)) '(x 0)))))
      (expect (spec-result-passed-p result) :to-be t)))

  (it "accepts a low step matching multiple high actions and checks fairness"
    (let* ((property (make-spec-temporal-property :name 'reaches-one :kind :eventually
                                                   :predicate (lambda (s) (= (state-ref s 'x) 1))))
           (fairness (make-spec-fairness-condition :kind :weak :action 'alternate))
           (high (refinement-cycle :temporal (list property) :fairness (list fairness) :two-actions t))
           (result (check-refinement (refinement-cycle :fairness (list (make-spec-fairness-condition :kind :weak :action 'advance))) high #'identity)))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-checked-properties result) :to-equal '(reaches-one :deadlock))))

  (it "rejects an ineligible mapping value"
    (expect (lambda () (check-refinement (refinement-cycle) (refinement-cycle)
                        (lambda (s) (declare (ignore s)) (list 'x (make-hash-table))))) :to-throw 'spec-state-error))

  (it "rejects a mapping missing a high variable"
    (expect (lambda () (check-refinement (refinement-cycle) (refinement-cycle)
                        (lambda (s) (declare (ignore s)) nil))) :to-throw 'spec-definition-error))

  (it "detects a high temporal violation in the mapped graph"
    (let* ((property (make-spec-temporal-property :name 'reaches-one :kind :eventually
                                                   :predicate (lambda (s) (= (state-ref s 'x) 1))))
           (result (check-refinement (refinement-cycle) (refinement-cycle :temporal (list property))
                                     (lambda (s) (declare (ignore s)) '(x 0))))
           (violation (spec-result-violation result)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :temporal)
      (expect (spec-violation-property violation) :to-be 'reaches-one)
      (expect (lasso-p (spec-violation-trace violation)) :to-be t)
      (expect (spec-result-checked-properties result) :to-equal '(reaches-one :deadlock))))

  (it "does not pass truncation with requested high liveness"
    (let* ((property (make-spec-temporal-property :name 'reaches-one :kind :eventually
                                                   :predicate (lambda (s) (= (state-ref s 'x) 1))))
           (result (check-refinement (refinement-cycle) (refinement-cycle :temporal (list property))
                                     #'identity :max-states 1 :max-depth 3 :allow-bounded t)))
      (expect (spec-result-truncated result) :to-be t)
      (expect (spec-result-truncation-reason result) :to-be :max-states)
      (expect (spec-result-liveness-requested result) :to-equal '(reaches-one))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-result-checked-properties result) :to-equal '(:deadlock))
      (expect (spec-result-limits result) :to-equal '(:max-states 1 :max-depth 3))))

  (it "rejects unknown temporal names before truncation or safety violations"
    (let ((spec (refinement-cycle)))
      (expect (lambda () (check-refinement spec spec #'identity :max-states 1 :temporal '(missing))) :to-throw 'spec-configuration-error)
      (expect (lambda () (check-refinement spec spec (lambda (s) (declare (ignore s)) '(x 1)) :temporal '(missing))) :to-throw 'spec-configuration-error))))

(describe "spec refinement mapped liveness"
  (it "does not create a cycle by merging low states with the same image"
    (let* ((low (make-spec :name 'low-path :variables '(x)
                           :init (lambda () '((x 0)))
                           :actions (list (make-spec-action :name 'advance
                                          :guard (lambda (s) (< (state-ref s 'x) 3))
                                          :update (lambda (s) (list 'x (1+ (state-ref s 'x)))))
                                          (make-spec-action :name 'stay
                                          :guard (lambda (s) (= (state-ref s 'x) 3))
                                          :update (lambda (s) (declare (ignore s)) nil)))
                           :fairness-conditions (list (make-spec-fairness-condition
                                                       :kind :weak :action 'advance))))
           (high (make-spec :name 'high-cycle :variables '(x)
                            :init (lambda () '((x 0)))
                            :actions (list (make-spec-action :name 'a
                                           :guard (lambda (s) (= (state-ref s 'x) 0))
                                           :update (lambda (s) (declare (ignore s)) '(x 1)))
                                           (make-spec-action :name 'b
                                           :guard (lambda (s) (= (state-ref s 'x) 1))
                                           :update (lambda (s) (declare (ignore s)) '(x 0)))
                                           (make-spec-action :name 'c
                                           :guard (lambda (s) (= (state-ref s 'x) 0))
                                           :update (lambda (s) (declare (ignore s)) '(x 2))))
                            :temporal-properties (list (make-spec-temporal-property
                                                       :name 'reaches-two :kind :eventually
                                                       :predicate (lambda (s) (= (state-ref s 'x) 2))))))
           (result (check-refinement low high
                                     (lambda (s) (list 'x (nth (state-ref s 'x) '(0 1 0 2)))))))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-states-found result) :to-be 4)
      (expect (spec-result-checked-properties result) :to-equal '(reaches-two :deadlock))))

  (it "finds a real fair low cycle violating high liveness"
    (let* ((property (make-spec-temporal-property :name 'reaches-one :kind :eventually
                                                   :predicate (lambda (s) (= (state-ref s 'x) 1))))
           (low (refinement-cycle :fairness (list (make-spec-fairness-condition
                                                  :kind :weak :action 'advance))))
           (result (check-refinement low (refinement-cycle :temporal (list property))
                                     (lambda (s) (declare (ignore s)) '(x 0))))
           (violation (spec-result-violation result)))
      (expect (spec-violation-kind violation) :to-be :temporal)
      (expect (spec-violation-property violation) :to-be 'reaches-one)
      (expect (lasso-p (spec-violation-trace violation)) :to-be t)
      (expect (spec-result-passed-p result) :to-be nil)))

  (it "checks recurrent high liveness through a low back edge"
    (let* ((low (make-spec :name (quote back-edge) :variables (quote (x))
                           :init (lambda () (quote ((x 0))))
                           :actions (list (make-spec-action :name (quote first-step)
                                            :guard (lambda (s) (= (state-ref s (quote x)) 0))
                                            :update (lambda (s) (declare (ignore s)) (quote (x 1))))
                                          (make-spec-action :name (quote second-step)
                                            :guard (lambda (s) (= (state-ref s (quote x)) 1))
                                            :update (lambda (s) (declare (ignore s)) (quote (x 2))))
                                          (make-spec-action :name (quote back)
                                            :guard (lambda (s) (= (state-ref s (quote x)) 2))
                                            :update (lambda (s) (declare (ignore s)) (quote (x 1)))))
                           :fairness-conditions
                           (mapcar (lambda (action) (make-spec-fairness-condition :kind :weak :action action))
                                   (quote (first-step second-step back)))))
           (high (make-spec :name (quote high) :variables (spec-variables low)
                            :init (spec-init low) :actions (spec-actions low)
                            :temporal-properties
                            (list (make-spec-temporal-property :name (quote recurring-one) :kind :infinitely-often
                                    :predicate (lambda (s) (= (state-ref s (quote x)) 1))))))
           (result (check-refinement low high (function identity))))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-states-found result) :to-be 3)
      (expect (spec-result-checked-properties result) :to-equal (quote (recurring-one :deadlock))))))

(describe "spec refinement temporal predicates"
  (it "preserves each distinct temporal predicate when selecting properties"
    (let* ((low (refinement-cycle :fairness (list (make-spec-fairness-condition
                                                  :kind :weak :action 'advance))))
           (high (refinement-cycle :temporal
                                   (list (make-spec-temporal-property
                                          :name 'reaches-one :kind :eventually
                                          :predicate (lambda (s) (= (state-ref s 'x) 1)))
                                         (make-spec-temporal-property
                                          :name 'never-two :kind :always
                                          :predicate (lambda (s) (/= (state-ref s 'x) 2)))
                                         (make-spec-temporal-property
                                          :name 'reaches-two :kind :eventually
                                          :predicate (lambda (s) (= (state-ref s 'x) 2))))))
           (passes (check-refinement low high #'identity :temporal '(reaches-one never-two)))
           (fails (check-refinement low high #'identity :temporal '(reaches-two))))
      (expect (spec-result-passed-p passes) :to-be t)
      (expect (spec-result-checked-properties passes) :to-equal '(reaches-one never-two :deadlock))
      (expect (spec-violation-property (spec-result-violation fails)) :to-be 'reaches-two)
      (expect (spec-result-checked-properties fails) :to-equal '(reaches-two :deadlock))))

  (it "maps both antecedent and consequent of leads-to"
    (let* ((low (refinement-cycle :fairness (list (make-spec-fairness-condition
                                                  :kind :weak :action 'advance))))
           (property (make-spec-temporal-property :name 'zero-leads-to-one :kind :leads-to
                                                   :predicate (lambda (s) (= (state-ref s 'x) 0))
                                                   :consequent (lambda (s) (= (state-ref s 'x) 1))))
           (high (refinement-cycle :temporal (list property)))
           (passes (check-refinement low high #'identity))
           (fails (check-refinement low high (lambda (s) (declare (ignore s)) '(x 0)))))
      (expect (spec-result-passed-p passes) :to-be t)
      (expect (spec-violation-kind (spec-result-violation fails)) :to-be :temporal)
      (expect (spec-violation-property (spec-result-violation fails)) :to-be 'zero-leads-to-one))))

(describe "spec refinement temporal configuration"
  (it "rejects a dotted property list before exploring"
    (expect (lambda () (check-refinement (refinement-cycle) (refinement-cycle :temporal (list (make-spec-temporal-property :name 'known :kind :always :predicate (constantly t)))) #'identity :temporal '(known . tail))) :to-throw 'spec-configuration-error)))
