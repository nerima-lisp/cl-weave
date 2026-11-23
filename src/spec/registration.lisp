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

;;; The skip and todo forms keep the check form inside the test body, so it is
;;; never evaluated while the test is registered or run. IT-SKIP and IT-TODO
;;; cannot take a body, so this builds the same registration form they do.
;;; Syntax: (it-spec-skip name [reason] [options-plist] check-form), where the
;;; reason defaults to the same string as IT-SKIP or IT-TODO.
(defun spec-skipped-registration-form (macro-name name body reason-key default-reason)
  (multiple-value-bind (reason rest-body)
      (cl-weave::split-reasoned-body body default-reason)
    (multiple-value-bind (options forms)
        (cl-weave::split-leading-option-plist rest-body)
      (unless (and forms (null (rest forms)))
        (cl-weave::registration-syntax-error
         "~S requires exactly one check form after an optional reason and options plist, got ~S."
         macro-name forms))
      (let* ((check-form (first forms))
             (test-body `(report-spec-result ,check-form :form ',check-form)))
        (cl-weave::test-registration-form
         name
         (list test-body)
         (cl-weave::test-options-with-registration-options
          options (list reason-key reason)))))))

(defmacro it-spec-skip (name &body body)
  (spec-skipped-registration-form 'it-spec-skip name body :skip-reason "skipped"))

(defmacro it-spec-todo (name &body body)
  (spec-skipped-registration-form 'it-spec-todo name body :todo-reason "todo"))
