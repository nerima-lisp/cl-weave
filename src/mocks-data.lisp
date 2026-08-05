(in-package #:cl-weave)

(defconstant +mock-history-initial-capacity+ 16
  "Initial, and floor for regrown, capacity of a mock state's CALLS and
RESULTS history vectors. Shared with the growth step in
REGISTER-MOCK-CALL so the two never drift apart.")

(defstruct mock-state
  implementation
  (calls (make-array +mock-history-initial-capacity+ :adjustable t :fill-pointer 0))
  (results (make-array +mock-history-initial-capacity+ :adjustable t :fill-pointer 0))
  (generation 0)
  restore
  resident-spy-frame
  (disposed-p nil)
  #+sb-thread
  (lock (sb-thread:make-mutex :name "cl-weave mock state")))

(defstruct spy-frame
  symbol
  mock
  state
  original
  restored-p)

(define-condition mock-disposed-error (error)
  ((mock :initarg :mock :reader mock-disposed-error-mock))
  (:report
    (lambda (condition stream)
      (declare (ignore condition))
      (write-string "The mock has been disposed and can no longer be called." stream))))

(define-condition active-spy-disposal-error (error)
  ((mock :initarg :mock :reader active-spy-disposal-error-mock)
    (symbol :initarg :symbol :reader active-spy-disposal-error-symbol))
  (:report
    (lambda (condition stream)
      (format
        stream
        "Cannot dispose the spy for ~S while it is active."
        (active-spy-disposal-error-symbol condition)))))

(defvar *mock-states* (make-hash-table :test #'eq))

(defvar *spy-stacks* (make-hash-table :test #'eq))

#+sb-thread
(defvar *mock-registry-lock* (sb-thread:make-mutex :name "cl-weave mock registry"))
