(in-package #:cl-weave/spec)

(defun conformance-violation (trace index action params expected actual what &optional condition)
  (make-spec-violation :kind :conformance :trace trace
                       :detail (append (list :step index :action action :params params
                                             :expected expected :actual actual :what what)
                                       (when condition (list :condition condition)))))

(defun conformance-run (spec initials reset operations abstraction trace
                        &optional (sut nil sut-supplied-p) actual strict)
  (unless sut-supplied-p
    (setf sut (funcall reset)
          actual (make-state spec (funcall abstraction sut))))
  (unless (member actual initials :test #'equal)
    (return-from conformance-run
      (conformance-violation (list (make-trace-step :state actual)) 0 nil nil
                             initials actual :state)))
  ;; A different valid reset cannot replay a path rooted at the previous state.
  (unless (equal actual (trace-step-state (first trace)))
    (when strict
      (signal-spec-error (quote spec-configuration-error)
                         "Tree reset changed initial state from ~S to ~S."
                         (trace-step-state (first trace)) actual))
    (return-from conformance-run nil))
  (loop for step in (rest trace)
        for previous = (first trace) then step
        for index from 1
        for action-name = (trace-step-action step)
        for params = (trace-step-params step)
        for action = (spec-find-action spec action-name)
        for expected-state = (trace-step-state step)
        for prefix = (subseq trace 0 (1+ index))
        do (multiple-value-bind (output condition)
               (handler-case (values (apply (cdr (assoc action-name operations)) sut params) nil)
                 (error (condition) (values nil condition)))
             (when condition
               (return-from conformance-run
                 (conformance-violation prefix index action-name params expected-state condition
                                        :state condition)))
             (let ((state (make-state spec (funcall abstraction sut))))
               (unless (equal state expected-state)
                 (return-from conformance-run
                   (conformance-violation prefix index action-name params expected-state state :state)))
               (when (spec-action-output action)
                 (let ((expected (apply (spec-action-output action)
                                        (trace-step-state previous) expected-state params)))
                   (unless (equal expected output)
                     (return-from conformance-run
                       (conformance-violation prefix index action-name params expected output :output))))))))
  nil)

(defun conformance-initial-spec (spec initial)
  (make-spec :name (spec-name spec) :constants (spec-constants spec)
             :variables (spec-variables spec) :init (lambda () (list initial))
             :actions (spec-actions spec)))

(defun check-sequential-conformance (spec &key reset operations abstraction (mode :random)
                                           (seed (cl-weave::property-seed))
                                           (runs (cl-weave::property-test-count))
                                           (max-steps *default-max-simulation-steps*)
                                           (depth *default-max-depth*)
                                           (max-states *default-max-states*) allow-bounded)
  (unless (member mode '(:random :tree))
    (signal-spec-error 'spec-configuration-error "Unknown conformance mode ~S." mode))
  (unless (if (eq mode :random)
              (and (typep runs '(integer 1 *)) (typep max-steps '(integer 1 *)))
              (and (typep depth '(integer 1 *)) (typep max-states '(integer 1 *))))
    (signal-spec-error 'spec-configuration-error "Conformance limits must be positive integers."))
  (dolist (action (spec-actions spec))
    (unless (and (assoc (spec-action-name action) operations)
                 (functionp (cdr (assoc (spec-action-name action) operations))))
      (signal-spec-error 'spec-configuration-error "Missing operation for action ~S."
                         (spec-action-name action))))
  (let ((initials (spec-initial-states spec))
        (seen (make-state-table)) (depth-reached 0) (steps 0) (runs-done 0)
        (truncation nil))
    (labels ((result (&optional violation)
               (make-spec-result :spec-name (spec-name spec) :mode :sequential-conformance
                                 :violation violation :states-found (state-table-count seen)
                                 :depth-reached depth-reached :truncated (not (null truncation))
                                 :truncation-reason truncation :allow-bounded allow-bounded
                                 :checked-properties nil
                                 :limits (if (eq mode :random)
                                             (list :runs runs :max-steps max-steps)
                                             (list :depth depth :max-states max-states))
                                 :statistics (list :runs runs-done :steps steps :seed seed)))
             (record-trace (trace)
               (loop for step in trace for level from 0
                     do (setf (state-table-ref seen (trace-step-state step)) t
                              depth-reached (max depth-reached level)))
               (incf steps (1- (length trace))))
             (finish (initial calls violation)
               (let* ((original (spec-violation-trace violation))
                      (minimal (shrink-action-sequence
                                spec initial calls
                                (lambda (candidate)
                                  (let* ((sut (funcall reset))
                                         (actual (make-state spec (funcall abstraction sut))))
                                    (conformance-run spec initials reset operations abstraction
                                                     candidate sut actual (eq mode :tree))))))
                      (trace (replay-action-sequence spec initial minimal))
                      (shrunk (let* ((sut (funcall reset))
                                     (actual (make-state spec (funcall abstraction sut))))
                                (conformance-run spec initials reset operations abstraction
                                                 trace sut actual (eq mode :tree)))))
                 (when shrunk
                   (setf violation shrunk))
                 (setf (spec-violation-detail violation)
                       (append (spec-violation-detail violation)
                               (list :original-trace original)))
                 (return-from check-sequential-conformance (result violation))))
             (run-path (initial calls &optional (sut nil sut-supplied-p) actual)
               (let* ((trace (replay-action-sequence spec initial calls))
                      (violation
                        (if sut-supplied-p
                            (conformance-run spec initials reset operations abstraction trace sut actual)
                            (let* ((sut (funcall reset))
                                   (actual (make-state spec (funcall abstraction sut))))
                              (conformance-run spec initials reset operations abstraction
                                               trace sut actual (eq mode :tree))))))
                 (incf runs-done)
                 (record-trace trace)
                 (when violation (finish initial calls violation)))))
      (if (eq mode :random)
          (dotimes (index runs)
            (let* ((sut (funcall reset))
                   (actual (make-state spec (funcall abstraction sut))))
              (unless (member actual initials :test #'equal)
                (incf runs-done)
                (return-from check-sequential-conformance
                  (result (conformance-violation (list (make-trace-step :state actual))
                                                 0 nil nil initials actual :state))))
              (multiple-value-bind (initial calls)
                  (generate-action-sequence (conformance-initial-spec spec actual)
                                            (cl-weave::make-property-rng-from-seed (+ seed index))
                                            :max-steps max-steps)
                (run-path initial calls sut actual))))
          (progn (labels ((visit (initial state calls level)
                       (when (and (not (nth-value 1 (state-table-ref seen state)))
                                  (= (state-table-count seen) max-states))
                         (setf truncation :max-states)
                         (return-from visit nil))
                       (run-path initial calls)
                       (let ((transitions (spec-successors spec state)))
                         (if (= level depth)
                             (when transitions (setf truncation :max-depth))
                             (dolist (transition transitions)
                               (when (eq truncation :max-states) (return))
                               (visit initial (spec-transition-to transition)
                                      (append calls (list (cons (spec-transition-action transition)
                                                                (spec-transition-params transition))))
                                      (1+ level)))))))
              (let* ((sut (funcall reset))
                     (actual (make-state spec (funcall abstraction sut))))
                (unless (member actual initials :test (function equal))
                  (incf runs-done)
                  (return-from check-sequential-conformance
                    (result (conformance-violation (list (make-trace-step :state actual))
                                                   0 nil nil initials actual :state))))
                (visit actual actual nil 0)))))
      (result))))
