(in-package #:cl-weave/spec)

;;;; Specification objects (FR-003). A SPEC is plain data plus closures; the
;;;; DSL in dsl.lisp only builds one with MAKE-SPEC, and a specification can be
;;;; assembled by hand with the same constructors.
;;;;
;;;; Calling convention of every user-supplied function, fixed here so that no
;;;; module has to guess it:
;;;;
;;;;   init                 ()                          -> list of state plists
;;;;   quantifier domain    (state . earlier-params)    -> list of values
;;;;   guard                (state . params)            -> generalized boolean
;;;;   update               (state . params)            -> plist of changed variables
;;;;   output               (state next-state . params) -> any EQUAL-comparable value
;;;;   invariant predicate  (state)                     -> generalized boolean
;;;;   action relation      (state next-state)          -> generalized boolean
;;;;   temporal predicates  (state)                     -> generalized boolean

;;; Default limits (NFR-001, D4). Every search budget is finite by default.
;;; These values are provisional: Phase 1 measures them in benchmarks/.
(defparameter *default-max-states* 10000
  "Distinct states EXPLORE-SPEC may discover before it truncates.")
(defparameter *default-max-depth* 100
  "Longest path, in steps from an initial state, EXPLORE-SPEC follows.")
(defparameter *default-max-simulation-steps* 50
  "Steps in one random run of SIMULATE-SPEC.")
(defparameter *default-linearization-budget* 100000
  "Search nodes LINEARIZABLE-HISTORY-P may visit before it gives up.")

(defstruct (spec-action (:copier nil))
  "A named action. PARAMS is a list of (SYMBOL DOMAIN-FUNCTION), the
existential quantifiers; the guard, update and output functions receive the
quantified values in the same order."
  name params guard update output)

(defstruct (spec-invariant (:copier nil)) name predicate)

(defstruct (spec-action-property (:copier nil))
  "The property [][RELATION]_vars. A step that leaves every variable unchanged
satisfies it vacuously."
  name relation)

(defparameter *temporal-kinds*
  '(:always :eventually :infinitely-often :eventually-always :leads-to)
  "The five admitted forms: []P, <>P, []<>P, <>[]P and P ~> Q.")

(defstruct (spec-temporal-property (:copier nil))
  "KIND is one of +TEMPORAL-KINDS+. PREDICATE is P; CONSEQUENT is Q and is
present only for :leads-to."
  name kind predicate consequent)

(defstruct (spec-fairness-condition (:copier nil))
  "KIND is :weak or :strong. ACTION names an action; the condition applies to
the disjunction of all its parameter instances, as WF_vars(\\E x : A(x))."
  kind action)

(defstruct (spec (:constructor %make-spec) (:copier nil))
  name constants variables init actions invariants action-properties
  temporal-properties fairness-conditions symmetry (check-deadlock t))

(defmethod print-object ((spec spec) stream)
  (print-unreadable-object (spec stream :type t)
    (format stream "~A" (spec-name spec))))

;;; Results shared by every checker.

(defstruct (spec-transition (:copier nil))
  "One step of the next-state relation: ACTION taken with PARAMS in FROM gives TO."
  action params from to)

(defstruct (trace-step (:copier nil))
  "A state and the action that produced it; ACTION and PARAMS are NIL for an
initial state."
  action params state)

(defstruct (lasso (:copier nil))
  "A counterexample to a temporal property: PREFIX is a list of trace steps
from an initial state, CYCLE a list of trace steps that repeats forever."
  prefix cycle)

(defstruct (spec-violation (:copier nil))
  "KIND is :invariant, :action-property, :deadlock, :temporal, :refinement,
:conformance or :linearizability. TRACE is a list of trace steps (or a LASSO
for :temporal); DETAIL is a plist whose keys depend on KIND."
  kind property trace detail)

(defstruct (spec-result (:copier nil))
  "Outcome of one check. TRUNCATED is true when a limit stopped the search
before it covered the space; TRUNCATION-REASON is :max-states, :max-depth or
:budget. LIVENESS-REQUESTED lists the temporal properties that were asked for.
CHECKED-PROPERTIES lists, in declaration order, the names of the properties the
check examined: invariants, action properties, temporal properties, and the
keyword :deadlock when deadlock was checked; NIL when none was. LIMITS is the
plist of limits the check ran with, for example (:max-states n :max-depth d),
(:runs r :max-steps s) or (:budget b). STATISTICS is a plist of
checker-specific counters."
  spec-name mode violation (states-found 0) (depth-reached 0) truncated
  truncation-reason liveness-requested allow-bounded checked-properties limits
  statistics)

(defun spec-result-passed-p (result)
  "True when RESULT is a pass. A violation never passes. A truncated search
passes only when the caller allowed bounded checking (D4), and never when
temporal properties were requested, because a truncated graph cannot decide
them (FR-007)."
  (and (null (spec-result-violation result))
       (or (not (spec-result-truncated result))
           (and (spec-result-allow-bounded result)
                (null (spec-result-liveness-requested result))))))

(defstruct (state-graph (:copier nil))
  "The reachable state graph handed from the explorer to the liveness checker.
EDGES maps a state to its list of SPEC-TRANSITIONs (a STATE-TABLE).
COMPLETE-P is true only when no limit cut the search."
  spec initial-states (edges (make-state-table)) complete-p)

;;; Construction and validation.

(defmacro ensure-definition (test control &rest arguments)
  `(unless ,test
     (signal-spec-error 'spec-definition-error ,control ,@arguments)))

(defun unique-p (items)
  (= (length items) (length (remove-duplicates items :test #'equal))))

(defun validate-spec-components (name constants variables init actions invariants
                                 action-properties temporal-properties
                                 fairness-conditions symmetry)
  (ensure-definition (or (stringp name) (and name (symbolp name)))
                     "Specification name must be a string or a non-NIL symbol, got ~S." name)
  (ensure-definition (and (listp constants) (evenp (length constants))
                          (loop for key in constants by #'cddr always (symbolp key))
                          (unique-p (loop for key in constants by #'cddr collect key)))
                     "Constants of ~A must be a plist with unique symbol keys, got ~S."
                     name constants)
  (ensure-definition (and variables (listp variables) (every #'symbolp variables)
                          (unique-p variables))
                     "Variables of ~A must be a non-empty list of unique symbols, got ~S."
                     name variables)
  (ensure-definition (functionp init) "Init of ~A must be a function, got ~S." name init)
  (ensure-definition (and (listp actions) (every #'spec-action-p actions))
                     "Actions of ~A must be a list of SPEC-ACTION." name)
  (dolist (action actions)
    (let ((action-name (spec-action-name action)))
      (ensure-definition (and action-name (symbolp action-name))
                         "Action name must be a non-NIL symbol, got ~S." action-name)
      (ensure-definition (and (listp (spec-action-params action))
                              (every (lambda (quantifier)
                                       (and (consp quantifier)
                                            (symbolp (first quantifier))
                                            (functionp (second quantifier))
                                            (null (cddr quantifier))))
                                     (spec-action-params action))
                              (unique-p (mapcar #'first (spec-action-params action))))
                         "Parameters of action ~S must be a list of unique (SYMBOL DOMAIN-FUNCTION)."
                         action-name)
      (ensure-definition (functionp (spec-action-guard action))
                         "Guard of action ~S must be a function." action-name)
      (ensure-definition (functionp (spec-action-update action))
                         "Update of action ~S must be a function." action-name)
      (ensure-definition (or (null (spec-action-output action))
                             (functionp (spec-action-output action)))
                         "Output of action ~S must be a function or NIL." action-name)))
  (ensure-definition (unique-p (mapcar #'spec-action-name actions))
                     "Action names of ~A must be unique." name)
  (ensure-definition (and (listp invariants) (every #'spec-invariant-p invariants)
                          (every (lambda (invariant)
                                   (functionp (spec-invariant-predicate invariant)))
                                 invariants))
                     "Invariants of ~A must be SPEC-INVARIANTs with function predicates." name)
  (ensure-definition (and (listp action-properties)
                          (every #'spec-action-property-p action-properties)
                          (every (lambda (property)
                                   (functionp (spec-action-property-relation property)))
                                 action-properties))
                     "Action properties of ~A must be SPEC-ACTION-PROPERTYs with function relations."
                     name)
  (ensure-definition (and (listp temporal-properties)
                          (every #'spec-temporal-property-p temporal-properties))
                     "Temporal properties of ~A must be SPEC-TEMPORAL-PROPERTYs." name)
  (dolist (property temporal-properties)
    (let ((kind (spec-temporal-property-kind property)))
      (ensure-definition (member kind *temporal-kinds*)
                         "Temporal property ~S has kind ~S; admitted kinds are ~S."
                         (spec-temporal-property-name property) kind *temporal-kinds*)
      (ensure-definition (functionp (spec-temporal-property-predicate property))
                         "Temporal property ~S needs a predicate function."
                         (spec-temporal-property-name property))
      (ensure-definition (eq (eq kind :leads-to)
                             (functionp (spec-temporal-property-consequent property)))
                         "Temporal property ~S: a consequent is required for :leads-to and forbidden otherwise."
                         (spec-temporal-property-name property))))
  (let ((property-names
          (append (mapcar #'spec-invariant-name invariants)
                  (mapcar #'spec-action-property-name action-properties)
                  (mapcar #'spec-temporal-property-name temporal-properties))))
    (ensure-definition (and (every #'symbolp property-names) (unique-p property-names))
                       "Property names of ~A must be unique symbols across invariants, action properties and temporal properties: ~S."
                       name property-names))
  (dolist (condition fairness-conditions)
    (ensure-definition (and (spec-fairness-condition-p condition)
                            (member (spec-fairness-condition-kind condition) '(:weak :strong))
                            (find (spec-fairness-condition-action condition) actions
                                  :key #'spec-action-name))
                       "Fairness condition ~S must be :weak or :strong on a declared action."
                       condition))
  (dolist (constant symmetry)
    (ensure-definition (member constant constants)
                       "Symmetry names ~S, which is not a constant of ~A." constant name)))

(defun make-spec (&key name constants variables init actions invariants
                    action-properties temporal-properties fairness-conditions
                    symmetry (check-deadlock t))
  "Build and validate a specification. CONSTANTS is a plist of model
parameters. VARIABLES is the ordered list of variable names. INIT is a function
of no arguments returning a list of state plists. SYMMETRY lists the constants
whose values are symmetric sets."
  (validate-spec-components name constants variables init actions invariants
                            action-properties temporal-properties
                            fairness-conditions symmetry)
  (%make-spec :name name :constants constants :variables variables :init init
              :actions actions :invariants invariants
              :action-properties action-properties
              :temporal-properties temporal-properties
              :fairness-conditions fairness-conditions
              :symmetry symmetry :check-deadlock (and check-deadlock t)))

(defun spec-constant (spec name)
  "Return the value of the constant NAME."
  (loop for (key value) on (spec-constants spec) by #'cddr
        when (eq key name) do (return value)
        finally (signal-spec-error 'spec-definition-error
                                   "~A has no constant ~S." (spec-name spec) name)))

(defun spec-find-action (spec name)
  "Return the action called NAME, or NIL."
  (find name (spec-actions spec) :key #'spec-action-name))

;;; States.

(defun make-state (spec plist)
  "Return the canonical state for PLIST: every declared variable, in
declaration order. Signal SPEC-DEFINITION-ERROR for a missing, repeated or
undeclared variable and SPEC-STATE-ERROR for a value EQUAL cannot compare."
  (let ((variables (spec-variables spec)))
    (ensure-definition (handler-case
                           (and (listp plist)
                                (let ((size (list-length plist)))
                                  (and size (evenp size))))
                         (type-error () nil))
                       "A state of ~A must be a plist, got ~S." (spec-name spec) plist)
    (let ((keys (loop for key in plist by #'cddr collect key)))
      (ensure-definition (and (unique-p keys)
                              (null (set-difference keys variables))
                              (null (set-difference variables keys)))
                         "State ~S of ~A must assign exactly the variables ~S, each once."
                         plist (spec-name spec) variables))
    (loop for variable in variables
          for value = (getf plist variable)
          do (validate-comparable-value value variable)
          collect variable
          collect value)))

(defun domain-elements (domain what)
  "Return the elements of DOMAIN, a list, without duplicates in first-seen
order. WHAT names the use for error messages. A value-model set is not a list;
pass (SPEC-SET-ELEMENTS set) instead."
  (ensure-definition (and (listp domain)
                          (not (member (first domain)
                                       '(%set %function %record %sequence))))
                     "Domain of ~A must be a list of values; use SPEC-SET-ELEMENTS on a value-model set, got ~S."
                     what domain)
  (let ((seen (make-state-table))
        (elements '()))
    (dolist (element domain)
      (unless (nth-value 1 (state-table-ref seen element))
        (setf (state-table-ref seen element) t)
        (push element elements)))
    (nreverse elements)))

(defun spec-initial-states (spec)
  "Return the initial states of SPEC: canonical, validated, without
duplicates, in the order Init produced them. An Init with no states signals
SPEC-DEFINITION-ERROR."
  (let ((init-states (funcall (spec-init spec))))
    (ensure-definition (listp init-states)
                       "Init of ~A must return a list of states, got ~S."
                       (spec-name spec) init-states)
    (let ((seen (make-state-table))
          (states '()))
      (dolist (plist init-states)
        (let ((state (make-state spec plist)))
          (unless (nth-value 1 (state-table-ref seen state))
            (setf (state-table-ref seen state) t)
            (push state states))))
      (ensure-definition states "Init of ~A produced no initial state." (spec-name spec))
      (nreverse states))))

(defun map-action-bindings (action state function)
  "Call FUNCTION with each list of quantified values of ACTION in STATE. Later
quantifiers may depend on earlier ones. Domains are visited in list order."
  (labels ((walk (quantifiers bound)
             (if (null quantifiers)
                 (funcall function (reverse bound))
                 (destructuring-bind (name domain-function) (first quantifiers)
                   (dolist (value (domain-elements
                                   (apply domain-function state (reverse bound))
                                   (format nil "parameter ~S of action ~S"
                                           name (spec-action-name action))))
                     (walk (rest quantifiers) (cons value bound)))))))
    (walk (spec-action-params action) '())))

(defun apply-update (spec action state update)
  (ensure-definition (handler-case
                         (and (listp update)
                              (let ((size (list-length update)))
                                (and size (evenp size))))
                       (type-error () nil))
                     "Update of action ~S must return a plist, got ~S."
                     (spec-action-name action) update)
  (let ((assigned (loop for key in update by #'cddr collect key)))
    (ensure-definition (and (unique-p assigned)
                            (null (set-difference assigned (spec-variables spec))))
                       "Action ~S assigns ~S; each assigned variable must be declared in ~S and appear once."
                       (spec-action-name action) assigned (spec-variables spec)))
  (loop for variable in (spec-variables spec)
        for unchanged = (list nil)
        for value = (let ((assigned (getf update variable unchanged)))
                      (if (eq assigned unchanged)
                          (state-ref state variable)
                          (validate-comparable-value assigned variable)))
        collect variable
        collect value))

(defun spec-successors (spec state)
  "Return the transitions enabled in STATE as a list of SPEC-TRANSITIONs: for
each action in declaration order, for each binding of its quantifiers in domain
order, those whose guard holds. This is the single successor enumeration every
checker uses.

A transition whose TO equals FROM is returned like any other; stuttering steps
are implicit and never enumerated. Distinct bindings that reach the same TO are
distinct transitions."
  (let ((transitions '()))
    (dolist (action (spec-actions spec))
      (map-action-bindings
       action state
       (lambda (params)
         (when (apply (spec-action-guard action) state params)
           (push (make-spec-transition
                  :action (spec-action-name action)
                  :params params
                  :from state
                  :to (apply-update spec action state
                                    (apply (spec-action-update action) state params)))
                 transitions)))))
    (nreverse transitions)))

(defun spec-deadlock-p (spec state)
  "True when no action of SPEC is enabled in STATE, that is, no guard holds for
any binding. A state whose only enabled steps change nothing is not a deadlock."
  (block search
    (dolist (action (spec-actions spec) t)
      (map-action-bindings
       action state
       (lambda (params)
         (when (apply (spec-action-guard action) state params)
           (return-from search nil)))))))

(defun spec-check-invariants (spec state)
  "Return the names of the invariants STATE violates, in declaration order."
  (loop for invariant in (spec-invariants spec)
        unless (funcall (spec-invariant-predicate invariant) state)
          collect (spec-invariant-name invariant)))

(defun spec-check-action-properties (spec state next-state)
  "Return the names of the action properties violated by the step from STATE
to NEXT-STATE. A stuttering step (NEXT-STATE EQUAL to STATE) violates nothing."
  (unless (equal state next-state)
    (loop for property in (spec-action-properties spec)
          unless (funcall (spec-action-property-relation property) state next-state)
            collect (spec-action-property-name property))))
