(in-package #:cl-weave/spec)

;;; Test registration for specifications (FR-012). Each macro wraps one check
;;; form in REPORT-SPEC-RESULT and registers it through a core macro of the it
;;; family, so focus, tags, retry, timeout, filter and shard behave as they do
;;; for IT.

(defun spec-registration-form (macro-name name body target)
  (multiple-value-bind (options forms) (cl-weave::split-leading-option-plist body)
    (unless (and forms (null (rest forms)))
      (cl-weave::registration-syntax-error
       "~S requires exactly one check form after an optional options plist, got ~S."
       macro-name forms))
    (let* ((check-form (first forms))
           (test-body `(report-spec-result ,check-form :form ',check-form)))
      (if options
          `(,target ,name ,options ,test-body)
          `(,target ,name ,test-body)))))

(defmacro it-spec (name &body body)
  (spec-registration-form 'it-spec name body 'cl-weave:it))

(defmacro it-spec-only (name &body body)
  (spec-registration-form 'it-spec-only name body 'cl-weave:it-only))
