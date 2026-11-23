(in-package #:cl-weave/spec)

(define-condition spec-error (error)
  ((message :initarg :message :reader spec-error-message))
  (:report (lambda (condition stream)
             (format stream "cl-weave/spec: ~A" (spec-error-message condition))))
  (:documentation "Base class of every error signalled by cl-weave/spec."))

(define-condition spec-definition-error (spec-error) ()
  (:documentation "A specification is malformed: bad names, duplicate
declarations, an update of an undeclared variable, an empty Init."))

(define-condition spec-configuration-error (spec-error) ()
  (:documentation "A check was requested with options that cannot be honoured,
for example liveness under random search. Signalled before any search starts."))

(define-condition spec-value-error (spec-error) ()
  (:documentation "A value-model operation was applied outside its domain."))

(define-condition spec-state-error (spec-error)
  ((variable :initarg :variable :reader spec-state-error-variable)
   (value :initarg :value :reader spec-state-error-value))
  (:documentation "A state variable holds a value that EQUAL cannot compare."))

(defun format-condition-message (control arguments)
  ;; Values reach messages through ~S; bounding the printer keeps a condition
  ;; from retaining or rendering an arbitrarily large state.
  (let ((*print-length* 20)
        (*print-level* 6)
        (*print-circle* t))
    (apply #'format nil control arguments)))

(defun signal-spec-error (type control &rest arguments)
  (error type :message (format-condition-message control arguments)))
