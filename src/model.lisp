(in-package #:cl-weave)

;;;; The data the framework passes around: the suite and test-case records,
;;;; the assertion and event records the reporters read, and the conditions a
;;;; failing test signals. Also the assertion counting that expect-assertions
;;;; and expect-has-assertions verify, which is defined here because it is
;;;; entirely a matter of these records and conditions.

(defvar *test-context* nil)
(defvar *soft-assertion-sink* nil
  "When bound to an adjustable vector (inside WITH-SOFT-ASSERTIONS), a failing
assertion is collected there and execution continues instead of unwinding.")
(defvar *assertion-count* nil)
(defvar *expected-assertion-count* nil)
(defvar *expected-assertion-count-form* nil)
(defvar *has-assertions-required* nil)
(defvar *has-assertions-form* nil)

(defmacro define-record-class (name slots)
  "Define a CLOS data record and its public constructor and predicate."
  (let ((constructor (intern (format nil "MAKE-~A" name)))
        (predicate (intern (format nil "~A-P" name))))
    `(progn
       (defclass ,name ()
         ,(loop for slot in slots
                for initarg = (intern (symbol-name slot) :keyword)
                for accessor = (intern (format nil "~A-~A" name slot))
                collect `(,slot
                          :initarg ,initarg
                          :initform nil
                          :accessor ,accessor)))
       (defun ,constructor (&rest initargs)
         (apply #'make-instance ',name initargs))
       (defun ,predicate (value)
         (typep value ',name)))))

(define-record-class suite
  (name parent focus execution-mode skip-reason todo-reason
   children children-tail
   before-all before-all-tail
   after-all after-all-tail
   before-each before-each-tail
   around-each around-each-tail
   after-each after-each-tail))

(defmethod print-object ((suite suite) stream)
  (print-unreadable-object (suite stream :type t)
    (format stream "~S :children ~D"
            (suite-name suite)
            (length (suite-children suite)))))

(defmacro suite-hook (suite hook)
  (ecase hook
    (before-all `(suite-before-all ,suite))
    (after-all `(suite-after-all ,suite))
    (before-each `(suite-before-each ,suite))
    (around-each `(suite-around-each ,suite))
    (after-each `(suite-after-each ,suite))))

(define-record-class test-case
  (name function trusted-empty-function focus skip-reason todo-reason retry timeout-ms
   execution-mode expected-failure-reason location tags watch-dependencies))

(defmethod print-object ((test test-case) stream)
  (print-unreadable-object (test stream :type t)
    (format stream "~S :focus ~S"
            (test-case-name test)
            (test-case-focus test))))

(define-record-class assertion-detail
  (form matcher actual expected negated pass))

(defun make-assertion-detail-record
    (form matcher actual expected negated pass)
  (make-assertion-detail
   :form form
   :matcher matcher
   :actual actual
   :expected expected
   :negated negated
   :pass pass))

(define-record-class test-event
  (status path condition secondary-conditions assertion reason location
   elapsed-internal-time journal replay-seed))

(define-record-class test-plan-entry
  (path status reason focused retry timeout-ms concurrent location tags))

(defun make-test-plan-entry-record
    (path status reason focused retry timeout-ms concurrent location tags)
  (make-instance
   (load-time-value (find-class (quote test-plan-entry)))
   :path path
   :status status
   :reason reason
   :focused focused
   :retry retry
   :timeout-ms timeout-ms
   :concurrent concurrent
   :location location
   :tags tags))

(define-record-class benchmark-result
  (samples iterations warmup))

(defun report-test-failure (condition stream)
  (let ((detail (failure-detail condition)))
    (format stream "Test assertion failed: ~S"
            (and detail (assertion-detail-form detail)))))

(define-condition test-failure (error)
  ((detail :initarg :detail :reader failure-detail))
  (:report report-test-failure))

(define-condition assertion-failure (test-failure) ())

(defun report-test-timeout (condition stream)
  (format stream "Test exceeded its ~D ms timeout."
          (test-timeout-ms condition)))

(define-condition test-timeout (error)
  ((timeout-ms :initarg :timeout-ms :reader test-timeout-ms))
  (:report report-test-timeout))

(defun report-expected-failure-missed (condition stream)
  (format stream "Test unexpectedly passed; expected failure: ~A"
          (expected-failure-missed-reason condition)))

(define-condition expected-failure-missed (error)
  ((reason :initarg :reason :reader expected-failure-missed-reason))
  (:report report-expected-failure-missed))

(defun report-hook-failure (condition stream)
  (format stream "~(~A~) hook failed (~D condition~:P): ~{~A~^; ~}"
          (hook-failure-phase condition)
          (length (hook-failure-causes condition))
          (hook-failure-causes condition)))

(define-condition hook-failure (error)
  ((phase :initarg :phase :reader hook-failure-phase)
   (causes :initarg :causes :reader hook-failure-causes))
  (:report report-hook-failure))

(defun signal-assertion-failure (detail)
  "Signal an assertion failure. Inside WITH-SOFT-ASSERTIONS the DETAIL is
collected and returned so the surrounding form keeps running; otherwise the
failure unwinds the test as usual."
  (let ((sink *soft-assertion-sink*))
    (if sink
        (progn
          (vector-push-extend detail sink)
          detail)
        (error 'assertion-failure :detail detail))))

(defun assertion-counting-active-p ()
  (integerp *assertion-count*))

(defun record-assertion ()
  (when (assertion-counting-active-p)
    (incf *assertion-count*))
  t)

(defun require-assertion-counting (form)
  (unless (assertion-counting-active-p)
    (error "cl-weave: ~S must be used inside a running test." form)))

(defmacro with-assertion-counting ((form) &body body)
  `(progn
     (require-assertion-counting ,form)
     ,@body))

(defun set-expected-assertion-count (count form)
  (with-assertion-counting (form)
    (unless (and (integerp count) (not (minusp count)))
      (error "cl-weave: EXPECT-ASSERTIONS count must be a non-negative integer, got ~S."
             count))
    (setf *expected-assertion-count* count
          *expected-assertion-count-form* form)
    count))

(defun set-has-assertions-required (form)
  (with-assertion-counting (form)
    (setf *has-assertions-required* t
          *has-assertions-form* form)
    t))

(defun assertion-count-failure-detail (form matcher actual expected)
  (make-assertion-detail-record form matcher actual expected nil nil))

(defun signal-assertion-count-failure (form matcher actual expected)
  (signal-assertion-failure
   (assertion-count-failure-detail form matcher actual expected)))

(defun verify-assertion-counts ()
  (when (and *expected-assertion-count*
             (/= *assertion-count* *expected-assertion-count*))
    (signal-assertion-count-failure *expected-assertion-count-form*
                                    :assertions
                                    *assertion-count*
                                    *expected-assertion-count*))
  (when (and *has-assertions-required*
             (zerop *assertion-count*))
    (signal-assertion-count-failure *has-assertions-form*
                                    :has-assertions
                                    *assertion-count*
                                    '(:minimum 1)))
  t)
