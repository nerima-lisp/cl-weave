(in-package #:cl-weave/spec-test)

(defun conformance-trace-summary (trace)
  (mapcar (lambda (step)
            (list (trace-step-action step) (trace-step-params step)
                  (trace-step-state step)))
          trace))

(defspec conformance-counter ()
  (:variables x)
  (:init (x 0))
  (:action inc (:next (x (1+ x))) (:output (next x))))

(defun conformance-reset () (list 0))
(defun conformance-abstraction (sut) (list 'x (first sut)))
(defun conformance-inc (sut) (incf (first sut)))

(describe "spec sequential conformance"
  (it "reports the initial mismatch at step zero"
    (let* ((result (check-sequential-conformance
                    (conformance-counter) :reset (lambda () (list 9))
                    :operations (list (cons 'inc #'conformance-inc))
                    :abstraction #'conformance-abstraction :runs 1 :max-steps 2))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (getf detail :step) :to-be 0)
      (expect (getf detail :what) :to-be :state)
      (expect (getf detail :actual) :to-equal '(x 9))))
  (it "reports a wrong output with a correct next state"
    (let* ((result (check-sequential-conformance
                    (conformance-counter) :reset #'conformance-reset
                    :operations (list (cons 'inc (lambda (sut) (incf (first sut)) :wrong)))
                    :abstraction #'conformance-abstraction :runs 1 :max-steps 3 :seed 8))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (getf detail :step) :to-be 1)
      (expect (getf detail :action) :to-be 'inc)
      (expect (getf detail :params) :to-equal nil)
      (expect (getf detail :what) :to-be :output)
      (expect (getf detail :expected) :to-be 1)
      (expect (getf detail :actual) :to-be :wrong)
      (expect (conformance-trace-summary (spec-violation-trace violation))
              :to-equal '((nil nil (x 0)) (inc nil (x 1))))))
  (it "reports the operation exception and its content"
    (let* ((result (check-sequential-conformance
                    (conformance-counter) :reset #'conformance-reset
                    :operations (list (cons 'inc (lambda (sut) (declare (ignore sut))
                                                   (error "operation exploded"))))
                    :abstraction #'conformance-abstraction :runs 1 :max-steps 2))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (getf detail :action) :to-be 'inc)
      (expect (not (null (search "operation exploded" (format nil "~A" detail)))) :to-be t)))
  (it "ends a run at a deadlock without executing an operation"
    (let ((calls 0))
      (let ((result (check-sequential-conformance
                     (counter :limit 0) :reset #'conformance-reset
                     :operations (list (cons 'inc (lambda (sut) (declare (ignore sut)) (incf calls))))
                     :abstraction #'conformance-abstraction :runs 2 :max-steps 3)))
        (expect (spec-result-passed-p result) :to-be t)
        (expect calls :to-be 0))))
  (it "rejects a missing operation before reset"
    (let ((resets 0))
      (expect (lambda ()
                (check-sequential-conformance
                 (conformance-counter) :reset (lambda () (incf resets) (list 0))
                 :operations nil :abstraction #'conformance-abstraction))
              :to-throw 'spec-configuration-error)
      (expect resets :to-be 0)))
  (it "uses each reset's matching initial state"
    (let ((resets 0)
          (spec (specification two-initials ()
                  (:variables x) (:init (x (:in (list 0 1))))
                  (:action inc (:next (x (1+ x)))))))
      (let ((result (check-sequential-conformance
                     spec :reset (lambda () (list (mod (incf resets) 2)))
                     :operations (list (cons 'inc #'conformance-inc))
                     :abstraction #'conformance-abstraction
                     :mode :random :seed 4 :runs 4 :max-steps 2)))
        (expect (spec-result-passed-p result) :to-be t)
        (expect resets :to-be 4))))
  (it "checks a correct implementation in both modes and records limits"
    (dolist (mode '(:random :tree))
      (let ((result (check-sequential-conformance
                     (counter :limit 2) :reset #'conformance-reset
                     :operations (list (cons 'inc #'conformance-inc))
                     :abstraction #'conformance-abstraction :mode mode
                     :seed 3 :runs 2 :max-steps 4 :depth 3 :max-states 20)))
        (expect (spec-result-passed-p result) :to-be t)
        (expect (spec-result-mode result) :to-be :sequential-conformance)
        (expect (spec-result-checked-properties result) :to-equal nil)
        (expect (spec-result-limits result)
                :to-equal (if (eq mode :random) '(:runs 2 :max-steps 4)
                              '(:max-depth 3 :max-states 20))))))
  (it "honors the tree budget and allow-bounded"
    (flet ((run (allow)
             (check-sequential-conformance
              (conformance-counter) :reset #'conformance-reset
              :operations (list (cons 'inc #'conformance-inc))
              :abstraction #'conformance-abstraction :mode :tree :depth 3
              :max-states 1 :allow-bounded allow)))
      (let ((bounded (run nil)) (allowed (run t)))
        (expect (spec-result-truncated bounded) :to-be t)
        (expect (spec-result-passed-p bounded) :to-be nil)
        (expect (spec-result-truncated allowed) :to-be t)
        (expect (spec-result-passed-p allowed) :to-be t))))
  (it "shrinks a sequence exposing a single implementation bug"
    (let* ((spec (specification shrink-bug ()
                   (:variables x) (:init (x 0))
                   (:action idle (:next (x x)))
                   (:action inc (:next (x (1+ x))))))
           (result (check-sequential-conformance
                    spec :reset #'conformance-reset
                    :operations (list (cons 'idle (lambda (sut) (declare (ignore sut))))
                                      (cons 'inc (lambda (sut) (incf (first sut) 2))))
                    :abstraction #'conformance-abstraction
                    :mode :random :seed 2 :runs 10 :max-steps 8))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (getf detail :what) :to-be :state)
      (expect (getf detail :expected) :to-equal '(x 1))
      (expect (getf detail :actual) :to-equal '(x 2))
      (expect (conformance-trace-summary (getf detail :original-trace))
              :to-equal '((nil nil (x 0)) (idle nil (x 0)) (inc nil (x 1))))
      (expect (conformance-trace-summary (spec-violation-trace violation))
              :to-equal '((nil nil (x 0)) (inc nil (x 1)))))))

(describe "spec sequential conformance tree bounds"
  (it "checks a looping state once without exhausting the depth bound"
    (let* ((spec (specification loop-state ()
                   (:variables x) (:init (x 0))
                   (:action stay (:next (x x)))))
           (result (check-sequential-conformance
                    spec :reset #'conformance-reset
                    :operations (list (cons 'stay (lambda (sut) (declare (ignore sut)))))
                    :abstraction #'conformance-abstraction
                    :mode :tree :depth 2 :max-states 1)))
      (expect (spec-result-states-found result) :to-be 1)
      (expect (spec-result-truncated result) :to-be nil)
      (expect (spec-result-passed-p result) :to-be t))))

(describe "spec sequential conformance tree initial states"
  (it "signals both initial states when tree reset changes to another valid state"
    (let ((*package* (find-package :cl-weave/spec-test))
          (resets 0)
          (spec (specification two-tree-initials ()
                  (:variables x) (:init (x (:in (list 0 1))))
                  (:action inc (:next (x (1+ x)))))))
      (let ((message
              (handler-case
                  (progn
                    (check-sequential-conformance
                     spec :reset (lambda () (list (mod (incf resets) 2)))
                     :operations (list (cons 'inc #'conformance-inc))
                     :abstraction #'conformance-abstraction
                     :mode :tree :depth 2 :max-states 20)
                    nil)
                (spec-configuration-error (condition)
                  (string-upcase (spec-error-message condition))))))
        (expect (stringp message) :to-be t)
        (expect (not (null (search "(X 0)" message))) :to-be t)
        (expect (not (null (search "(X 1)" message))) :to-be t))))
  (it "reports a later reset outside all initial states at step zero"
    (let ((resets 0)
          (spec (specification invalid-tree-reset ()
                  (:variables x) (:init (x (:in (list 0 1))))
                  (:action inc (:next (x (1+ x)))))))
      (let* ((result (check-sequential-conformance
                      spec :reset (lambda () (list (if (= (incf resets) 1) 0 9)))
                      :operations (list (cons 'inc #'conformance-inc))
                      :abstraction #'conformance-abstraction
                      :mode :tree :depth 2 :max-states 20))
             (detail (spec-violation-detail (spec-result-violation result))))
        (expect (spec-result-passed-p result) :to-be nil)
        (expect (getf detail :step) :to-be 0)
        (expect (getf detail :what) :to-be :state)
        (expect (getf detail :actual) :to-equal '(x 9)))))
  (it "explores only the initial state supplied by the first reset"
    (let ((calls 0)
          (spec (specification selected-tree-root ()
                  (:variables x) (:init (x (:in (list 0 1))))
                  (:action advance (:guard (= x 0)) (:next (x 2)))
                  (:action other (:guard (= x 1)) (:next (x 3))))))
      (let ((result (check-sequential-conformance
                     spec :reset #'conformance-reset
                     :operations (list (cons 'advance (lambda (sut) (incf calls) (setf (first sut) 2)))
                                       (cons 'other (lambda (sut) (declare (ignore sut)) (error "unreachable"))))
                     :abstraction #'conformance-abstraction
                     :mode :tree :depth 2 :max-states 20)))
        (expect (spec-result-passed-p result) :to-be t)
        (expect calls :to-be 1)
        (expect (spec-result-states-found result) :to-be 2)))))

(describe "spec sequential conformance regression cases"
  (it "checks both self-loop transitions without expanding paths exponentially"
    (let ((resets 0) (first-calls 0) (second-calls 0)
          (spec (specification two-loops ()
                  (:variables x) (:init (x 0))
                  (:action first-loop (:next (x x)))
                  (:action second-loop (:next (x x))))))
      (let ((result (check-sequential-conformance
                     spec :reset (lambda () (incf resets) (list 0))
                     :operations (list (cons 'first-loop (lambda (sut) (declare (ignore sut)) (incf first-calls)))
                                       (cons 'second-loop (lambda (sut) (declare (ignore sut)) (incf second-calls))))
                     :abstraction #'conformance-abstraction
                     :mode :tree :depth 12 :max-states 10)))
        (expect (spec-result-passed-p result) :to-be t)
        (expect (spec-result-states-found result) :to-be 1)
        (expect first-calls :to-be 1)
        (expect second-calls :to-be 1)
        (expect (<= resets 4) :to-be t))))
  (it "shrinks a violation despite alternating valid reset states"
    (let ((resets 0)
          (spec (specification alternating-shrink ()
                  (:variables x) (:init (x (:in (list 0 1))))
                  (:action idle (:next (x x)))
                  (:action inc (:next (x (1+ x)))))))
      (let* ((result (check-sequential-conformance
                      spec :reset (lambda () (list (mod (1- (incf resets)) 2)))
                      :operations (list (cons 'idle (lambda (sut) (declare (ignore sut))))
                                        (cons 'inc (lambda (sut) (incf (first sut) 2))))
                      :abstraction #'conformance-abstraction
                      :mode :random :seed 2 :runs 1 :max-steps 8))
             (violation (spec-result-violation result))
             (detail (spec-violation-detail violation)))
        (expect (getf detail :seed) :to-be 2)
        (expect (getf detail :case-index) :to-be 0)
        (expect (conformance-trace-summary (getf detail :original-trace))
                :to-equal '((nil nil (x 0)) (idle nil (x 0)) (inc nil (x 1))))
        (expect (conformance-trace-summary (spec-violation-trace violation))
                :to-equal '((nil nil (x 0)) (inc nil (x 1)))))))
  (it "reports unsuccessful shrink attempts when the root cannot be reset"
    (let ((resets 0)
          (spec (specification exhausted-shrink ()
                  (:variables x) (:init (x (:in (list 0 1))))
                  (:action idle (:next (x x)))
                  (:action inc (:next (x (1+ x)))))))
      (let* ((result (check-sequential-conformance
                      spec :reset (lambda () (list (if (= (incf resets) 1) 0 1)))
                      :operations (list (cons 'idle (lambda (sut) (declare (ignore sut))))
                                        (cons 'inc (lambda (sut) (incf (first sut) 2))))
                      :abstraction #'conformance-abstraction
                      :mode :random :seed 2 :runs 1 :max-steps 8))
             (violation (spec-result-violation result))
             (detail (spec-violation-detail violation)))
        (expect (spec-violation-kind violation) :to-be :conformance)
        (expect (> (getf detail :shrink-reset-exhausted 0) 0) :to-be t)
        (expect (conformance-trace-summary (spec-violation-trace violation))
                :to-equal '((nil nil (x 0)) (idle nil (x 0)) (inc nil (x 1)))))))
  (it "runs every operation from each reset's matching initial state"
    (let ((instances nil)
          (spec (specification per-run-operations ()
                  (:variables x) (:init (x (:in (list 0 1))))
                  (:action inc (:next (x (1+ x)))))))
      (let ((result (check-sequential-conformance
                     spec :reset (lambda () (let ((sut (list (mod (length instances) 2) 0)))
                                               (push sut instances) sut))
                     :operations (list (cons 'inc (lambda (sut) (incf (second sut)) (incf (first sut)))))
                     :abstraction #'conformance-abstraction
                     :mode :random :seed 4 :runs 4 :max-steps 2)))
        (expect (spec-result-passed-p result) :to-be t)
        (expect (mapcar #'second (reverse instances)) :to-equal '(2 2 2 2)))))
  (it "rejects noninteger seeds before reset"
    (dolist (seed '(nil 1.5 :invalid))
      (let ((resets 0))
        (expect (lambda ()
                  (check-sequential-conformance
                   (conformance-counter) :reset (lambda () (incf resets) (list 0))
                   :operations (list (cons 'inc #'conformance-inc))
                   :abstraction #'conformance-abstraction :seed seed))
                :to-throw 'spec-configuration-error)
        (expect resets :to-be 0)))))

(describe "spec sequential conformance case index"
  (it "records the index of a violation after an earlier passing run"
    (let ((resets 0)
          (spec (specification later-case ()
                  (:variables x) (:init (x (:in (list 0 1))))
                  (:action inc (:next (x (1+ x)))))))
      (let* ((result (check-sequential-conformance
                      spec :reset (lambda () (list (if (= (incf resets) 1) 0 1)))
                      :operations (list (cons 'inc (lambda (sut)
                                                    (incf (first sut) (if (zerop (first sut)) 1 2)))))
                      :abstraction #'conformance-abstraction
                      :mode :random :seed 17 :runs 2 :max-steps 1))
             (detail (spec-violation-detail (spec-result-violation result))))
        (expect (getf detail :seed) :to-be 17)
        (expect (getf detail :case-index) :to-be 1)
        (expect (getf detail :expected) :to-equal '(x 2))
        (expect (getf detail :actual) :to-equal '(x 3))))))
