(in-package #:cl-weave)

(defvar *root-suite* nil)
(defvar *current-suite* nil)
(defvar *named-suites* (make-hash-table :test #'equal))
(defvar *registration-owners* (make-hash-table :test (function eq)))
(progn
  (defvar *test-registry-generation* 0)
  #+sb-thread
  (defvar *test-registry-lock*
    (sb-thread:make-mutex :name "cl-weave test registry"))
  (defmacro with-test-registry-lock (&body body)
    #+sb-thread
    `(sb-thread:with-mutex (*test-registry-lock*) ,@body)
    #-sb-thread
    `(progn ,@body)))

(progn
  (defun note-test-registry-change-unlocked ()
    (incf *test-registry-generation*))
  (defun note-test-registry-change ()
    (with-test-registry-lock
      (note-test-registry-change-unlocked))))

(defun registration-location-pathname (location)
  (let ((file (and location (getf location :file))))
    (and file (uiop:ensure-absolute-pathname file))))

(progn
  (defun record-registration-owner-unlocked (registration pathname)
    (when pathname
      (setf (gethash registration *registration-owners*) pathname))
    registration)
  (defun record-registration-owner (registration location)
  (let ((pathname (registration-location-pathname location)))
    (with-test-registry-lock
      (record-registration-owner-unlocked registration pathname)
      (note-test-registry-change-unlocked)
      registration))))
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

(progn
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
     :tags tags)))

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

(progn
  (defun root-suite-unlocked ()
  (if *root-suite*
      (values *root-suite* nil)
      (values (setf *root-suite* (make-suite :name "root")) t)))
  (defun root-suite ()
  (with-test-registry-lock
    (multiple-value-bind (root created-p)
        (root-suite-unlocked)
      (when created-p
        (note-test-registry-change-unlocked))
      root)))
  (progn
  (defun copy-list-with-tail (values)
    (loop with head = nil
          with tail = nil
          for value in values
          for cell = (list value)
          do (if tail
                 (setf (cdr tail) cell
                       tail cell)
                 (setf head cell
                       tail cell))
          finally (return (values head tail))))

  (defun copy-suite-children-with-tail (children suite-map)
    (loop with head = nil
          with tail = nil
          for child in children
          for value = (if (suite-p child)
                          (gethash child suite-map)
                          child)
          for cell = (list value)
          do (if tail
                 (setf (cdr tail) cell
                       tail cell)
                 (setf head cell
                       tail cell))
          finally (return (values head tail))))

  (defun clone-suite-tree-unlocked (root)
  (let ((suite-map (make-hash-table :test (function eq)))
        (pending (and root (list (cons root nil)))))
    ;; Allocate suite shells before rebuilding child and hook list spines.
    (loop while pending
          for entry = (pop pending)
          for suite = (car entry)
          for parent = (cdr entry)
          for clone = (make-suite :name (suite-name suite)
                                  :parent parent
                                  :focus (suite-focus suite)
                                  :skip-reason (suite-skip-reason suite)
                                  :todo-reason (suite-todo-reason suite)
                                  :execution-mode (suite-execution-mode suite))
          do (setf (gethash suite suite-map) clone)
             (dolist (child (suite-children suite))
               (when (suite-p child)
                 (push (cons child clone) pending))))
    (maphash
     (lambda (suite clone)
       (multiple-value-bind (children children-tail)
           (copy-suite-children-with-tail (suite-children suite) suite-map)
         (setf (suite-children clone) children
               (suite-children-tail clone) children-tail))
       (multiple-value-bind (before-each before-each-tail)
           (copy-list-with-tail (suite-before-each suite))
         (setf (suite-before-each clone) before-each
               (suite-before-each-tail clone) before-each-tail))
       (multiple-value-bind (after-each after-each-tail)
           (copy-list-with-tail (suite-after-each suite))
         (setf (suite-after-each clone) after-each
               (suite-after-each-tail clone) after-each-tail))
       (multiple-value-bind (before-all before-all-tail)
           (copy-list-with-tail (suite-before-all suite))
         (setf (suite-before-all clone) before-all
               (suite-before-all-tail clone) before-all-tail))
       (multiple-value-bind (after-all after-all-tail)
           (copy-list-with-tail (suite-after-all suite))
         (setf (suite-after-all clone) after-all
               (suite-after-all-tail clone) after-all-tail))
       (multiple-value-bind (around-each around-each-tail)
           (copy-list-with-tail (suite-around-each suite))
         (setf (suite-around-each clone) around-each
               (suite-around-each-tail clone) around-each-tail)))
     suite-map)
    (values (and root (gethash root suite-map)) suite-map))))
  (defun snapshot-suite (suite)
  (with-test-registry-lock
    (let ((tree-root suite))
      (loop while (and tree-root (suite-parent tree-root))
            do (setf tree-root (suite-parent tree-root)))
      (multiple-value-bind (clone suite-map)
          (clone-suite-tree-unlocked tree-root)
        (or (gethash suite suite-map) clone))))))

(progn
  (defun current-or-root-suite-unlocked ()
    (or *current-suite*
        (root-suite-unlocked)))
  (defun current-or-root-suite ()
  (with-test-registry-lock
    (multiple-value-bind (suite created-p)
        (current-or-root-suite-unlocked)
      (when created-p
        (note-test-registry-change-unlocked))
      suite))))

(defun clear-tests ()
  (with-test-registry-lock
    (setf *root-suite* nil
          *current-suite* nil
          *named-suites* (make-hash-table :test (function equal))
          *registration-owners* (make-hash-table :test (function eq)))
    (note-test-registry-change-unlocked)
    t))

(defmacro append-to-tail-list (suite head tail value)
  (let ((suite-var (gensym "SUITE"))
        (value-var (gensym "VALUE"))
        (cell-var (gensym "CELL")))
    `(let* ((,suite-var ,suite)
            (,value-var ,value)
            (,cell-var (list ,value-var)))
       (if (,tail ,suite-var)
           (setf (cdr (,tail ,suite-var)) ,cell-var
                 (,tail ,suite-var) ,cell-var)
           (setf (,head ,suite-var) ,cell-var
                 (,tail ,suite-var) ,cell-var))
       ,value-var)))

(defun set-suite-hook-lists
    (suite children before-all after-all before-each around-each after-each)
  "Replace SUITE's children and hook lists, recomputing each tail pointer."
  (setf (suite-children suite) children
        (suite-children-tail suite) (last children)
        (suite-before-all suite) before-all
        (suite-before-all-tail suite) (last before-all)
        (suite-after-all suite) after-all
        (suite-after-all-tail suite) (last after-all)
        (suite-before-each suite) before-each
        (suite-before-each-tail suite) (last before-each)
        (suite-around-each suite) around-each
        (suite-around-each-tail suite) (last around-each)
        (suite-after-each suite) after-each
        (suite-after-each-tail suite) (last after-each)))

(defmacro define-tail-registration (name head tail)
  `(defun ,name (function &key location)
     (let ((pathname (registration-location-pathname location)))
       (with-test-registry-lock
         (let ((registration
                 (append-to-tail-list (current-or-root-suite-unlocked)
                                      ,head
                                      ,tail
                                      function)))
           (record-registration-owner-unlocked registration pathname)
           (note-test-registry-change-unlocked)
           registration)))))

(progn
  (defun add-owned-child-unlocked (parent child pathname)
    (append-to-tail-list parent
                         suite-children
                         suite-children-tail
                         child)
    (record-registration-owner-unlocked child pathname)
    (note-test-registry-change-unlocked)
    child)
  (defun add-child (parent child) (with-test-registry-lock (add-owned-child-unlocked parent child nil))))

(defun normalize-execution-mode (mode)
  (unless (member mode '(nil :concurrent :sequential))
    (error "cl-weave: execution mode must be NIL, :CONCURRENT, or :SEQUENTIAL, got ~S."
           mode))
  mode)

(defun named-suite-key (name)
  (typecase name
    (symbol (string-upcase (symbol-name name)))
    (string (string-upcase name))
    (t name)))

(defun suite-registration-initargs
    (name parent focus execution-mode skip-reason todo-reason)
  (list :name name
        :parent parent
        :focus focus
        :execution-mode (normalize-execution-mode execution-mode)
        :skip-reason skip-reason
        :todo-reason todo-reason))

(defun collect-bounded-unique (list maximum overflow-error-fn canonicalize-fn)
  "Walk LIST once, deduplicating by the canonical key CANONICALIZE-FN
returns for each element, and return the unique values in original order.
Calls OVERFLOW-ERROR-FN (expected to signal an error) instead of returning
if LIST is circular, improper, or longer than MAXIMUM elements."
  (if (null list)
      nil
      (loop with seen-cells = (make-hash-table :test #'eq)
            with seen-keys = (make-hash-table :test #'equal)
            with normalized = '()
            with count = 0
            with cursor = list
            do (cond
                 ((null cursor)
                  (return (nreverse normalized)))
                 ((or (atom cursor)
                      (gethash cursor seen-cells)
                      (>= count maximum))
                  (funcall overflow-error-fn))
                 (t
                  (setf (gethash cursor seen-cells) t)
                  (incf count)
                  (multiple-value-bind (key value) (funcall canonicalize-fn (car cursor))
                    (unless (gethash key seen-keys)
                      (setf (gethash key seen-keys) t)
                      (push value normalized)))
                  (setf cursor (cdr cursor)))))))

(defconstant +maximum-tag-count+ 100000)

(defun normalize-tags (tags &optional (description "tags"))
  "Canonicalize tags to unique uppercase strings, comparing names case-insensitively."
  (if (null tags)
      nil
      (collect-bounded-unique
       tags +maximum-tag-count+
       (lambda ()
         (error
          "cl-weave: ~A must be a finite proper list with at most ~D entries."
          description
          +maximum-tag-count+))
       (lambda (tag)
         (let* ((name
                  (etypecase tag
                    (symbol (symbol-name tag))
                    (string tag)))
                (canonical (string-upcase name)))
           (values canonical canonical))))))


(defun collapse-parent-directory-components (pathname)
  (let ((directory (pathname-directory pathname)))
    (make-pathname
     :directory
     (loop with normalized = '()
           for component in directory
           if (eq component :up)
             do (when (and normalized
                           (not (member (first normalized) '(:absolute :relative :up))))
                  (pop normalized))
           else
             do (push component normalized)
           finally (return (nreverse normalized)))
     :defaults pathname)))


(defconstant +maximum-watch-dependency-count+ 100000)

(defun normalize-watch-dependencies (dependencies location)
  (if (null dependencies)
      nil
      (let* ((source (getf location :file))
             (base (and source
                        (uiop:pathname-directory-pathname
                         (uiop:ensure-absolute-pathname source)))))
        (collect-bounded-unique
         dependencies +maximum-watch-dependency-count+
         (lambda ()
           (error
            "cl-weave: watch dependencies must be a finite proper list with at most ~D entries."
            +maximum-watch-dependency-count+))
         (lambda (dependency)
           (let* ((pathname
                    (etypecase dependency
                      (pathname dependency)
                      (string (pathname dependency))))
                  (absolute
                    (if (uiop:absolute-pathname-p pathname)
                        pathname
                        (if base
                            (merge-pathnames pathname base)
                            (error
                             "cl-weave: relative watch dependency ~S requires a test source location."
                             dependency))))
                  (canonical
                    (collapse-parent-directory-components
                     (uiop:ensure-absolute-pathname absolute))))
             (values canonical canonical)))))))


(defun test-registration-initargs
    (name function focus skip-reason todo-reason retry timeout-ms
     execution-mode expected-failure-reason location tags watch-dependencies
     &optional trusted-empty-function)
  (list :name name
        :function function
        :trusted-empty-function trusted-empty-function
        :focus focus
        :skip-reason skip-reason
        :todo-reason todo-reason
        :retry retry
        :timeout-ms timeout-ms
        :execution-mode (and execution-mode
                             (normalize-execution-mode execution-mode))
        :expected-failure-reason expected-failure-reason
        :location location
        :tags (and tags (normalize-tags tags))
        :watch-dependencies
        (and watch-dependencies
             (normalize-watch-dependencies watch-dependencies location))))

(defun register-suite
    (name thunk &key focus execution-mode skip-reason todo-reason location)
  (unless (stringp name)
    (error "cl-weave: suite name must be a string."))
  (let* ((pathname (registration-location-pathname location))
         (suite
           (apply (function make-suite)
                  (suite-registration-initargs
                   name *current-suite* focus execution-mode
                   skip-reason todo-reason))))
    (with-test-registry-lock
      (let ((parent (current-or-root-suite-unlocked)))
        (setf (suite-parent suite) parent)
        (add-owned-child-unlocked parent suite pathname)))
    (let ((*current-suite* suite))
      (funcall thunk))
    suite))

(defun register-test
    (name function &key focus skip-reason todo-reason retry timeout-ms
         execution-mode expected-failure-reason location tags watch-depends-on
         trusted-empty-function)
  (unless (stringp name)
    (error "cl-weave: test name must be a string."))
  (let* ((pathname (registration-location-pathname location))
         (test
           (apply (function make-test-case)
                  (test-registration-initargs
                   name function focus skip-reason todo-reason retry
                   timeout-ms execution-mode expected-failure-reason
                   location tags watch-depends-on trusted-empty-function))))
    (with-test-registry-lock
      (add-owned-child-unlocked (current-or-root-suite-unlocked)
                                test
                                pathname))
    test))



(define-tail-registration register-before-all suite-before-all suite-before-all-tail)
(define-tail-registration register-after-all suite-after-all suite-after-all-tail)
(define-tail-registration register-before-each suite-before-each suite-before-each-tail)
(define-tail-registration register-around-each suite-around-each suite-around-each-tail)
(define-tail-registration register-after-each suite-after-each suite-after-each-tail)

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
