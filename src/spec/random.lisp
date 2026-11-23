(in-package #:cl-weave/spec)

(defun random-spec-index (rng count)
  (floor (* count (cl-weave::property-random-below rng (expt 2 30))) (expt 2 30)))

(defun generate-action-sequence (spec rng &key (max-steps *default-max-simulation-steps*) on-step)
  (let* ((initials (spec-initial-states spec))
         (initial (nth (random-spec-index rng (length initials)) initials))
         (state initial)
         (calls '()))
    (unless (and on-step (funcall on-step initial nil))
      (dotimes (index max-steps)
        (let ((transitions (spec-successors spec state)))
          (unless transitions (return))
          (let ((transition (nth (random-spec-index rng (length transitions)) transitions)))
            (push (cons (spec-transition-action transition)
                        (spec-transition-params transition)) calls)
            (setf state (spec-transition-to transition))
            (when (and on-step (funcall on-step state transition)) (return))))))
    (values initial (nreverse calls))))

(defun replay-action-sequence (spec initial-state calls)
  (let ((state initial-state)
        (trace (list (make-trace-step :state initial-state))))
    (loop for call in calls
          for index from 0
          for transition = (find-if (lambda (candidate)
                                      (and (eq (car call) (spec-transition-action candidate))
                                           (equal (cdr call) (spec-transition-params candidate))))
                                    (spec-successors spec state))
          do (unless transition
               (return-from replay-action-sequence (values (nreverse trace) nil index)))
             (setf state (spec-transition-to transition))
             (push (make-trace-step :action (spec-transition-action transition)
                                    :params (spec-transition-params transition)
                                    :state state)
                   trace))
    (values (nreverse trace) t nil)))

(defun shrink-action-sequence (spec initial-state calls still-fails-p
                               &key (max-steps cl-weave::*property-shrink-max-steps*))
  (unless (typep max-steps '(integer 0 *))
    (error 'type-error :datum max-steps :expected-type '(integer 0 *)))
  (multiple-value-bind (trace valid-p) (replay-action-sequence spec initial-state calls)
    (unless (and valid-p (funcall still-fails-p trace))
      (return-from shrink-action-sequence (values calls 0))))
  (let ((current calls) (steps 0) (visited (make-hash-table :test #'equal)))
    (setf (gethash calls visited) t)
    (block shrinking
      (loop
        (let ((accepted nil) (size (length current)))
          (loop for count from size downto 1
                until accepted
                do (loop for start from 0 to (- size count)
                         for candidate = (append (subseq current 0 start)
                                                 (nthcdr (+ start count) current))
                         unless (gethash candidate visited)
                           do (when (>= steps max-steps)
                                (restart-case
                                    (error 'cl-weave:property-shrink-limit
                                           :values current :steps steps :max-steps max-steps)
                                  (cl-weave::accept-current ()
                                    (return-from shrinking (values current steps)))))
                              (incf steps)
                              (setf (gethash candidate visited) t)
                              (multiple-value-bind (trace valid-p)
                                  (replay-action-sequence spec initial-state candidate)
                                (let ((accept (and valid-p (funcall still-fails-p trace))))
                                  (cl-weave::record-shrink-step-frame 0 candidate accept)
                                  (when accept
                                    (setf current candidate accepted t)
                                    (return))))))
          (unless accepted (return (values current steps))))))))

(defun random-step-violation (spec previous step check-deadlock)
  (let* ((state (trace-step-state step))
         (property (and previous
                        (first (spec-check-action-properties
                                spec (trace-step-state previous) state))))
         (invariant (first (spec-check-invariants spec state))))
    (cond
      (property
       (make-spec-violation :kind :action-property :property property
                            :detail (list :from (trace-step-state previous) :to state
                                          :action (trace-step-action step)
                                          :params (trace-step-params step))))
      (invariant
       (make-spec-violation :kind :invariant :property invariant :detail (list :state state)))
      ((and check-deadlock (spec-deadlock-p spec state))
       (make-spec-violation :kind :deadlock :detail (list :state state))))))

(defun random-trace-violation (spec trace check-deadlock)
  (let ((prefix '()) (previous nil))
    (dolist (step trace)
      (push step prefix)
      (let ((violation (random-step-violation spec previous step check-deadlock)))
        (when violation
          (setf (spec-violation-trace violation) (reverse prefix))
          (return-from random-trace-violation violation)))
      (setf previous step))))

(defun simulate-spec (spec &key (runs (cl-weave::property-test-count))
                           (max-steps *default-max-simulation-steps*)
                           (seed (cl-weave::property-seed)) temporal allow-bounded
                           (check-deadlock :spec))
  (when temporal
    (signal-spec-error 'spec-configuration-error "Random search cannot check temporal properties."))
  (unless (and (integerp runs) (plusp runs))
    (signal-spec-error 'spec-configuration-error "RUNS must be a positive integer, got ~S." runs))
  (unless (and (integerp max-steps) (plusp max-steps))
    (signal-spec-error 'spec-configuration-error "MAX-STEPS must be a positive integer, got ~S." max-steps))
  (unless (integerp seed)
    (signal-spec-error 'spec-configuration-error "SEED must be an integer, got ~S." seed))
  (unless (member check-deadlock '(:spec t nil))
    (signal-spec-error 'spec-configuration-error "Invalid deadlock option ~S." check-deadlock))
  (let ((deadlock-p (if (eq check-deadlock :spec) (spec-check-deadlock spec) check-deadlock))
        (seen (make-state-table)) (steps 0) (depth-reached 0)
        (completed-runs 0) (result-violation nil))
    (loop for case-index from 0 below runs
          for rng = (cl-weave::make-property-rng-from-seed (+ seed case-index))
          do (let ((trace '()) (violation nil) (depth 0))
               (multiple-value-bind (initial calls)
                   (generate-action-sequence
                    spec rng :max-steps max-steps
                    :on-step (lambda (state transition)
                               (let ((step (make-trace-step
                                            :state state
                                            :action (when transition (spec-transition-action transition))
                                            :params (when transition (spec-transition-params transition)))))
                                 (setf (state-table-ref seen state) t)
                                 (when transition
                                   (incf steps)
                                   (incf depth)
                                   (setf depth-reached (max depth-reached depth)))
                                 (setf violation (random-step-violation spec (first trace) step deadlock-p))
                                 (push step trace)
                                 violation)))
                 (incf completed-runs)
                 (when violation
                   (let* ((original-trace (nreverse trace))
                          (kind (spec-violation-kind violation))
                          (property (spec-violation-property violation))
                          (minimal (shrink-action-sequence
                                    spec initial calls
                                    (lambda (candidate)
                                      (let ((found (random-trace-violation spec candidate deadlock-p)))
                                        (and found (eq kind (spec-violation-kind found))
                                             (equal property (spec-violation-property found)))))))
                          (minimal-trace (replay-action-sequence spec initial minimal)))
                     (setf result-violation (random-trace-violation spec minimal-trace deadlock-p))
                     (setf (spec-violation-detail result-violation)
                           (append (spec-violation-detail result-violation)
                                   (list :seed seed :case-index case-index
                                         :original-length (length calls)
                                         :shrunk-length (length minimal)
                                         :original-trace original-trace))))
                   (return)))))
    (make-spec-result
     :spec-name (spec-name spec) :mode :random :violation result-violation
     :states-found (state-table-count seen) :depth-reached depth-reached
     :allow-bounded allow-bounded
     :checked-properties (append (mapcar #'spec-invariant-name (spec-invariants spec))
                                 (mapcar #'spec-action-property-name (spec-action-properties spec))
                                 (when deadlock-p (list :deadlock)))
     :limits (list :runs runs :max-steps max-steps)
     :statistics (list :runs completed-runs :steps steps :seed seed))))