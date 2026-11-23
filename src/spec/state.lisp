(in-package #:cl-weave/spec)

;;;; A state is a property list whose keys are the specification's variable
;;;; names in declaration order, for example (x 0 y 1). It contains only values
;;;; that EQUAL compares structurally, so two states are the same state exactly
;;;; when they are EQUAL. Every module compares states with EQUAL and hashes
;;;; them with STATE-FINGERPRINT; none of them looks inside a value.

(defun state-ref (state variable)
  "Return the value of VARIABLE in STATE."
  (loop for (key value) on state by #'cddr
        when (eq key variable)
          do (return value)
        finally (signal-spec-error 'spec-definition-error
                                   "State ~S has no variable ~S."
                                   state variable)))

(defun comparable-leaf-p (object)
  (typep object '(or symbol number character string bit-vector pathname)))

(defun validate-comparable-value (value &optional variable)
  "Return VALUE when EQUAL can compare it structurally, otherwise signal
SPEC-STATE-ERROR naming VARIABLE. Conses are walked; their leaves must be
symbols, numbers, characters, strings, bit vectors or pathnames. Hash tables,
other arrays, structures, closures and CLOS instances compare by identity, so
two states holding equal-looking copies would be counted as different states."
  (labels ((walk (object)
             (loop
               (cond ((consp object)
                      (walk (car object))
                      (setf object (cdr object)))
                     ((comparable-leaf-p object) (return))
                     (t (error 'spec-state-error
                               :variable variable
                               :value object
                               :message (format-condition-message
                                         "State variable ~S holds ~S, which EQUAL compares by identity. Use lists, numbers, symbols, characters, strings or the value-model constructors."
                                         (list variable object))))))))
    (walk value)
    value))

;;; Fingerprints: FNV-1a style mixing over the structure of a value. EQUAL
;;; values have equal fingerprints because every leaf is hashed with SXHASH,
;;; which the standard requires to agree with EQUAL.

(deftype fingerprint () '(unsigned-byte 62))

(declaim (inline mix-fingerprint))
(defun mix-fingerprint (hash datum)
  (ldb (byte 62 0) (* (logxor hash datum) 1099511628211)))

(defun state-fingerprint (value)
  "Return a non-negative integer below 2^62 that is equal for EQUAL values.
It is deterministic across processes of the same implementation."
  (let ((hash (ldb (byte 62 0) 14695981039346656037)))
    (labels ((walk (object)
               (loop
                 (cond ((consp object)
                        (setf hash (mix-fingerprint hash 1))
                        (walk (car object))
                        (setf object (cdr object)))
                       (t (setf hash (mix-fingerprint hash (sxhash object)))
                          (return))))))
      (walk value))
    hash))

;;; State table: a map keyed by EQUAL values. SXHASH only looks at the first
;;; few elements of a long list, so an EQUAL hash table keyed by states
;;; degrades to long chains; buckets keyed by STATE-FINGERPRINT do not.
;;; Iteration is in insertion order, which keeps searches reproducible.

(defstruct (state-table (:constructor make-state-table ())
                        (:copier nil))
  (buckets (make-hash-table :test 'eql))
  (cells (make-array 16 :adjustable t :fill-pointer 0)))

(defun state-table-count (table)
  (length (state-table-cells table)))

(defun state-table-cell (table key)
  (find key (gethash (state-fingerprint key) (state-table-buckets table))
        :key #'car :test #'equal))

(defun state-table-ref (table key)
  "Return (values value found-p) for KEY, compared with EQUAL."
  (let ((cell (state-table-cell table key)))
    (if cell
        (values (cdr cell) t)
        (values nil nil))))

(defun (setf state-table-ref) (value table key)
  (let ((cell (state-table-cell table key)))
    (if cell
        (setf (cdr cell) value)
        (let ((new (cons key value)))
          (push new (gethash (state-fingerprint key) (state-table-buckets table)))
          (vector-push-extend new (state-table-cells table))
          value))))

(defun map-state-table (function table)
  "Call FUNCTION with each key and value in insertion order."
  (loop for cell across (state-table-cells table)
        do (funcall function (car cell) (cdr cell)))
  nil)
