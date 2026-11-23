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

;;; The skip and todo forms take the same arguments as IT-SKIP and IT-TODO, plus
;;; a check form last: (name [reason] [options-plist] check-form). The reason is
;;; a form evaluated at registration, as IT-SKIP evaluates its reason. The check
;;; form is only counted, never placed in the generated code, so no part of it
;;; is expanded or evaluated, at compile time or at run time. The test body is
;;; (nil), the same body IT-SKIP and IT-TODO register.
(defun spec-skipped-registration-form (macro-name name body reason-key default-reason)
  (let* ((check-form (car (last body)))
         (head (butlast body))
         (reason-given-p (and head (not (cl-weave::option-plist-form-p (first head)))))
         (reason (if reason-given-p (first head) default-reason))
         (option-forms (if reason-given-p (rest head) head)))
    (unless (and (consp check-form)
                 (<= (length option-forms) 1)
                 (every #'cl-weave::option-plist-form-p option-forms))
      (cl-weave::registration-syntax-error
       "~S requires a name, an optional reason, an optional options plist, and one check form, got ~S."
       macro-name body))
    (cl-weave::test-registration-form
     name
     '(nil)
     (cl-weave::test-options-with-registration-options
      (first option-forms) (list reason-key reason)))))

(defmacro it-spec-skip (name &body body)
  (spec-skipped-registration-form 'it-spec-skip name body :skip-reason "skipped"))

(defmacro it-spec-todo (name &body body)
  (spec-skipped-registration-form 'it-spec-todo name body :todo-reason "todo"))
