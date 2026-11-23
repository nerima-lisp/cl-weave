(in-package #:cl-weave/spec)

;;;; Macro DSL (FR-003, D3). The macros only parse syntax and expand into a
;;;; MAKE-SPEC call whose components are lambdas obeying the calling convention
;;;; documented in spec.lisp. Nothing here searches or evaluates a state space.
;;;;
;;;;   (defspec counter ((limit 3))
;;;;     (:variables x)
;;;;     (:init (x 0))
;;;;     (:action inc (:guard (< x limit)) (:next (x (1+ x))))
;;;;     (:invariant bounded (<= x limit)))
;;;;
;;;; Inside guards, updates, outputs, invariants and predicates, each state
;;;; variable and each constant is an ordinary lexical variable holding its
;;;; current value. (NEXT x) reads x in the next state and is available only in
;;;; :output and :action-property forms.

(defmacro next (variable)
  "The value of VARIABLE in the next state. Valid inside :output and
:action-property forms of the DSL, which bind the next state."
  `(state-ref %next-state ',variable))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun dsl-error (control &rest arguments)
    (apply #'signal-spec-error 'spec-definition-error control arguments))

  (defparameter *specification-clause-heads*
    '(:variables :init :action :invariant :action-property :temporal :fairness
      :symmetry :deadlock-check))

  (defun normalize-constant-bindings (constants)
    (mapcar (lambda (constant)
              (cond ((and constant (symbolp constant)) (list constant nil))
                    ((and (consp constant) (symbolp (first constant)) (first constant)
                          (null (cddr constant)))
                     (list (first constant) (second constant)))
                    (t (dsl-error "A constant must be SYMBOL or (SYMBOL DEFAULT-FORM), got ~S."
                                  constant))))
            constants))

  (defun clauses-headed (head clauses)
    (remove-if-not (lambda (clause) (and (consp clause) (eq (first clause) head)))
                   clauses))

  (defun sole-clause (head clauses)
    (let ((found (clauses-headed head clauses)))
      (when (rest found)
        (dsl-error "Clause ~S may appear only once." head))
      (first found)))

  (defun state-let (state variables body)
    `(let ,(loop for variable in variables
                 collect `(,variable (state-ref ,state ',variable)))
       (declare (ignorable ,@variables))
       ,@body))

  (defun state-lambda (variables parameters body &key next-state)
    (let ((state (gensym "STATE")))
      `(lambda (,state ,@(when next-state '(%next-state)) ,@parameters)
         (declare (ignorable ,state ,@(when next-state '(%next-state)) ,@parameters))
         ,(state-let state variables body))))

  (defun action-clause-parts (name clauses)
    (dolist (clause clauses)
      (unless (and (consp clause) (member (first clause) '(:for :guard :next :output)))
        (dsl-error "Action ~S: unknown clause ~S; expected :for, :guard, :next or :output."
                   name clause)))
    (flet ((single (head)
             (let ((found (clauses-headed head clauses)))
               (when (rest found)
                 (dsl-error "Action ~S: clause ~S may appear only once." name head))
               (first found))))
      (values (rest (single :for))
              (single :guard)
              (rest (single :next))
              (single :output))))

  (defun action-form (action variables)
    (destructuring-bind (name &rest clauses) (rest action)
      (unless (and name (symbolp name))
        (dsl-error "An :action needs a symbol name, got ~S." name))
      (multiple-value-bind (quantifiers guard updates output)
          (action-clause-parts name clauses)
        (let ((parameters (mapcar (lambda (quantifier)
                                    (unless (and (consp quantifier)
                                                 (symbolp (first quantifier))
                                                 (= (length quantifier) 2))
                                      (dsl-error "Action ~S: a :for entry must be (SYMBOL DOMAIN-FORM), got ~S."
                                                 name quantifier))
                                    (first quantifier))
                                  quantifiers)))
          (when (intersection parameters variables)
            (dsl-error "Action ~S: parameters ~S shadow state variables."
                       name (intersection parameters variables)))
          (loop for (variable) in updates
                do (unless (member variable variables)
                     (dsl-error "Action ~S assigns ~S, which is not a declared variable."
                                name variable)))
          (let ((assigned (mapcar #'first updates)))
            (unless (= (length assigned) (length (remove-duplicates assigned)))
              (dsl-error "Action ~S assigns a variable twice." name)))
          `(make-spec-action
            :name ',name
            :params (list ,@(loop for quantifier in quantifiers
                                  for index from 0
                                  collect `(list ',(first quantifier)
                                                 ,(state-lambda variables
                                                                (subseq parameters 0 index)
                                                                (list (second quantifier))))))
            :guard ,(state-lambda variables parameters
                                  (if guard (rest guard) '(t)))
            :update ,(state-lambda variables parameters
                                   `((list ,@(loop for (variable form) in updates
                                                   collect `',variable
                                                   collect form))))
            :output ,(when output
                       (state-lambda variables parameters (rest output)
                                     :next-state t)))))))

  (defun init-form (init variables)
    (let ((entries (rest init)))
      (dolist (entry entries)
        (unless (and (consp entry) (symbolp (first entry)) (= (length entry) 2))
          (dsl-error ":init entries must be (VARIABLE FORM) or (VARIABLE (:in DOMAIN-FORM)), got ~S."
                     entry)))
      (let ((assigned (mapcar #'first entries)))
        (unless (and (= (length assigned) (length (remove-duplicates assigned)))
                     (null (set-difference assigned variables))
                     (null (set-difference variables assigned)))
          (dsl-error ":init must give each of ~S exactly once, got ~S." variables assigned)))
      `(lambda ()
         (init-product
          (list ,@(loop for (variable form) in entries
                        collect (if (and (consp form) (eq (first form) :in))
                                    `(list ',variable
                                           (domain-elements ,(second form)
                                                            ,(format nil "init variable ~S" variable)))
                                    `(list ',variable (list ,form)))))))))

  (defun invariant-form (clause variables)
    (destructuring-bind (name form) (rest clause)
      `(make-spec-invariant :name ',name
                            :predicate ,(state-lambda variables '() (list form)))))

  (defun action-property-form (clause variables)
    (destructuring-bind (name form) (rest clause)
      `(make-spec-action-property :name ',name
                                  :relation ,(state-lambda variables '() (list form)
                                                           :next-state t))))

  (defun temporal-form (clause variables)
    (destructuring-bind (name (kind predicate &optional consequent)) (rest clause)
      (unless (member kind *temporal-kinds*)
        (dsl-error "Temporal property ~S: kind must be one of ~S, got ~S."
                   name *temporal-kinds* kind))
      `(make-spec-temporal-property
        :name ',name :kind ,kind
        :predicate ,(state-lambda variables '() (list predicate))
        :consequent ,(when consequent
                       (state-lambda variables '() (list consequent)))))))

(defun init-product (choices)
  "CHOICES is a list of (VARIABLE VALUES). Return every state plist that picks
one value per variable; the first variable varies slowest."
  (if (null choices)
      (list '())
      (destructuring-bind (variable values) (first choices)
        (loop for value in values
              nconc (loop for rest in (init-product (rest choices))
                          collect (list* variable value rest))))))

(defmacro specification (name (&rest constants) &body clauses)
  "Return a SPEC. CONSTANTS is a list of SYMBOL or (SYMBOL FORM); they are
bound lexically around the whole specification and recorded as its constants.
CLAUSES are :variables, :init, :action, :invariant, :action-property,
:temporal, :fairness, :symmetry and :deadlock-check; see CONTRACTS.md."
  (dolist (clause clauses)
    (unless (and (consp clause) (member (first clause) *specification-clause-heads*))
      (dsl-error "Specification ~S: unknown clause ~S; expected one of ~S."
                 name clause *specification-clause-heads*)))
  (let* ((bindings (normalize-constant-bindings constants))
         (constant-names (mapcar #'first bindings))
         (variables-clause (sole-clause :variables clauses))
         (init-clause (sole-clause :init clauses))
         (deadlock-clause (sole-clause :deadlock-check clauses))
         (variables (rest variables-clause)))
    (unless variables-clause (dsl-error "Specification ~S needs a :variables clause." name))
    (unless init-clause (dsl-error "Specification ~S needs an :init clause." name))
    (when (intersection variables constant-names)
      (dsl-error "Specification ~S: ~S are both constants and variables."
                 name (intersection variables constant-names)))
    `(let* ,bindings
       (declare (ignorable ,@constant-names))
       (make-spec
        :name ',name
        :constants (list ,@(loop for constant in constant-names
                                 collect `',constant
                                 collect constant))
        :variables ',variables
        :init ,(init-form init-clause variables)
        :actions (list ,@(mapcar (lambda (clause) (action-form clause variables))
                                 (clauses-headed :action clauses)))
        :invariants (list ,@(mapcar (lambda (clause) (invariant-form clause variables))
                                    (clauses-headed :invariant clauses)))
        :action-properties (list ,@(mapcar (lambda (clause)
                                             (action-property-form clause variables))
                                           (clauses-headed :action-property clauses)))
        :temporal-properties (list ,@(mapcar (lambda (clause) (temporal-form clause variables))
                                             (clauses-headed :temporal clauses)))
        :fairness-conditions
        (list ,@(loop for clause in (clauses-headed :fairness clauses)
                      append (loop for (kind . actions) in (rest clause)
                                   do (unless (member kind '(:weak :strong))
                                        (dsl-error "Fairness kind must be :weak or :strong, got ~S." kind))
                                   append (loop for action in actions
                                                collect `(make-spec-fairness-condition
                                                          :kind ,kind :action ',action)))))
        :symmetry ',(loop for clause in (clauses-headed :symmetry clauses)
                          append (rest clause))
        :check-deadlock ,(if deadlock-clause (second deadlock-clause) t)))))

(defmacro defspec (name (&rest constants) &body clauses)
  "Define a function NAME that returns the specification. Each constant becomes
a keyword parameter with its default form, so a model parameter is overridden
per call: (counter :limit 5)."
  (let ((bindings (normalize-constant-bindings constants)))
    `(defun ,name (&key ,@bindings)
       (specification ,name ,(mapcar (lambda (binding) (list (first binding) (first binding)))
                                     bindings)
         ,@clauses))))
