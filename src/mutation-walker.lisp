(in-package #:cl-weave)

(defstruct (mutation-walk-context
             (:constructor make-mutation-walk-context (visitor path)))
  (visitor nil :type function :read-only t)
  (path nil :type list :read-only t))

(defun mutation-child-context (context &rest indexes)
  (make-mutation-walk-context
   (mutation-walk-context-visitor context)
   (append (mutation-walk-context-path context) indexes)))

(defun walk-mutation-form (form visitor &optional path)
  (labels ((declaration-form-p (candidate)
             (and (consp candidate) (eq (first candidate) 'declare)))
           (walk-child (node context &rest indexes)
             (walk node (apply #'mutation-child-context context indexes)))
           (walk-body (body context start &key docstring-p)
             (loop for element in body
                   for index from start
                   for first-p = t then nil
                   unless (or (declaration-form-p element)
                              (and docstring-p first-p (stringp element)))
                     do (walk-child element context index)))
           (walk-lambda-body (lambda-like-form context)
             (walk-body (cddr lambda-like-form) context 2 :docstring-p t))
           (walk-binding-value (binding context binding-index value-index)
             (when (and (consp binding) (consp (nthcdr value-index binding)))
               (walk-child (nth value-index binding)
                           context 1 binding-index value-index)))
           (walk-bindings (bindings context)
             (loop for binding in bindings
                   for binding-index from 0
                   do (walk-binding-value binding context binding-index 1)))
           (walk-local-definitions (definitions context)
             (loop for definition in definitions
                   for definition-index from 0
                   when (and (consp definition) (consp (rest definition)))
                     do (walk-body (cddr definition)
                                   (mutation-child-context context 1 definition-index)
                                   2
                                   :docstring-p t)))
           (walk-value-pairs (elements context start)
             (loop for element in elements
                   for index from start
                   when (evenp index)
                     do (walk-child element context index)))
           (walk-clauses (clauses context start body-offset)
             (loop for clause in clauses
                   for clause-index from start
                   when (and (consp clause)
                             (or (zerop body-offset) (consp (rest clause))))
                     do (walk-body (nthcdr body-offset clause)
                                   (mutation-child-context context clause-index)
                                   body-offset)))
           (walk-do (node context)
             (walk-bindings (second node) context)
             (loop for binding in (second node)
                   for binding-index from 0
                   do (walk-binding-value binding context binding-index 2))
             (let ((end-clause (third node)))
               (when (consp end-clause)
                 (walk-body end-clause (mutation-child-context context 2) 0)))
             (walk-body (cdddr node) context 3))
           (walk-application-subforms (node context)
             ;; Function names and special-form operators are syntax, not
             ;; evaluated subforms. Keywords retain their data-list use.
             (loop for element in node
                   for index from 0
                   when (or (plusp index)
                            (keywordp (first node))
                            (and (zerop index) (consp element)))
                     do (walk-child element context index)))
           (walk (node context)
             (funcall (mutation-walk-context-visitor context)
                      node
                      (mutation-walk-context-path context))
             (when (consp node)
               (case (first node)
                  ((quote declare) nil)
                 (function
                  (let ((function-form (second node)))
                    (when (and (consp function-form)
                               (eq (first function-form) 'lambda))
                      (walk-lambda-body function-form (mutation-child-context context 1)))))
                 (lambda
                  (walk-lambda-body node context))
                 ((defun defmacro)
                  (walk-body (cdddr node) context 3 :docstring-p t))
                 ((let let* symbol-macrolet handler-bind)
                  (walk-bindings (second node) context)
                  (walk-body (cddr node) context 2))
                 ((flet labels macrolet)
                  (walk-local-definitions (second node) context)
                  (walk-body (cddr node) context 2))
                 ((multiple-value-bind destructuring-bind)
                  (when (consp (cddr node))
                    (walk-child (third node) context 2))
                  (walk-body (cdddr node) context 3))
                 ((dolist dotimes)
                  (let ((binding (second node)))
                    (when (consp (rest binding))
                      (walk-child (second binding) context 1 1))
                    (when (consp (cddr binding))
                      (walk-child (third binding) context 1 2)))
                  (walk-body (cddr node) context 2))
                 ((do do*)
                  (walk-do node context))
                 ((setq psetq)
                  (walk-value-pairs (rest node) context 1))
                 (cond
                  (walk-clauses (rest node) context 1 0))
                 ((handler-case restart-case)
                  (when (consp (rest node))
                    (walk-child (second node) context 1))
                  (walk-clauses (cddr node) context 2 2))
                 ((block return-from eval-when)
                  (walk-body (cddr node) context 2))
                 (go nil)
                 (the
                  (when (consp (cddr node))
                    (walk-child (third node) context 2)))
                 ((locally unwind-protect multiple-value-prog1
                   multiple-value-call progv)
                  (walk-body (rest node) context 1))
                 (tagbody
                  (loop for element in (rest node)
                        for index from 1
                        unless (or (symbolp element) (numberp element))
                          do (walk-child element context index)))
                 (otherwise
                  (walk-application-subforms node context))))))
    (walk form (make-mutation-walk-context visitor path))))

(defun replace-mutation-path (form path replacement)
  (if (null path)
      replacement
      (loop for element in form
            for index from 0
            collect (if (= index (first path))
                        (replace-mutation-path element (rest path) replacement)
                        element))))

(defun collect-mutations (form &key (operators *default-mutation-operators*))
  (let ((operator-list (mutation-operator-list operators))
        (mutations '())
        (next-id 0))
    (walk-mutation-form
     form
     (lambda (node path)
       (dolist (operator operator-list)
         (dolist (replacement
                  (funcall (mutation-operator-function operator) node path))
           (unless (equal replacement node)
             (incf next-id)
             (push (make-mutation
                    :id next-id
                    :operator (mutation-operator-name operator)
                    :path path
                    :original node
                    :replacement replacement
                    :form (replace-mutation-path form path replacement))
                   mutations))))))
    (nreverse mutations)))
