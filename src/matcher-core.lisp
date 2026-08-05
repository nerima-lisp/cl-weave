(in-package #:cl-weave)

(defstruct matcher
  name
  function
  description)

(defvar *matchers* (make-hash-table :test #'eq))

(defun matcher-description-value (description matcher)
  (when (and description (not (stringp description)))
    (error "cl-weave: matcher ~S description must be a string or NIL, got ~S."
           matcher
           description))
  description)

(defun register-matcher (name function &key description)
  (unless (symbolp name)
    (error "cl-weave: matcher name must be a symbol, got ~S." name))
  (unless (functionp function)
    (error "cl-weave: matcher ~S must be registered with a function, got ~S."
           name
           function))
  (setf (gethash name *matchers*)
        (make-matcher :name name
                      :function function
                      :description (matcher-description-value description name)))
  name)

(defun matcher-spec-name (spec)
  (cond
    ((and (consp spec) (symbolp (first spec))) (first spec))
    (t (error "cl-weave: matcher spec must start with a symbol name, got ~S." spec))))

(defun matcher-spec-function (spec)
  (cond
    ((and (consp spec) (functionp (second spec))) (second spec))
    (t (error "cl-weave: matcher spec ~S must provide a function as its second value." spec))))

(defun matcher-spec-description (spec)
  (let ((tail (cddr spec)))
    (cond
      ((null tail) nil)
      ((and (= (length tail) 1) (stringp (first tail)))
       (first tail))
      ((and (= (length tail) 2) (eq (first tail) :description))
       (matcher-description-value (second tail) (matcher-spec-name spec)))
      (t
       (error "cl-weave: matcher spec ~S must end with no metadata, a ~
               description string, or :description string."
              spec)))))

(defun extend-expect (specs)
  (dolist (spec specs specs)
    (register-matcher (matcher-spec-name spec)
                      (matcher-spec-function spec)
                      :description (matcher-spec-description spec))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun validate-matcher-lambda-list (actual expected operator)
    (unless (and (symbolp actual) (symbolp expected))
      (error "cl-weave: ~S matcher bindings must be symbols, got ~S."
             operator
             (list actual expected))))

  (defun matcher-description-fragments-p (form)
    (and (consp form)
         (eq (first form) :description)
         (rest form)
         (every (function stringp) (rest form))))

  (defun split-matcher-body (body)
    "Return the leading description of BODY and the forms that follow it.

The description may also be written as a leading (:description \"a\" \"b\")
form, whose parts are joined here. That spelling exists because a description
longer than 100 columns cannot be one literal: Common Lisp has no string
continuation, and a newline inside a literal becomes part of the string. The
form is unambiguous because :description names no function, so it could never
have been a matcher body form."
    (cond
      ((and (consp body) (stringp (first body)))
       (values (first body) (rest body)))
      ((and (consp body) (matcher-description-fragments-p (first body)))
       (values (apply (function concatenate) 'string (rest (first body)))
               (rest body)))
      (t (values nil body))))

  (defun matcher-definition-body (name actual expected body operator)
    "Validate the NAME/ACTUAL/EXPECTED bindings of a matcher definition
introduced by OPERATOR (defmatcher or expect-extend), then split BODY into
its description and forms via SPLIT-MATCHER-BODY."
    (unless (symbolp name)
      (error "cl-weave: ~A matcher name must be a symbol, got ~S." operator name))
    (validate-matcher-lambda-list actual expected operator)
    (split-matcher-body body)))

(defmacro defmatcher (name (actual expected) &body body)
  (multiple-value-bind (description forms)
      (matcher-definition-body name actual expected body 'defmatcher)
    `(register-matcher ',name
                       (lambda (,actual ,expected)
                         ,@forms)
                       :description ,description)))

(defmacro expect-extend (&body definitions)
  `(extend-expect
    (list
     ,@(loop for definition in definitions
             collect
             (destructuring-bind (name (actual expected) &body body) definition
               (multiple-value-bind (description forms)
                   (matcher-definition-body name actual expected body 'expect-extend)
                 `(list ',name
                        (lambda (,actual ,expected)
                          ,@forms)
                        :description
                        ,description)))))))

(defun matcher-named (name)
  (or (gethash name *matchers*)
      (error "Unknown cl-weave matcher: ~S" name)))

(defun matcher-metadata (name)
  (let ((matcher (matcher-named name)))
    (list :name (matcher-name matcher)
          :description (matcher-description matcher))))

(defun list-matchers ()
  (sort (loop for matcher being the hash-values of *matchers*
              collect (matcher-metadata (matcher-name matcher)))
        #'string<
        :key (lambda (metadata)
               (symbol-name (getf metadata :name)))))

