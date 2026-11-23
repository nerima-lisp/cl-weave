(in-package #:cl-weave/spec-test)

(defspec random-counter ()
  (:variables x) (:init (x 0))
  (:action inc (:next (x (1+ x))))
  (:invariant below-three (< x 3)))

(defun random-trace-summary (trace)
  (mapcar (lambda (step) (list (trace-step-action step)
                               (trace-step-params step)
                               (trace-step-state step))) trace))

(describe "spec random search"
  (it "finds an initial invariant violation without taking a step"
    (let* ((spec (specification bad-initial ()
                   (:variables x) (:init (x 0))
                   (:invariant positive (> x 0))))
           (violation (spec-result-violation
                       (simulate-spec spec :seed 7 :runs 1 :max-steps 2))))
      (expect (spec-violation-kind violation) :to-be :invariant)
      (expect (spec-violation-property violation) :to-be 'positive)
      (expect (random-trace-summary (spec-violation-trace violation))
              :to-equal '((nil nil (x 0))))))
  (it "finds a violation on the first transition"
    (let* ((spec (specification first-step ()
                   (:variables x) (:init (x 0))
                   (:action inc (:next (x (1+ x))))
                   (:invariant zero (zerop x))))
           (violation (spec-result-violation
                       (simulate-spec spec :seed 7 :runs 1 :max-steps 3))))
      (expect (spec-violation-kind violation) :to-be :invariant)
      (expect (random-trace-summary (spec-violation-trace violation))
              :to-equal '((nil nil (x 0)) (inc nil (x 1))))))
  (it "stops generating at a deadlock"
    (multiple-value-bind (initial calls)
        (generate-action-sequence (counter :limit 2)
                                  (cl-weave::make-property-rng-from-seed 42)
                                  :max-steps 8)
      (expect initial :to-equal '(x 0))
      (expect calls :to-equal '((inc) (inc)))))
  (it "reports a deadlock or permits it when checking is disabled"
    (let* ((spec (counter :limit 1))
           (failure (simulate-spec spec :seed 1 :runs 1 :max-steps 3))
           (pass (simulate-spec spec :seed 1 :runs 1 :max-steps 3
                                :check-deadlock nil)))
      (expect (spec-violation-kind (spec-result-violation failure)) :to-be :deadlock)
      (expect (spec-result-passed-p pass) :to-be t)
      (expect (spec-result-truncated pass) :to-be nil)))
  (it "replays only enabled calls and returns the valid prefix"
    (multiple-value-bind (trace ok failed-index)
        (replay-action-sequence (counter :limit 1) '(x 0) '((inc) (inc)))
      (expect ok :to-be nil)
      (expect failed-index :to-be 1)
      (expect (random-trace-summary trace)
              :to-equal '((nil nil (x 0)) (inc nil (x 1))))))
  (it "shrinks to zero calls when the initial state still fails"
    (multiple-value-bind (calls steps)
        (shrink-action-sequence (random-counter) '(x 0) '((inc) (inc))
                                (lambda (trace) (declare (ignore trace)) t))
      (expect calls :to-equal nil)
      (expect (> steps 0) :to-be t)))
  (it "does not shrink when the original sequence does not fail"
    (multiple-value-bind (calls steps)
        (shrink-action-sequence (random-counter) '(x 0) '((inc) (inc))
                                (lambda (trace) (declare (ignore trace)) nil))
      (expect calls :to-equal '((inc) (inc)))
      (expect steps :to-be 0)))
  (it "removes redundant calls while preserving a failure"
    (multiple-value-bind (calls steps)
        (shrink-action-sequence (random-counter) '(x 0)
                                '((inc) (inc) (inc) (inc))
                                (lambda (trace)
                                  (>= (state-ref (trace-step-state (car (last trace))) 'x) 2)))
      (expect calls :to-equal '((inc) (inc)))
      (expect (> steps 0) :to-be t)))
  (it "rejects candidate sequences whose guards are no longer enabled"
    (let ((spec (specification guarded ()
                  (:variables x) (:init (x 0))
                  (:action advance (:guard (zerop x)) (:next (x 1)))
                  (:action finish (:guard (= x 1)) (:next (x 2))))))
      (multiple-value-bind (calls steps)
          (shrink-action-sequence spec '(x 0) '((advance) (finish))
                                  (lambda (trace)
                                    (= (state-ref (trace-step-state (car (last trace))) 'x) 2)))
        (expect calls :to-equal '((advance) (finish)))
        (expect (> steps 0) :to-be t))))
  (it "signals the shrink limit and accepts the current candidate via restart"
    (let ((condition nil))
      (multiple-value-bind (calls steps)
          (handler-bind ((cl-weave:property-shrink-limit
                           (lambda (c) (setf condition c)
                             (invoke-restart 'cl-weave::accept-current))))
            (shrink-action-sequence (random-counter) '(x 0) '((inc) (inc))
                                    (lambda (trace) (declare (ignore trace)) t)
                                    :max-steps 0))
        (expect calls :to-equal '((inc) (inc)))
        (expect steps :to-be 0)
        (expect (cl-weave:property-shrink-limit-values condition) :to-equal '((inc) (inc)))
        (expect (cl-weave:property-shrink-limit-steps condition) :to-be 0)
        (expect (cl-weave:property-shrink-limit-max-steps condition) :to-be 0))))
  (it "repeats the same counterexample with the same seed"
    (let* ((first (simulate-spec (random-counter) :seed 37 :runs 2 :max-steps 5))
           (second (simulate-spec (random-counter) :seed 37 :runs 2 :max-steps 5))
           (a (spec-result-violation first)) (b (spec-result-violation second)))
      (expect (spec-violation-kind a) :to-be :invariant)
      (expect (random-trace-summary (spec-violation-trace a))
              :to-equal (random-trace-summary (spec-violation-trace b)))
      (expect (random-trace-summary (getf (spec-violation-detail a) :original-trace)) :to-equal (random-trace-summary (getf (spec-violation-detail b) :original-trace)))
      (expect (getf (spec-violation-detail a) :seed) :to-be 37)))
  (it "uses the environment seed when no seed is supplied"
    (cl-weave::with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name) (when (string= name "CL_WEAVE_PROPERTY_SEED") "123"))))
      (let ((result (simulate-spec (random-counter) :runs 1 :max-steps 3)))
        (expect (getf (spec-result-statistics result) :seed) :to-be 123)
        (expect (getf (spec-violation-detail (spec-result-violation result)) :seed)
                :to-be 123))))
  (it "rejects liveness before evaluating Init"
    (let* ((started nil)
           (spec (make-spec :name 'unstarted :variables '(x)
                            :init (lambda () (setf started t) '((x 0))))))
      (expect (lambda () (simulate-spec spec :temporal :all))
              :to-throw 'spec-configuration-error)
      (expect started :to-be nil)))
  (it "rejects nonpositive or noninteger run and step limits before Init"
    (dolist (bad '(0 -1 1.5 nil))
      (let* ((started nil)
             (spec (make-spec :name 'unstarted :variables '(x)
                              :init (lambda () (setf started t) '((x 0))))))
        (expect (lambda () (simulate-spec spec :runs bad))
                :to-throw 'spec-configuration-error)
        (expect (lambda () (simulate-spec spec :max-steps bad))
                :to-throw 'spec-configuration-error)
        (expect started :to-be nil)))))

(describe "spec random search result metadata"
  (it "records checked properties in declaration order and the requested limits"
    (let* ((spec (specification properties ()
                   (:variables x) (:init (x 0))
                   (:action inc (:next (x (1+ x))))
                   (:invariant nonnegative (>= x 0))
                   (:invariant finite (< x 100))
                   (:action-property grows (> (next x) x))))
           (result (simulate-spec spec :seed 8 :runs 2 :max-steps 4)))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-checked-properties result)
              :to-equal '(nonnegative finite grows :deadlock))
      (expect (spec-result-limits result) :to-equal '(:runs 2 :max-steps 4))
      (expect (spec-result-checked-properties
               (simulate-spec spec :seed 8 :runs 1 :max-steps 1 :check-deadlock nil))
              :to-equal '(nonnegative finite grows))))
  (it "retains the original trace in the violation detail"
    (let* ((result (simulate-spec (random-counter) :seed 37 :runs 1 :max-steps 5))
           (detail (spec-violation-detail (spec-result-violation result))))
      (expect (random-trace-summary (getf detail :original-trace))
              :to-equal '((nil nil (x 0)) (inc nil (x 1))
                          (inc nil (x 2)) (inc nil (x 3)))))))

(defspec random-choices ()
  (:variables origin history)
  (:init (origin (:in (list 0 1))) (history nil))
  (:action a (:next (history (append history (list 'a)))))
  (:action b (:next (history (append history (list 'b)))))
  (:invariant no-repeated-neighbors
    (not (loop for (a b) on history while b thereis (eq a b)))))

(describe "spec random search choices"
  (it "selects initial states and actions using the high bits of each draw"
    ;; The first six draws modulo 2^30 for seeds 0 and 100 are respectively
    ;; 12345 333190782 654583775 375725100 229283573 35593354 and
    ;; 829870797 459302786 404872851 284081872 413847241 70351310.
    ;; The two-way threshold is 536870912.
    (multiple-value-bind (initial calls)
        (generate-action-sequence (random-choices)
                                  (cl-weave::make-property-rng-from-seed 0)
                                  :max-steps 5)
      (expect initial :to-equal '(origin 0 history nil))
      (expect calls :to-equal '((a) (b) (a) (a) (a))))
    (multiple-value-bind (initial calls)
        (generate-action-sequence (random-choices)
                                  (cl-weave::make-property-rng-from-seed 100)
                                  :max-steps 5)
      (expect initial :to-equal '(origin 1 history nil))
      (expect calls :to-equal '((a) (a) (a) (a) (a)))))
  (it "uses independent run seeds and finds the second run's repeated actions"
    ;; Seed 4 chooses A B; seed 5 chooses B B after the Init draw.
    (let* ((result (simulate-spec (random-choices) :seed 4 :runs 2 :max-steps 2))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-violation-kind violation) :to-be :invariant)
      (expect (getf detail :case-index) :to-be 1)
      (expect (getf (spec-result-statistics result) :runs) :to-be 2)
      (expect (random-trace-summary (getf detail :original-trace))
              :to-equal '((nil nil (origin 0 history nil))
                          (b nil (origin 0 history (b)))
                          (b nil (origin 0 history (b b)))))))
  (it "shrinks a noisy generated failure and retains its original trace"
    ;; Seed 0 selects A B A A before the first repeated neighbor.
    (let* ((result (simulate-spec (random-choices) :seed 0 :runs 1 :max-steps 5))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (getf detail :original-length) :to-be 4)
      (expect (getf detail :shrunk-length) :to-be 2)
      (expect (random-trace-summary (getf detail :original-trace))
              :to-equal '((nil nil (origin 0 history nil))
                          (a nil (origin 0 history (a)))
                          (b nil (origin 0 history (a b)))
                          (a nil (origin 0 history (a b a)))
                          (a nil (origin 0 history (a b a a)))))
      (expect (random-trace-summary (spec-violation-trace violation))
              :to-equal '((nil nil (origin 0 history nil))
                          (a nil (origin 0 history (a)))
                          (a nil (origin 0 history (a a)))))))
  (it "replays quantified calls by action and parameter values"
    (multiple-value-bind (trace ok failed-index)
        (replay-action-sequence (chooser) '(x 0 y 0) '((set-x 2)))
      (expect ok :to-be t)
      (expect failed-index :to-be nil)
      (expect (random-trace-summary trace)
              :to-equal '((nil nil (x 0 y 0)) (set-x (2) (x 2 y 0)))))
    (multiple-value-bind (trace ok failed-index)
        (replay-action-sequence (chooser) '(x 0 y 0) '((set-x 9)))
      (expect ok :to-be nil)
      (expect failed-index :to-be 0)
      (expect (random-trace-summary trace) :to-equal '((nil nil (x 0 y 0))))))
  (it "never calls the failure predicate for an invalid replay"
    (let ((spec (specification guarded-prefix ()
                  (:variables x) (:init (x 0))
                  (:action advance (:guard (zerop x)) (:next (x 1)))
                  (:action finish (:guard (= x 1)) (:next (x 2)))))
          (invocations 0))
      (multiple-value-bind (calls steps)
          (shrink-action-sequence
           spec '(x 0) '((advance) (finish))
           (lambda (trace)
             (incf invocations)
             (let ((x (state-ref (trace-step-state (car (last trace))) 'x)))
               (or (= x 2) (and (= x 0) (> invocations 2))))))
        (expect calls :to-equal '((advance) (finish)))
        (expect steps :to-be 3)
        (expect invocations :to-be 3))))
  (it "does not spend budget or record frames twice for an identical candidate"
    (let ((frames (cl-weave:with-execution-journal
                    (multiple-value-bind (calls steps)
                        (shrink-action-sequence
                         (random-counter) '(x 0) '((inc) (inc) (inc))
                         (lambda (trace) (>= (length trace) 4)) :max-steps 3)
                      (expect calls :to-equal '((inc) (inc) (inc)))
                      (expect steps :to-be 3)))))
      (let ((shrink-frames (remove-if-not
                            (lambda (frame) (eq (cl-weave:journal-frame-kind frame) :shrink-step))
                            frames)))
        (expect (mapcar #'cl-weave:journal-frame-form shrink-frames)
                :to-equal '(nil ((inc)) ((inc) (inc)))))))
  (it "honors the spec deadlock setting and explicit overrides at the last step"
    (let ((spec (specification deadlock-disabled ()
                  (:variables x) (:init (x 0))
                  (:action inc (:guard (zerop x)) (:next (x 1)))
                  (:deadlock-check nil))))
      (expect (spec-result-passed-p
               (simulate-spec spec :seed 0 :runs 1 :max-steps 1 :check-deadlock :spec)) :to-be t)
      (expect (spec-result-passed-p
               (simulate-spec spec :seed 0 :runs 1 :max-steps 1 :check-deadlock nil)) :to-be t)
      (expect (spec-violation-kind
               (spec-result-violation
                (simulate-spec spec :seed 0 :runs 1 :max-steps 1 :check-deadlock t)))
              :to-be :deadlock)
      (expect (lambda () (simulate-spec spec :check-deadlock :invalid))
              :to-throw 'spec-configuration-error)))
  (it "rejects noninteger seeds before invoking Init"
    (dolist (bad '(nil 1.5 "4"))
      (let* ((started nil)
             (spec (make-spec :name 'unstarted :variables '(x)
                              :init (lambda () (setf started t) '((x 0))))))
        (expect (lambda () (simulate-spec spec :seed bad)) :to-throw 'spec-configuration-error)
        (expect started :to-be nil))))
  (it "does not evaluate guards after an initial violation"
    (let ((spec (specification bad-initial-guard ()
                  (:variables x) (:init (x 0))
                  (:action danger (:guard (error "guard evaluated")) (:next (x 1)))
                  (:invariant positive (> x 0)))))
      (expect (spec-violation-kind
               (spec-result-violation (simulate-spec spec :seed 0 :runs 1 :max-steps 2)))
              :to-be :invariant))))

(describe "spec random search seed replay"
  (it "repeats a multi-choice counterexample for the same seed and differs for another"
    (let* ((spec (random-choices))
           (first (spec-result-violation (simulate-spec spec :seed 0 :runs 1 :max-steps 5)))
           (again (spec-result-violation (simulate-spec spec :seed 0 :runs 1 :max-steps 5)))
           (other (spec-result-violation (simulate-spec spec :seed 5 :runs 1 :max-steps 5)))
           (first-trace (random-trace-summary (getf (spec-violation-detail first) :original-trace)))
           (again-trace (random-trace-summary (getf (spec-violation-detail again) :original-trace)))
           (other-trace (random-trace-summary (getf (spec-violation-detail other) :original-trace))))
      (expect first-trace :to-equal again-trace)
      (expect (equal first-trace other-trace) :to-be nil)
      (expect other-trace :to-equal '((nil nil (origin 0 history nil))
                                      (b nil (origin 0 history (b)))
                                      (b nil (origin 0 history (b b))))))))
