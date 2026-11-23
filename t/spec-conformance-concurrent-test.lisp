(in-package #:cl-weave/spec-test)

(defspec concurrent-counter ()
  (:variables x)
  (:init (x 0))
  (:action inc (:next (x (1+ x))) (:output (next x))))

(defspec concurrent-counter-without-output ()
  (:variables x)
  (:init (x 0))
  (:action inc (:next (x (1+ x)))))

(defspec concurrent-counter-two-initials ()
  (:variables x)
  (:init (x (:in (list 0 5))))
  (:action inc (:next (x (1+ x))) (:output (next x))))

(defspec concurrent-choices ()
  (:variables x)
  (:init (x 0))
  (:action left (:next (x x)))
  (:action right (:next (x x))))

(defun concurrent-history-op (id output invoked returned)
  (make-history-operation :id id :thread id :action 'inc :params nil
                          :output output :invoked invoked :returned returned))

(describe "spec concurrent conformance"
  (it "accepts an empty history without concurrency capability"
    (let ((cl-weave::*platform-capabilities* nil))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-counter) nil)
        (expect linearizable :to-be t)
        (expect prefix :to-equal nil)
        (expect exceeded :to-be nil))))

  (it "accepts one operation with its declared output"
    (let ((op (concurrent-history-op 0 1 0 1)))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-counter) (list op))
        (expect linearizable :to-be t)
        (expect prefix :to-equal (list op))
        (expect exceeded :to-be nil))))

  (it "respects real-time order for non-overlapping operations"
    (let ((first (concurrent-history-op 0 2 0 1))
          (second (concurrent-history-op 1 1 2 3)))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-counter) (list second first))
        (expect linearizable :to-be nil)
        (expect prefix :to-equal nil)
        (expect exceeded :to-be nil))))

  (it "reorders fully overlapping operations to match outputs"
    (let ((first (concurrent-history-op 0 2 0 3))
          (second (concurrent-history-op 1 1 1 2)))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-counter) (list first second))
        (expect linearizable :to-be t)
        (expect prefix :to-equal (list second first))
        (expect exceeded :to-be nil))))

  (it "reports a lost update from an unlocked counter deterministically"
    (let ((first (concurrent-history-op 0 1 0 3))
          (second (concurrent-history-op 1 1 1 2)))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-counter) (list second first))
        (expect linearizable :to-be nil)
        (expect prefix :to-equal (list first))
        (expect exceeded :to-be nil))))

  (it "ignores observed output when no output is declared"
    (let ((op (concurrent-history-op 0 :arbitrary 0 1)))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-counter-without-output) (list op))
        (expect linearizable :to-be t)
        (expect prefix :to-equal (list op))
        (expect exceeded :to-be nil))))

  (it "can start from any declared initial state"
    (let ((op (concurrent-history-op 0 6 0 1)))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-counter-two-initials) (list op))
        (expect linearizable :to-be t)
        (expect prefix :to-equal (list op))
        (expect exceeded :to-be nil))))

  (it "signals exhaustion when budget one cannot finish a nonempty history"
    (let ((op (concurrent-history-op 0 1 0 1)))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-counter) (list op) :budget 1)
        (expect linearizable :to-be nil)
        (expect prefix :to-equal nil)
        (expect exceeded :to-be t))))

  (it "requires the concurrency capability before executing operations"
    (let ((cl-weave::*platform-capabilities* nil)
          (resets 0))
      (expect (lambda ()
                (check-linearizability
                 (concurrent-counter) :reset (lambda () (incf resets))
                 :operations (list (cons 'inc (lambda (sut) sut)))))
              :to-throw 'cl-weave::platform-capability-unavailable)
      (expect resets :to-be 0)))

  (it "breaks equal-invocation prefix ties by operation id"
    (let ((higher (concurrent-history-op 9 1 0 3))
          (lower (concurrent-history-op 2 1 0 2)))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-counter) (list higher lower))
        (expect linearizable :to-be nil)
        (expect prefix :to-equal (list lower))
        (expect exceeded :to-be nil))))

  #+sb-thread
  (it "generates the same varied operation sequence for the same seed"
    (flet ((run-check ()
             (let ((sut (list nil)))
               (let ((result
                       (check-linearizability
                        (concurrent-choices) :reset (lambda () sut)
                        :operations (list (cons 'left (lambda (object) (push 'left (car object))))
                                          (cons 'right (lambda (object) (push 'right (car object)))))
                        :threads 1 :operations-per-thread 12 :runs 1 :seed 42)))
                 (expect (spec-result-passed-p result) :to-be t)
                 (reverse (car sut))))))
      (let ((expected '(left right right right left right right left left left left left)))
        (expect (run-check) :to-equal expected)
        (expect (run-check) :to-equal expected))))

  #+sb-thread
  (it "applies bounded checking policy to an exhausted budget"
    (flet ((run-check (allow-bounded)
             (check-linearizability
              (concurrent-counter)
              :reset (lambda () (cons (sb-thread:make-mutex) 0))
              :operations (list (cons 'inc
                                      (lambda (sut)
                                        (sb-thread:with-mutex ((car sut))
                                          (incf (cdr sut))))))
              :threads 1 :operations-per-thread 1 :runs 1 :seed 42
              :budget 1 :allow-bounded allow-bounded)))
      (let ((strict (run-check nil)) (bounded (run-check t)))
        (expect (spec-result-truncated strict) :to-be t)
        (expect (spec-result-truncation-reason strict) :to-be :budget)
        (expect (spec-result-limits strict) :to-equal '(:budget 1))
        (expect (spec-result-passed-p strict) :to-be nil)
        (expect (spec-result-truncated bounded) :to-be t)
        (expect (spec-result-passed-p bounded) :to-be t))))

  #+sb-thread
  (it "accepts a locked counter running on real threads"
    (let ((result
            (check-linearizability
             (concurrent-counter)
             :reset (lambda () (cons (sb-thread:make-mutex) 0))
             :operations (list (cons 'inc
                                     (lambda (sut)
                                       (sb-thread:with-mutex ((car sut))
                                         (incf (cdr sut))))))
             :threads 3 :operations-per-thread 3 :runs 2 :seed 42)))
      (expect (spec-result-mode result) :to-be :linearizability)
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-truncated result) :to-be nil))))

