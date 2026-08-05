(in-package #:cl-weave)

(defun generated-property-values (generators rng)
  (mapcar (lambda (generator)
            (funcall (property-generator-produce generator) rng))
          generators))

(defun property-failure-condition (function values)
  (handler-case
      (progn
        (apply function values)
        nil)
    (error (condition)
      condition)))

(defgeneric same-property-failure-p (original candidate)
  (:documentation
   "Return true when CANDIDATE represents the same property failure as ORIGINAL."))

(defmethod same-property-failure-p ((original condition) (candidate condition))
  (eq (class-of original) (class-of candidate)))

(defmethod same-property-failure-p (original candidate)
  (declare (ignore original candidate))
  nil)

(defstruct (property-shrink-bounce
            (:constructor make-property-shrink-bounce (thunk)))
  (thunk nil :type function :read-only t))

(defun trampoline-property-shrink (step)
  (loop while (property-shrink-bounce-p step)
        do (setf step
                 (funcall (property-shrink-bounce-thunk step)))
        finally (return step)))

(defmacro bounce-property-shrink ((state-var) &body body)
  "Build a shrink continuation that defers BODY as a trampoline bounce
instead of calling it directly, so TRAMPOLINE-PROPERTY-SHRINK can drive
arbitrarily deep shrink recursion in a flat loop rather than the Lisp
call stack. STATE-VAR is bound to the argument the continuation receives."
  `(lambda (,state-var)
     (make-property-shrink-bounce (lambda () ,@body))))

(defun property-shrink-state-with
    (state &key
                (original (property-shrink-state-original state))
                (function (property-shrink-state-function state))
                (current (property-shrink-state-current state))
                (visited (property-shrink-state-visited state))
                (cyclic-visited (property-shrink-state-cyclic-visited state))
                (current-cyclic-p (property-shrink-state-current-cyclic-p state))
                (steps (property-shrink-state-steps state))
                (max-steps (property-shrink-state-max-steps state)))
  "Return a new PROPERTY-SHRINK-STATE copied from STATE, overriding only the
supplied keyword fields. PROPERTY-SHRINK-STATE is read-only, so every field
transition goes through here instead of re-listing all eight slots at each
call site."
  (make-property-shrink-state
   :original original
   :function function
   :current current
   :visited visited
   :cyclic-visited cyclic-visited
   :current-cyclic-p current-cyclic-p
   :steps steps
   :max-steps max-steps))

(defun property-shrink-state-with-attempt (state steps)
  (property-shrink-state-with state :steps steps))

(defun property-shrink-state-with-current (state current current-cyclic-p)
  (let ((visited (property-shrink-state-visited state))
        (cyclic-visited (property-shrink-state-cyclic-visited state)))
    (if current-cyclic-p
        (push current cyclic-visited)
        (setf (gethash current visited) t))
    (property-shrink-state-with state
                                 :current current
                                 :visited visited
                                 :cyclic-visited cyclic-visited
                                 :current-cyclic-p current-cyclic-p)))

(defun record-shrink-step-frame (index candidate accepted-p)
  "Record a :SHRINK-STEP journal frame for a shrink candidate attempt, a no-op
when journaling is inactive. INDEX is the generator argument position that
changed; CANDIDATE is the full argument tuple tried; ACCEPTED-P is whether it
reproduced the original failure and became the new, smaller shrink frontier.
Chronologically interleaving these with assertion frames turns a property
test's timeline into a visible record of how PROPERTY-RUNNER walked from the
first failing case down to the minimal one."
  (record-journal-frame :shrink-step :form candidate :expected index :pass accepted-p))

(defun property-shrink-candidate-changed-p
    (next current next-cyclic-p current-cyclic-p)
  "True when NEXT differs from CURRENT, using cycle-safe equality whenever
either side may be a circular structure."
  (not
   (if (or next-cyclic-p current-cyclic-p)
       (cycle-safe-candidate-equal-p next current #'equal)
       (equal next current))))

(defun property-shrink-candidate-unvisited-p (next next-cyclic-p state)
  "True when NEXT has not already been tried during this shrink, checking the
cyclic-visited list for circular candidates and the VISITED hash table
otherwise."
  (not
   (if next-cyclic-p
       (find-if
        (lambda (visited)
          (cycle-safe-candidate-equal-p next visited #'equal))
        (property-shrink-state-cyclic-visited state))
       (nth-value 1 (gethash next (property-shrink-state-visited state))))))

(defun call-property-shrink-candidate/k (state index candidate accept reject)
  (let* ((current (property-shrink-state-current state))
         (next (copy-list current)))
    (setf (nth index next) candidate)
    (let* ((next-cyclic-p
             (candidate-requires-safe-equality-p next #'equal))
           (candidate-condition
             (property-failure-condition
              (property-shrink-state-function state) next))
           (accepted-p
             (and
              (property-shrink-candidate-changed-p
               next current next-cyclic-p
               (property-shrink-state-current-cyclic-p state))
              (property-shrink-candidate-unvisited-p next next-cyclic-p state)
              candidate-condition
              (same-property-failure-p
               (property-shrink-state-original state) candidate-condition))))
      (record-shrink-step-frame index next accepted-p)
      (if accepted-p
          (funcall accept
                   (property-shrink-state-with-current
                    state next next-cyclic-p))
          (funcall reject state)))))

(defun try-property-shrink-candidates/k
    (state index candidates accept reject complete)
  (if (null candidates)
      (funcall reject state)
      (let ((next-steps
              (consume-property-shrink-budget
               (property-shrink-state-current state)
               (property-shrink-state-steps state)
               (property-shrink-state-max-steps state))))
        (if (null next-steps)
            (funcall complete state)
            (let ((attempted-state
                    (property-shrink-state-with-attempt state next-steps)))
              (call-property-shrink-candidate/k
               attempted-state index (first candidates) accept
               (bounce-property-shrink (rejected-state)
                 (try-property-shrink-candidates/k
                  rejected-state index (rest candidates)
                  accept reject complete))))))))

(defun advance-property-shrink/k
    (state generators index accept complete)
  (if (null generators)
      (funcall complete state)
      (let* ((generator (first generators))
             (value (nth index (property-shrink-state-current state)))
             (candidates (property-shrink-candidates generator value)))
        (try-property-shrink-candidates/k
         state index candidates accept
         (bounce-property-shrink (rejected-state)
           (advance-property-shrink/k
            rejected-state (rest generators) (1+ index)
            accept complete))
         complete))))

(defun shrink-property-state/k (state generators complete)
  (advance-property-shrink/k
   state generators 0
   (bounce-property-shrink (accepted-state)
     (shrink-property-state/k accepted-state generators complete))
   complete))

(defun shrink-property-values (generators values function &optional original-condition)
  (let* ((visited (make-hash-table :test #'equal))
         (values-cyclic-p
           (candidate-requires-safe-equality-p values #'equal))
         (cyclic-visited (when values-cyclic-p (list values))))
    (unless values-cyclic-p
      (setf (gethash values visited) t))
    (let ((state
            (make-property-shrink-state
             :original (or original-condition
                           (property-failure-condition function values))
             :function function
             :current values
             :visited visited
             :cyclic-visited cyclic-visited
             :current-cyclic-p values-cyclic-p
             :steps 0
             :max-steps
             (ensure-property-shrink-max-steps *property-shrink-max-steps*))))
      (trampoline-property-shrink
       (shrink-property-state/k
        state generators
        (lambda (final-state)
          (property-shrink-state-current final-state)))))))

(defun signal-property-failure (names form values minimal seed case-index condition)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher :property
    :actual (list :seed seed
                  :case-index case-index
                  :values values
                  :minimal minimal
                  :condition (let ((*print-circle* t))
                               (princ-to-string condition)))
    :expected names
    :negated nil
    :pass nil)))

(defun run-property (generators function names form)
  (let* ((seed (property-seed))
         (rng (make-property-rng-from-seed seed)))
    (loop for case-index from 0 below (property-test-count)
          for values = (generated-property-values generators rng)
          for condition = (property-failure-condition function values)
          when condition
            do (let ((minimal (shrink-property-values generators values function
                                                      condition)))
                 (signal-property-failure names form values minimal seed case-index condition))))
  t)
