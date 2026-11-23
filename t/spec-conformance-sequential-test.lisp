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
                              '(:depth 3 :max-states 20))))))
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
  (it "counts a looping state once and reports the depth bound"
    (let* ((spec (specification loop-state ()
                   (:variables x) (:init (x 0))
                   (:action stay (:next (x x)))))
           (result (check-sequential-conformance
                    spec :reset #'conformance-reset
                    :operations (list (cons 'stay (lambda (sut) (declare (ignore sut)))))
                    :abstraction #'conformance-abstraction
                    :mode :tree :depth 2 :max-states 1)))
      (expect (spec-result-states-found result) :to-be 1)
      (expect (spec-result-truncated result) :to-be t)
      (expect (spec-result-truncation-reason result) :to-be :max-depth)
      (expect (spec-result-passed-p result) :to-be nil))))

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