(defspec concurrent-parameterized ()
  (:variables x)
  (:init (x 0))
  (:action set-value (:for (v (list 1 2))) (:next (x v))))

(defspec concurrent-read ()
  (:variables x)
  (:init (x 0))
  (:action read-value (:next (x x)) (:output x)))

(describe "spec concurrent conformance R11"
  (it "rejects an operation whose parameters do not match a transition"
    (let ((operation (make-history-operation :id 0 :thread 0 :action 'set-value
                                             :params '(3) :invoked 0 :returned 1)))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-parameterized) (list operation))
        (expect linearizable :to-be nil)
        (expect prefix :to-equal nil)
        (expect exceeded :to-be nil))))

  (it "accepts an operation whose parameters match a transition"
    (let ((operation (make-history-operation :id 0 :thread 0 :action 'set-value
                                             :params '(2) :invoked 0 :returned 1)))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-parameterized) (list operation))
        (expect linearizable :to-be t)
        (expect prefix :to-equal (list operation))
        (expect exceeded :to-be nil))))

  (it "decides nine overlapping reads within the default budget"
    (let ((history (loop for id below 9
                         collect (make-history-operation
                                  :id id :thread id :action 'read-value :params nil
                                  :output (if (= id 8) 1 0)
                                  :invoked id :returned (+ 10 id)))))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-read) history)
        (expect linearizable :to-be nil)
        (expect exceeded :to-be nil)
        (expect prefix :to-equal (subseq history 0 8)))))

  #+sb-thread
  (it "reports a forced lost update from two real threads"
    (let* ((readers (sb-thread:make-semaphore :count 0))
           (result
             (check-linearizability
              (concurrent-counter) :reset (lambda () (list 0))
              :operations
              (list (cons 'inc
                          (lambda (sut)
                            (let ((old (car sut)))
                              (sb-thread:signal-semaphore readers)
                              (sb-thread:wait-on-semaphore readers :n 2)
                              (sb-thread:signal-semaphore readers 2)
                              (setf (car sut) (1+ old))))))
              :threads 2 :operations-per-thread 1 :runs 1 :seed 42))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-violation-kind violation) :to-be :linearizability)
      (expect (length (getf detail :history)) :to-be 2)
      (expect (length (getf detail :longest-prefix)) :to-be 1)))

  #+sb-thread
  (it "reports an operation condition as a conformance failure"
    (let* ((result (check-linearizability
                    (concurrent-counter) :reset (lambda () nil)
                    :operations (list (cons 'inc (lambda (sut)
                                                   (declare (ignore sut))
                                                   (error "forced operation failure"))))
                    :threads 1 :operations-per-thread 1 :runs 1 :seed 42))
           (violation (spec-result-violation result))
           (condition (getf (spec-violation-detail violation) :condition)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (typep condition 'simple-error) :to-be t)
      (expect (simple-condition-format-control condition) :to-equal "forced operation failure"))))

(defspec concurrent-write-read ()
  (:variables x)
  (:init (x 0))
  (:action set-value (:for (v (list 1 2))) (:next (x v)))
  (:action read-value (:next (x x)) (:output x)))

(describe "spec concurrent conformance memoization"
  (it "distinguishes states reached by the same completed operations"
    (let* ((first (make-history-operation :id 0 :thread 0 :action 'set-value
                                          :params '(1) :invoked 0 :returned 3))
           (second (make-history-operation :id 1 :thread 1 :action 'set-value
                                           :params '(2) :invoked 1 :returned 4))
           (read (make-history-operation :id 2 :thread 2 :action 'read-value
                                         :params nil :output 1 :invoked 5 :returned 6)))
      (multiple-value-bind (linearizable prefix exceeded)
          (linearizable-history-p (concurrent-write-read) (list first second read))
        (expect linearizable :to-be t)
        (expect prefix :to-equal (list second first read))
        (expect exceeded :to-be nil)))))
