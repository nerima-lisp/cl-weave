(in-package #:cl-weave/spec-test)

;;;; FR-003 and the shared state machinery: spec construction, DSL, Init and
;;;; successor enumeration, property helpers, results, fingerprints and state
;;;; tables. Expected values are computed by hand from the fixtures in
;;;; spec-helpers.lisp.

(defmacro signals-error-of-type (type form)
  "Expand to an expectation that FORM signals a condition of TYPE."
  `(expect (handler-case (progn ,form :no-error)
             (,type () :signalled))
           :to-be :signalled))

(describe "spec enumeration of the counter fixture"
  (it "has one initial state"
    (expect (spec-initial-states (counter)) :to-equal '((x 0))))

  (it "enumerates the single successor of a non-final state"
    (expect (transition-summaries (spec-successors (counter) '(x 0)))
            :to-equal '((inc () (x 1)))))

  (it "enumerates no successor at the limit, which is a deadlock"
    (let ((spec (counter)))
      (expect (spec-successors spec '(x 3)) :to-be nil)
      (expect (spec-deadlock-p spec '(x 3)) :to-be t)
      (expect (spec-deadlock-p spec '(x 2)) :to-be nil)))

  (it "records the transition's source state and action"
    (let ((transition (first (spec-successors (counter) '(x 1)))))
      (expect (spec-transition-from transition) :to-equal '(x 1))
      (expect (spec-transition-action transition) :to-be 'inc)))

  (it "applies a model parameter override to the whole specification"
    (let ((spec (counter :limit 1)))
      (expect (spec-constant spec 'limit) :to-be 1)
      (expect (spec-successors spec '(x 1)) :to-be nil)
      (expect (spec-constants (counter)) :to-equal '(limit 3)))))

(describe "spec enumeration with several initial states and a quantifier"
  (it "returns every initial state in Init order"
    (expect (spec-initial-states (chooser))
            :to-equal '((x 0 y 0) (x 1 y 0))))

  (it "enumerates actions in declaration order and bindings in domain order"
    (expect (transition-summaries (spec-successors (chooser) '(x 0 y 0)))
            :to-equal '((set-x (1) (x 1 y 0))
                        (set-x (2) (x 2 y 0))
                        (bump-y () (x 0 y 1)))))

  (it "disables an action whose guard fails"
    (expect (transition-summaries (spec-successors (chooser) '(x 1 y 1)))
            :to-equal '((set-x (0) (x 0 y 1))
                        (set-x (2) (x 2 y 1))))))

(describe "spec quantifiers"
  (it "lets a later quantifier depend on an earlier one"
    (let ((spec (specification dependent ()
                  (:variables seen)
                  (:init (seen nil))
                  (:action pick
                    (:for (i (list 1 2))
                          (j (loop for k from i to 2 collect k)))
                    (:next (seen (list i j)))))))
      (expect (mapcar #'spec-transition-params (spec-successors spec '(seen nil)))
              :to-equal '((1 1) (1 2) (2 2)))))

  (it "visits a repeated domain element once"
    (let ((spec (specification repeated ()
                  (:variables x)
                  (:init (x 0))
                  (:action pick (:for (v (list 5 5 6))) (:next (x v))))))
      (expect (mapcar #'spec-transition-params (spec-successors spec '(x 0)))
              :to-equal '((5) (6)))))

  (it "rejects a value-model set passed where a list is expected"
    (let ((spec (make-spec
                 :name 'tagged :variables '(x)
                 :init (lambda () (list (list 'x 0)))
                 :actions (list (make-spec-action
                                 :name 'pick
                                 :params (list (list 'v (lambda (state)
                                                          (declare (ignore state))
                                                          (list 'cl-weave/spec::%set 1 2))))
                                 :guard (constantly t)
                                 :update (lambda (state v) (declare (ignore state)) (list 'x v)))))))
      (signals-error-of-type spec-definition-error (spec-successors spec '(x 0))))))

(describe "spec states"
  (it "orders state variables by declaration regardless of Init clause order"
    (let ((spec (specification reordered ()
                  (:variables a b)
                  (:init (b 2) (a 1)))))
      (expect (spec-initial-states spec) :to-equal '((a 1 b 2)))))

  (it "keeps unassigned variables unchanged"
    (expect (spec-transition-to (first (spec-successors (chooser) '(x 0 y 0))))
            :to-equal '(x 1 y 0)))

  (it "removes duplicate initial states"
    (let ((spec (specification duplicated ()
                  (:variables x)
                  (:init (x (:in (list 1 1 2)))))))
      (expect (spec-initial-states spec) :to-equal '((x 1) (x 2)))))

  (it "reads a variable with STATE-REF"
    (expect (state-ref '(x 1 y 2) 'y) :to-be 2)
    (signals-error-of-type spec-definition-error (state-ref '(x 1) 'z)))

  (it "rejects an empty Init"
    (let ((spec (make-spec :name 'empty :variables '(x)
                           :init (lambda () nil))))
      (signals-error-of-type spec-definition-error (spec-initial-states spec)))))

(describe "spec state validation"
  (it "names the variable holding a hash table in an initial state"
    (let ((spec (make-spec :name 'bad :variables '(x y)
                           :init (lambda ()
                                   (list (list 'x 0 'y (make-hash-table)))))))
      (handler-case (progn (spec-initial-states spec) (expect :no-error :to-be :error))
        (spec-state-error (condition)
          (expect (spec-state-error-variable condition) :to-be 'y)
          (expect (search "Y" (spec-error-message condition)) :to-be-type-of 'integer)))))

  (it "rejects a hash table nested inside a list"
    (expect (handler-case (validate-comparable-value (list 1 (list 2 (make-hash-table))) 'v)
              (spec-state-error (condition) (spec-state-error-variable condition)))
            :to-be 'v))

  (it "accepts lists, numbers, symbols, characters, strings and bit vectors"
    (let ((value (list 1 2.5 'a #\b "c" #*101 (list nil (cons 1 2)))))
      (expect (validate-comparable-value value 'v) :to-be value)))

  (it "rejects a successor state holding an incomparable value"
    (let ((spec (make-spec
                 :name 'bad-update :variables '(x)
                 :init (lambda () (list (list 'x 0)))
                 :actions (list (make-spec-action
                                 :name 'break
                                 :guard (constantly t)
                                 :update (lambda (state)
                                           (declare (ignore state))
                                           (list 'x (lambda ()))))))))
      (signals-error-of-type spec-state-error (spec-successors spec '(x 0)))))

  (it "rejects an update of an undeclared variable"
    (let ((spec (make-spec
                 :name 'undeclared :variables '(x)
                 :init (lambda () (list (list 'x 0)))
                 :actions (list (make-spec-action
                                 :name 'bad
                                 :guard (constantly t)
                                 :update (lambda (state)
                                           (declare (ignore state))
                                           (list 'z 1)))))))
      (signals-error-of-type spec-definition-error (spec-successors spec '(x 0)))))

  (it "rejects an Init state that omits a variable"
    (let ((spec (make-spec :name 'partial :variables '(x y)
                           :init (lambda () (list (list 'x 0))))))
      (signals-error-of-type spec-definition-error (spec-initial-states spec)))))

(describe "spec property helpers"
  (it "reports violated invariants by name"
    (let ((spec (specification invariant-demo ()
                  (:variables x)
                  (:init (x 0))
                  (:invariant small (< x 2))
                  (:invariant even (evenp x)))))
      (expect (spec-check-invariants spec '(x 0)) :to-be nil)
      (expect (spec-check-invariants spec '(x 1)) :to-equal '(even))
      (expect (spec-check-invariants spec '(x 2)) :to-equal '(small))))

  (it "checks action properties on real steps and ignores stuttering steps"
    (let ((spec (specification monotone ()
                  (:variables x)
                  (:init (x 0))
                  (:action-property never-decreases (>= (next x) x)))))
      (expect (spec-check-action-properties spec '(x 1) '(x 2)) :to-be nil)
      (expect (spec-check-action-properties spec '(x 2) '(x 1)) :to-equal '(never-decreases))
      (expect (spec-check-action-properties spec '(x 2) '(x 2)) :to-be nil)))

  (it "exposes the next state to an :output form"
    (let* ((spec (specification outputs ()
                   (:variables x)
                   (:init (x 0))
                   (:action inc (:next (x (1+ x))) (:output (list x (next x))))))
           (action (spec-find-action spec 'inc)))
      (expect (funcall (spec-action-output action) '(x 4) '(x 5)) :to-equal '(4 5)))))

(describe "spec DSL declarations"
  (it "records fairness, symmetry, temporal properties and the deadlock option"
    (let ((spec (specification declarations ((procs (list 1 2)))
                  (:variables x)
                  (:init (x 0))
                  (:action step (:next (x (1+ x))))
                  (:fairness (:weak step))
                  (:symmetry procs)
                  (:temporal reaches-two (:eventually (= x 2)))
                  (:temporal responds (:leads-to (= x 1) (= x 2)))
                  (:deadlock-check nil))))
      (expect (mapcar (lambda (c) (list (spec-fairness-condition-kind c)
                                        (spec-fairness-condition-action c)))
                      (spec-fairness-conditions spec))
              :to-equal '((:weak step)))
      (expect (spec-symmetry spec) :to-equal '(procs))
      (expect (spec-check-deadlock spec) :to-be nil)
      (expect (mapcar #'spec-temporal-property-kind (spec-temporal-properties spec))
              :to-equal '(:eventually :leads-to))
      (let ((leads-to (second (spec-temporal-properties spec))))
        (expect (funcall (spec-temporal-property-predicate leads-to) '(x 1)) :to-be t)
        (expect (funcall (spec-temporal-property-consequent leads-to) '(x 1)) :to-be nil))))

  (it "checks deadlock by default"
    (expect (spec-check-deadlock (counter)) :to-be t))

  (it "rejects malformed specifications at macroexpansion"
    (dolist (form '((specification bad () (:variables x))
                    (specification bad () (:init (x 0)))
                    (specification bad () (:variables x) (:init (x 0) (y 1)))
                    (specification bad () (:variables x) (:init (x 0)) (:bogus))
                    (specification bad () (:variables x) (:init (x 0))
                     (:action a (:next (z 1))))
                    (specification bad () (:variables x) (:init (x 0))
                     (:action a (:for (x '(1))) (:next (x 1))))
                    (specification bad () (:variables x) (:init (x 0))
                     (:temporal p (:sometimes (= x 1))))
                    (specification bad () (:variables x) (:init (x 0))
                     (:fairness (:medium a)))))
      (expect (handler-case (progn (macroexpand-1 form) :no-error)
                (spec-definition-error () :signalled))
              :to-be :signalled))))

(describe "MAKE-SPEC validation"
  (flet ((build (&rest overrides)
           (apply #'make-spec
                  (append overrides
                          (list :name 'valid :variables '(x)
                                :init (lambda () (list (list 'x 0))))))))
    (it "accepts a minimal specification"
      (expect (spec-p (build)) :to-be t))

    (it "rejects duplicate variables"
      (signals-error-of-type spec-definition-error
        (make-spec :name 'dup :variables '(x x) :init (lambda () nil))))

    (it "rejects a symmetry name that is not a constant"
      (signals-error-of-type spec-definition-error (build :symmetry '(procs))))

    (it "rejects fairness on an undeclared action"
      (signals-error-of-type spec-definition-error
        (build :fairness-conditions (list (make-spec-fairness-condition
                                           :kind :weak :action 'missing)))))

    (it "rejects duplicate property names across kinds"
      (signals-error-of-type spec-definition-error
        (build :invariants (list (make-spec-invariant :name 'p :predicate (constantly t)))
               :action-properties (list (make-spec-action-property
                                         :name 'p :relation (constantly t))))))

    (it "rejects a :leads-to property without a consequent"
      (signals-error-of-type spec-definition-error
        (build :temporal-properties
               (list (make-spec-temporal-property
                      :name 'p :kind :leads-to :predicate (constantly t))))))

    (it "rejects a consequent on any other kind"
      (signals-error-of-type spec-definition-error
        (build :temporal-properties
               (list (make-spec-temporal-property
                      :name 'p :kind :always :predicate (constantly t)
                      :consequent (constantly t))))))))

(describe "spec results"
  (it "passes a clean complete search"
    (expect (spec-result-passed-p (make-spec-result)) :to-be t))

  (it "fails on a violation"
    (expect (spec-result-passed-p
             (make-spec-result :violation (make-spec-violation :kind :invariant)))
            :to-be nil))

  (it "fails a truncated search by default"
    (expect (spec-result-passed-p
             (make-spec-result :truncated t :truncation-reason :max-states))
            :to-be nil))

  (it "passes a truncated search only when bounded checking was allowed"
    (expect (spec-result-passed-p
             (make-spec-result :truncated t :truncation-reason :max-states
                               :allow-bounded t))
            :to-be t))

  (it "never passes a truncated search that requested temporal properties"
    (expect (spec-result-passed-p
             (make-spec-result :truncated t :truncation-reason :max-states
                               :allow-bounded t :liveness-requested '(done)))
            :to-be nil))

  (it "passes a complete search that requested temporal properties"
    (expect (spec-result-passed-p
             (make-spec-result :liveness-requested '(done)))
            :to-be t))

  (it "defaults every budget to a finite number"
    (dolist (limit (list *default-max-states* *default-max-depth*
                         *default-max-simulation-steps* *default-linearization-budget*))
      (expect (and (integerp limit) (plusp limit)) :to-be t))))

(describe "state fingerprints"
  (it "agrees for EQUAL values built separately"
    (expect (state-fingerprint (list 'x 1 'y (list "a" #\b 2.5)))
            :to-be (state-fingerprint (list 'x 1 'y (list "a" #\b 2.5)))))

  (it "separates values that differ in one position"
    (let ((fingerprints (mapcar #'state-fingerprint
                                '((x 0) (x 1) (x 2) (y 0) (x 0 y 0) (x (0)) (x nil)))))
      (expect (length (remove-duplicates fingerprints)) :to-be (length fingerprints))))

  (it "fits in 62 bits"
    (expect (typep (state-fingerprint '(x 1 y (2 3))) '(unsigned-byte 62)) :to-be t)))

(describe "state tables"
  (it "finds a key by EQUAL, not identity"
    (let ((table (make-state-table)))
      (setf (state-table-ref table (list 'x 1)) :one)
      (expect (multiple-value-list (state-table-ref table (list 'x 1))) :to-equal '(:one t))
      (expect (multiple-value-list (state-table-ref table (list 'x 2))) :to-equal '(nil nil))))

  (it "overwrites without growing and counts distinct keys"
    (let ((table (make-state-table)))
      (setf (state-table-ref table '(x 1)) 1)
      (setf (state-table-ref table '(x 1)) 2)
      (setf (state-table-ref table '(x 2)) 3)
      (expect (state-table-count table) :to-be 2)
      (expect (state-table-ref table '(x 1)) :to-be 2)))

  (it "maps in insertion order"
    (let ((table (make-state-table))
          (seen '()))
      (dolist (key '((x 3) (x 1) (x 2)))
        (setf (state-table-ref table key) t))
      (map-state-table (lambda (key value) (declare (ignore value)) (push key seen)) table)
      (expect (nreverse seen) :to-equal '((x 3) (x 1) (x 2)))))

  (it "keeps many states that share a long common prefix apart"
    (let ((table (make-state-table)))
      (dotimes (index 500)
        (setf (state-table-ref table (list 'a 0 'b 0 'c 0 'd 0 'e 0 'f index)) index))
      (expect (state-table-count table) :to-be 500)
      (expect (state-table-ref table (list 'a 0 'b 0 'c 0 'd 0 'e 0 'f 321)) :to-be 321))))

(describe "state graph"
  (it "starts incomplete with an empty edge table"
    (let ((graph (make-state-graph :spec (counter) :initial-states '((x 0)))))
      (expect (state-graph-complete-p graph) :to-be nil)
      (expect (state-table-count (state-graph-edges graph)) :to-be 0))))
