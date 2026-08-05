(in-package #:cl-weave)

(defvar *property-test-count* 100)
(defvar *property-seed* 8675309)
(defvar *recursive-generator-depth* nil)

(defparameter *property-shrink-max-steps* 1000)

(define-condition property-shrink-limit (error)
  ((values :initarg :values :reader property-shrink-limit-values)
   (steps :initarg :steps :reader property-shrink-limit-steps)
   (max-steps :initarg :max-steps :reader property-shrink-limit-max-steps))
  (:report (lambda (condition stream)
             (let ((*print-circle* t))
               (format stream "Property shrinking exceeded the ~D step limit at ~S."
                       (property-shrink-limit-max-steps condition)
                       (property-shrink-limit-values condition))))))

(defstruct property-rng
  state)

(defstruct property-generator
  name
  produce
  shrink)

(defstruct (property-shrink-state
            (:constructor make-property-shrink-state
                (&key original function current
                      (visited (make-hash-table :test #'equal))
                      (cyclic-visited nil)
                      (current-cyclic-p nil)
                      steps max-steps)))
  (original nil :read-only t)
  (function nil :read-only t)
  (current nil :read-only t)
  (visited (make-hash-table :test #'equal) :type hash-table :read-only t)
  (cyclic-visited nil :type list :read-only t)
  (current-cyclic-p nil :type boolean :read-only t)
  (steps 0 :type (integer 0 *) :read-only t)
  (max-steps 0 :type (integer 0 *) :read-only t))

(define-condition property-shrinker-error (error)
  ((generator :initarg :generator :reader property-shrinker-error-generator)
   (value :initarg :value :reader property-shrinker-error-value)
   (cause :initarg :cause :reader property-shrinker-error-cause))
  (:report (lambda (condition stream)
             (let ((*print-circle* t))
               (format stream "Property shrinker ~S failed for ~S: ~A"
                       (property-generator-name
                        (property-shrinker-error-generator condition))
                       (property-shrinker-error-value condition)
                       (property-shrinker-error-cause condition))))))

(defun ensure-property-shrink-candidates (candidates)
  (unless (finite-proper-list-p candidates)
    (error "Property shrinkers must return a finite proper list."))
  candidates)

(defun ensure-property-generator (value label)
  (unless (property-generator-p value)
    (error "cl-weave: ~A must be a property generator, got ~S." label value))
  value)

(defun ensure-property-generators (generators label)
  (when (null generators)
    (error "cl-weave: ~A requires at least one property generator." label))
  (mapcar (lambda (generator)
            (ensure-property-generator generator label))
          generators))

(defun property-shrink-candidates (generator value)
  (loop with supplied-p = nil
        with supplied-candidates = nil
        do (handler-case
        (return
          (ensure-property-shrink-candidates
           (if supplied-p
               (prog1 supplied-candidates
                 (setf supplied-p nil))
               (funcall (property-generator-shrink generator) value))))
      ((and error (not property-shrinker-error)) (cause)
        (restart-case
            (error 'property-shrinker-error
                   :generator generator
                   :value value
                   :cause cause)
          (retry-shrinker ()
            :report "Retry the failing shrinker."
            (setf supplied-p nil))
          (use-value (candidates)
            :report "Supply replacement shrink candidates."
            (setf supplied-p t
                  supplied-candidates candidates))
          (skip-shrinking ()
            :report "Skip shrinking this generated value."
            (return nil)))))))

(defun ensure-property-shrink-max-steps (max-steps)
  (unless (and (integerp max-steps) (not (minusp max-steps)))
    (error 'type-error
           :datum max-steps
           :expected-type '(integer 0 *)))
  max-steps)

(defun consume-property-shrink-budget (values steps max-steps)
  (if (< steps max-steps)
      (1+ steps)
      (restart-case
          (error 'property-shrink-limit
                 :values values
                 :steps steps
                 :max-steps max-steps)
        (accept-current () nil))))

(defconstant +maximum-numeric-token-length+ 128)

(defun parse-environment-integer (name value)
  (when (> (length value) +maximum-numeric-token-length+)
    (error "cl-weave: ~A must not exceed ~D characters."
           name
           +maximum-numeric-token-length+))
  (handler-case
      (parse-integer value :junk-allowed nil)
    (error ()
      (error "cl-weave: ~A must be an integer, got ~S." name value))))

(defun environment-integer (name fallback)
  (let ((value (uiop:getenv name)))
    (if (and value (plusp (length value)))
        (parse-environment-integer name value)
        fallback)))

(defun ensure-positive-property-count (count source)
  (unless (and (integerp count) (plusp count))
    (error "cl-weave: ~A must be a positive integer, got ~S." source count))
  count)

(defun property-test-count ()
  (ensure-positive-property-count
   (environment-integer "CL_WEAVE_PROPERTY_TESTS" *property-test-count*)
   "CL_WEAVE_PROPERTY_TESTS or *property-test-count*"))

(defun property-seed ()
  (environment-integer "CL_WEAVE_PROPERTY_SEED" *property-seed*))

(defconstant +property-rng-modulus+ 2147483648)

(defun make-property-rng-from-seed (seed)
  (make-property-rng :state (mod (abs seed) +property-rng-modulus+)))

(defconstant +property-rng-multiplier+ 1103515245)

(defconstant +property-rng-increment+ 12345)

(defun property-random-below (rng limit)
  (when (<= limit 0)
    (error "cl-weave: random limit must be positive, got ~S." limit))
  (setf (property-rng-state rng)
        (mod (+ (* (property-rng-state rng) +property-rng-multiplier+) +property-rng-increment+)
             +property-rng-modulus+))
  (mod (property-rng-state rng) limit))

(defun integer-shrink-candidates (value min max)
  (declare (type integer value min max))
  ;; Shrink toward zero. The most useful reachable target is the in-range value
  ;; closest to zero (0 when it is in range, otherwise the nearest bound), never
  ;; the raw MIN bound: for a negative range MIN is the *most* extreme value, so
  ;; offering it as a candidate could let the greedy runner accept a larger
  ;; magnitude than the input it was shrinking. Clamping zero into [MIN, MAX]
  ;; and halving toward zero both have magnitude <= |VALUE|, so a shrink step
  ;; never moves away from smaller.
  (let ((toward-zero (max min (min max 0))))
    (loop for candidate in (list toward-zero (truncate value 2))
          when (and (integerp candidate)
                    (<= min candidate max))
            collect candidate into candidates
          finally (return (remove-duplicates candidates :test #'eql)))))

(defun make-integer-producer (min max)
  (declare (type integer min max))
  (lambda (rng)
    (+ min (property-random-below rng (1+ (- max min))))))

(defun make-integer-shrinker (min max)
  (declare (type integer min max))
  (lambda (value)
    (integer-shrink-candidates value min max)))
