(defpackage #:cl-weave/spec
  (:use #:cl)
  (:documentation
   "TLA+-style specifications for cl-weave, written in Lisp. A specification
declares constants, variables, an Init, named actions and properties; the
checkers explore its state space exhaustively or randomly, check refinement
between two specifications, and compare an implementation with a specification
sequentially or under concurrency. This system depends on cl-weave and adds no
export to it: core internals are reached with cl-weave:: where needed.

Every symbol exported here is decided up front, one block per module, so the
modules can be implemented in parallel without editing each other's blocks.
Module contracts live in .reinloom/tla-spec/CONTRACTS.md.")
  (:export
   ;; ------------------------------------------------------------------
   ;; conditions (src/spec/conditions.lisp)
   #:spec-error
   #:spec-error-message
   #:spec-definition-error
   #:spec-configuration-error
   #:spec-value-error
   #:spec-state-error
   #:spec-state-error-variable
   #:spec-state-error-value

   ;; ------------------------------------------------------------------
   ;; value model, FR-002 (src/spec/values.lisp)
   #:make-spec-set
   #:spec-set
   #:spec-set-p
   #:spec-set-elements
   #:spec-set-size
   #:spec-set-member-p
   #:spec-set-union
   #:spec-set-intersection
   #:spec-set-difference
   #:spec-subset-p
   #:spec-powerset
   #:spec-set-filter
   #:spec-set-map
   #:spec-set-of
   #:make-spec-function
   #:spec-function-over
   #:spec-function-p
   #:spec-function-domain
   #:spec-function-apply
   #:spec-function-except
   #:spec-function-pairs
   #:make-spec-record
   #:spec-record-p
   #:spec-record-ref
   #:spec-record-except
   #:spec-record-fields
   #:make-spec-sequence
   #:spec-sequence
   #:spec-sequence-p
   #:spec-sequence-elements
   #:spec-sequence-concat
   #:spec-sequence-length
   #:spec-sequence-ref
   #:value<
   #:map-value-atoms

   ;; ------------------------------------------------------------------
   ;; states, fingerprints and state tables, FR-002/FR-003 (src/spec/state.lisp)
   #:state-ref
   #:state-fingerprint
   #:validate-comparable-value
   #:make-state-table
   #:state-table-p
   #:state-table-ref
   #:state-table-count
   #:map-state-table

   ;; ------------------------------------------------------------------
   ;; specification objects, enumeration and results, FR-003 (src/spec/spec.lisp)
   #:spec
   #:make-spec
   #:spec-p
   #:spec-name
   #:spec-constants
   #:spec-variables
   #:spec-init
   #:spec-actions
   #:spec-invariants
   #:spec-action-properties
   #:spec-temporal-properties
   #:spec-fairness-conditions
   #:spec-symmetry
   #:spec-check-deadlock
   #:spec-constant
   #:spec-find-action
   #:spec-action
   #:make-spec-action
   #:spec-action-p
   #:spec-action-name
   #:spec-action-params
   #:spec-action-guard
   #:spec-action-update
   #:spec-action-output
   #:spec-invariant
   #:make-spec-invariant
   #:spec-invariant-p
   #:spec-invariant-name
   #:spec-invariant-predicate
   #:spec-action-property
   #:make-spec-action-property
   #:spec-action-property-p
   #:spec-action-property-name
   #:spec-action-property-relation
   #:spec-temporal-property
   #:make-spec-temporal-property
   #:spec-temporal-property-p
   #:spec-temporal-property-name
   #:spec-temporal-property-kind
   #:spec-temporal-property-predicate
   #:spec-temporal-property-consequent
   #:spec-fairness-condition
   #:make-spec-fairness-condition
   #:spec-fairness-condition-p
   #:spec-fairness-condition-kind
   #:spec-fairness-condition-action
   #:make-state
   #:spec-initial-states
   #:spec-successors
   #:spec-deadlock-p
   #:spec-check-invariants
   #:spec-check-action-properties
   #:spec-transition
   #:make-spec-transition
   #:spec-transition-p
   #:spec-transition-action
   #:spec-transition-params
   #:spec-transition-from
   #:spec-transition-to
   #:trace-step
   #:make-trace-step
   #:trace-step-p
   #:trace-step-action
   #:trace-step-params
   #:trace-step-state
   #:lasso
   #:make-lasso
   #:lasso-p
   #:lasso-prefix
   #:lasso-cycle
   #:spec-violation
   #:make-spec-violation
   #:spec-violation-p
   #:spec-violation-kind
   #:spec-violation-property
   #:spec-violation-trace
   #:spec-violation-detail
   #:spec-result
   #:make-spec-result
   #:spec-result-p
   #:spec-result-spec-name
   #:spec-result-mode
   #:spec-result-violation
   #:spec-result-states-found
   #:spec-result-depth-reached
   #:spec-result-truncated
   #:spec-result-truncation-reason
   #:spec-result-liveness-requested
   #:spec-result-allow-bounded
   #:spec-result-checked-properties
   #:spec-result-limits
   #:spec-result-statistics
   #:spec-result-passed-p
   #:state-graph
   #:make-state-graph
   #:state-graph-p
   #:state-graph-spec
   #:state-graph-initial-states
   #:state-graph-edges
   #:state-graph-complete-p
   #:*default-max-states*
   #:*default-max-depth*
   #:*default-max-simulation-steps*
   #:*default-linearization-budget*

   ;; ------------------------------------------------------------------
   ;; DSL macros, FR-003 (src/spec/dsl.lisp)
   #:specification
   #:defspec
   #:next

   ;; ------------------------------------------------------------------
   ;; symmetry reduction, FR-008 (src/spec/symmetry.lisp)
   #:spec-state-canonicalizer

   ;; ------------------------------------------------------------------
   ;; liveness and fairness, FR-007 (src/spec/liveness.lisp)
   #:check-temporal-properties

   ;; ------------------------------------------------------------------
   ;; exhaustive search and safety, FR-004/FR-005 (src/spec/explore.lisp)
   #:explore-spec

   ;; ------------------------------------------------------------------
   ;; random search, FR-006 (src/spec/random.lisp)
   #:simulate-spec
   #:generate-action-sequence
   #:replay-action-sequence
   #:shrink-action-sequence

   ;; ------------------------------------------------------------------
   ;; refinement, FR-009 (src/spec/refinement.lisp)
   #:check-refinement

   ;; ------------------------------------------------------------------
   ;; sequential conformance, FR-010 (src/spec/conformance-sequential.lisp)
   #:check-sequential-conformance

   ;; ------------------------------------------------------------------
   ;; concurrent conformance and linearizability, FR-011
   ;; (src/spec/conformance-concurrent.lisp)
   #:check-linearizability
   #:linearizable-history-p
   #:make-history-operation
   #:history-operation-p
   #:history-operation-id
   #:history-operation-thread
   #:history-operation-action
   #:history-operation-params
   #:history-operation-output
   #:history-operation-invoked
   #:history-operation-returned

   ;; ------------------------------------------------------------------
   ;; counterexample reporting and journal frames, FR-013 (src/spec/report.lisp)
   #:spec-result-payload
   #:report-spec-result
   #:format-spec-trace

   ;; ------------------------------------------------------------------
   ;; test registration, FR-012 (src/spec/registration.lisp)
   #:it-spec
   #:it-spec-only
   #:it-spec-skip
   #:it-spec-todo))
