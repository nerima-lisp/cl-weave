(in-package #:cl-weave/spec)

(defun generate-action-sequence (spec rng &key (max-steps *default-max-simulation-steps*))
  (let* ((initials (spec-initial-states spec))
         (initial (nth (cl-weave::property-random-below rng (length initials)) initials))
         (state initial)
         (calls '()))
    (dotimes (index max-steps)
      (let ((transitions (spec-successors spec state)))
        (unless transitions (return))
        (let ((transition (nth (cl-weave::property-random-below rng (length transitions))
                               transitions)))
          (push (cons (spec-transition-action transition)
                      (spec-transition-params transition)) calls)
          (setf state (spec-transition-to transition)))))
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
  (let ((current calls) (steps 0))
    (block shrinking
      (loop
        (let ((accepted nil) (size (length current)))
          (loop for count from size downto 1
                until accepted
                do (loop for start from 0 to (- size count)
                         for candidate = (append (subseq current 0 start)
                                                 (nthcdr (+ start count) current))
                         do (when (>= steps max-steps)
                              (restart-case
                                  (error 'cl-weave:property-shrink-limit
                                         :values current :steps steps :max-steps max-steps)
                                (cl-weave::accept-current ()
                                  (return-from shrinking (values current steps)))))
                            (incf steps)
                            (multiple-value-bind (trace valid-p)
                                (replay-action-sequence spec initial-state candidate)
                              (let ((accept (and valid-p (funcall still-fails-p trace))))
                                (cl-weave::record-shrink-step-frame 0 candidate accept)
                                (when accept
                                  (setf current candidate accepted t)
                                  (return))))))
          (unless accepted (return (values current steps))))))))

(defun random-trace-violation (spec trace check-deadlock)
  (let ((prefix '()) (previous nil))
    (dolist (step trace)
      (push step prefix)
      (let* ((state (trace-step-state step))
             (property (and previous
                            (first (spec-check-action-properties
                                    spec (trace-step-state previous) state))))
             (invariant (first (spec-check-invariants spec state)))
             (ordered (reverse prefix)))
        (cond
          (property
           (return-from random-trace-violation
             (make-spec-violation :kind :action-property :property property :trace ordered
                                  :detail (list :from (trace-step-state previous) :to state
                                                :action (trace-step-action step)
                                                :params (trace-step-params step)))))
          (invariant
           (return-from random-trace-violation
             (make-spec-violation :kind :invariant :property invariant :trace ordered
                                  :detail (list :state state))))
          ((and check-deadlock (spec-deadlock-p spec state))
           (return-from random-trace-violation
             (make-spec-violation :kind :deadlock :trace ordered :detail (list :state state))))))
      (setf previous step))))

(defun simulate-spec (spec &key (runs (cl-weave::property-test-count))
                           (max-steps *default-max-simulation-steps*)
                           (seed (cl-weave::property-seed)) temporal allow-bounded
                           (check-deadlock (spec-check-deadlock spec)))
  (when temporal
    (signal-spec-error 'spec-configuration-error "Random search cannot check temporal properties."))
  (unless (and (integerp runs) (plusp runs))
    (signal-spec-error 'spec-configuration-error "RUNS must be a positive integer, got ~S." runs))
  (unless (and (integerp max-steps) (plusp max-steps))
    (signal-spec-error 'spec-configuration-error "MAX-STEPS must be a positive integer, got ~S." max-steps))
  (let ((initials (spec-initial-states spec))
        (seen (make-state-table)) (steps 0) (depth-reached 0))
    (loop for case-index from 0 below runs
          for rng = (cl-weave::make-property-rng-from-seed (+ seed case-index))
          for initial = (nth (cl-weave::property-random-below rng (length initials)) initials)
          do (let ((state initial) (calls '())
                   (trace (list (make-trace-step :state initial))))
               (setf (state-table-ref seen state) t)
               (loop for depth from 0 to max-steps
                     for violation = (random-trace-violation spec trace check-deadlock)
                     do (when violation
                          (let* ((original-trace trace)
                                 (kind (spec-violation-kind violation))
                                 (property (spec-violation-property violation))
                                 (minimal (shrink-action-sequence
                                           spec initial calls
                                           (lambda (candidate)
                                             (let ((found (random-trace-violation spec candidate check-deadlock)))
                                               (and found (eq kind (spec-violation-kind found))
                                                    (equal property (spec-violation-property found)))))))
                                 (minimal-trace (replay-action-sequence spec initial minimal))
                                 (result-violation (random-trace-violation spec minimal-trace check-deadlock)))
                            (setf (spec-violation-detail result-violation)
                                  (append (spec-violation-detail result-violation)
                                          (list :seed seed :case-index case-index
                                                :original-length (length calls)
                                                :shrunk-length (length minimal)
                                                :original-trace original-trace)))
                            (return-from simulate-spec
                                         (make-spec-result
                                          :checked-properties (append (mapcar (function spec-invariant-name) (spec-invariants spec))
                                                                      (mapcar (function spec-action-property-name) (spec-action-properties spec))
                                                                      (when check-deadlock (list :deadlock)))
                                          :limits (list :runs runs :max-steps max-steps)
                                          :spec-name (spec-name spec) :mode :random
                                          :violation result-violation
                                          :states-found (state-table-count seen)
                                          :depth-reached depth-reached
                                          :allow-bounded allow-bounded
                                          :statistics (list :runs (1+ case-index)
                                                            :steps steps :seed seed)))))
                     (when (= depth max-steps) (return))
                     (let ((transitions (spec-successors spec state)))
                       (unless transitions (return))
                       (let ((transition (nth (cl-weave::property-random-below rng (length transitions))
                                              transitions)))
                         (setf state (spec-transition-to transition)
                               calls (append calls (list (cons (spec-transition-action transition)
                                                               (spec-transition-params transition))))
                               trace (append trace (list (make-trace-step
                                                          :action (spec-transition-action transition)
                                                          :params (spec-transition-params transition)
                                                          :state state))))
                         (setf (state-table-ref seen state) t)
                         (incf steps)
                         (setf depth-reached (max depth-reached (1+ depth)))))))) (make-spec-result
                                                                                   :checked-properties (append (mapcar (function spec-invariant-name) (spec-invariants spec))
                                                                                                               (mapcar (function spec-action-property-name) (spec-action-properties spec))
                                                                                                               (when check-deadlock (list :deadlock)))
                                                                                   :limits (list :runs runs :max-steps max-steps)
                                                                                   :spec-name (spec-name spec) :mode :random
                                                                                   :states-found (state-table-count seen) :depth-reached depth-reached
                                                                                   :allow-bounded allow-bounded
                                                                                   :statistics (list :runs runs :steps steps :seed seed)))
  )