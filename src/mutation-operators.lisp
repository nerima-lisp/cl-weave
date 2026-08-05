(in-package #:cl-weave)

(defstruct mutation-operator
  (name nil :type (or null keyword) :read-only t)
  (description nil :type (or null string) :read-only t)
  (function nil :type (or null function) :read-only t))

(defvar *mutation-operators* (make-hash-table :test #'eq))
(defparameter *default-mutation-operators*
  '(:arithmetic-operator :comparison-operator :boolean-literal :conditional-branch))
(defparameter *arithmetic-operator-mutations* '((+ -) (- +) (* /) (/ *)))
(defparameter *comparison-operator-mutations*
  '((= /=) (/= =) (< >=) (> <=) (<= >) (>= <)))

(defun register-mutation-operator (name function &key description)
  (check-type name keyword)
  (check-type function function)
  (when description (check-type description string))
  (setf (gethash name *mutation-operators*)
        (make-mutation-operator :name name :description description :function function))
  name)

(defmacro defmutation-operator (name (form path) &body body)
  (let ((description (when (stringp (first body)) (first body)))
        (forms (if (stringp (first body)) (rest body) body)))
    `(register-mutation-operator ,name
       (lambda (,form ,path) ,@forms)
       :description ,description)))

(defun mutation-operator-named (name)
  (or (gethash name *mutation-operators*)
      (error "Unknown mutation operator: ~S" name)))

(defun resolve-mutation-operator (operator)
  (cond ((keywordp operator) (mutation-operator-named operator))
        ((mutation-operator-p operator) operator)
        (t (error "Invalid mutation operator designator: ~S" operator))))

(defun mutation-operator-list (operators)
  (mapcar #'resolve-mutation-operator operators))

(defun mutation-operator-metadata (operator)
  (let ((operator (resolve-mutation-operator operator)))
    (list :name (mutation-operator-name operator)
          :description (mutation-operator-description operator))))

(defun list-mutation-operators ()
  (mapcar #'mutation-operator-metadata
          (sort (loop for operator being the hash-values of *mutation-operators*
                      collect operator)
                #'string< :key (lambda (operator)
                                 (symbol-name (mutation-operator-name operator))))))

(defun operator-symbol-replacement (form replacements)
  (when (and (consp form) (symbolp (first form)))
    (let ((replacement (second (assoc (first form) replacements :test #'eq))))
      (when replacement (list (cons replacement (rest form)))))))

(defmutation-operator :arithmetic-operator (form path)
  "Swaps arithmetic operator heads such as +, -, *, and /."
  (declare (ignore path))
  (operator-symbol-replacement form *arithmetic-operator-mutations*))

(defmutation-operator :comparison-operator (form path)
  "Swaps comparison operator heads such as =, /=, <, >, <=, and >=."
  (declare (ignore path))
  (operator-symbol-replacement form *comparison-operator-mutations*))

(defmutation-operator :boolean-literal (form path)
  "Flips literal T and NIL forms."
  (declare (ignore path))
  (cond ((eq form t) (list nil)) ((null form) (list t)) (t nil)))

(defmutation-operator :conditional-branch (form path)
  "Swaps IF then/else branches while preserving the test form."
  (declare (ignore path))
  (when (and (consp form) (eq (first form) 'if) (>= (length form) 3))
    (let ((test (second form)) (then-form (third form)) (else-form (fourth form)))
      (list `(if ,test ,else-form ,then-form)))))
