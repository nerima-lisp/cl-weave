(in-package #:cl-weave)

;;;; Turning registration arguments into suites and test cases: validating
;;;; and canonicalizing execution modes, tags and watch dependencies, then
;;;; attaching the resulting record to the registry.

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
                             "cl-weave: relative watch dependency ~S requires ~
                              a test source location."
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
        :execution-mode (normalize-execution-mode execution-mode)
        :expected-failure-reason expected-failure-reason
        :location location
        :tags (normalize-tags tags)
        :watch-dependencies
        (normalize-watch-dependencies watch-dependencies location)))

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
