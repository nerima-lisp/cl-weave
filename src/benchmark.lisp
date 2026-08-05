(in-package #:cl-weave)

(defun ensure-non-negative-integer (value name)
  (unless (and (integerp value) (not (minusp value)))
    (error "cl-weave: ~A must be a non-negative integer, got ~S." name value))
  value)

(defun ensure-positive-integer (value name)
  (unless (and (integerp value) (plusp value))
    (error "cl-weave: ~A must be a positive integer, got ~S." name value))
  value)

(defun elapsed-milliseconds (start end)
  (* 1000d0 (/ (- end start) internal-time-units-per-second)))

(defun sample-elapsed-milliseconds (function iterations)
  "Run FUNCTION ITERATIONS times and return the average elapsed milliseconds per call."
  (let ((start (get-internal-real-time)))
    (loop repeat iterations do (funcall function))
    (/ (elapsed-milliseconds start (get-internal-real-time)) iterations)))

(defun measure (function &key (warmup 0) (samples 10) (iterations 1))
  "Measure FUNCTION after WARMUP calls and return a BENCHMARK-RESULT.

Each sample is the average elapsed milliseconds of ITERATIONS calls.  The
result is observational only; use per-test :TIMEOUT-MS for stable CI limits."
  (check-type function function)
  (ensure-non-negative-integer warmup "warmup")
  (ensure-positive-integer samples "samples")
  (ensure-positive-integer iterations "iterations")
  (loop repeat warmup do (funcall function))
  (make-benchmark-result
   :samples (loop repeat samples
                   collect (sample-elapsed-milliseconds function iterations))
   :iterations iterations
   :warmup warmup))

(defmacro benchmark ((&key (warmup 0) (samples 10) (iterations 1)) &body body)
  "Measure BODY with lexical bindings preserved and return a BENCHMARK-RESULT."
  `(measure (lambda () ,@body)
            :warmup ,warmup
            :samples ,samples
            :iterations ,iterations))

(defun benchmark-samples-or-error (result)
  (check-type result benchmark-result)
  (let ((samples (benchmark-result-samples result)))
    (unless samples
      (error "cl-weave: benchmark result contains no samples."))
    samples))

(defun minimum-ms (result)
  (reduce #'min (benchmark-samples-or-error result)))

(defun maximum-ms (result)
  (reduce #'max (benchmark-samples-or-error result)))

(defun mean-ms (result)
  (let ((samples (benchmark-samples-or-error result)))
    (/ (reduce #'+ samples) (length samples))))

(defun median-ms (result)
  (let* ((samples (sort (copy-list (benchmark-samples-or-error result)) #'<))
         (count (length samples))
         (middle (floor count 2)))
    (if (oddp count)
        (nth middle samples)
        (/ (+ (nth (1- middle) samples) (nth middle samples)) 2))))
