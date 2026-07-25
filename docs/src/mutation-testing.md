# Mutation Testing

`collect-mutations` walks a Lisp form and returns one-at-a-time mutant data.
`run-mutations` accepts a predicate that returns true when the mutant survives
the caller's checks and false when the mutant is killed:

```lisp
(cl-weave:run-mutations
 '(+ 1 1)
 (lambda (form mutation)
   (declare (ignore mutation))
   (= (eval form) 2)))
```

Mutation operators are data-backed and macro-extensible:

```lisp
(cl-weave:defmutation-operator :keyword-toggle (form path)
  "Toggles :enabled keyword literals to :disabled."
  (declare (ignore path))
  (when (eq form :enabled)
    (list :disabled)))

(cl-weave:collect-mutations '(:enabled)
                            :operators '(:keyword-toggle))
```

The first string form in `defmutation-operator` becomes stable operator
metadata. `list-mutation-operators` returns deterministic plist metadata for
CI tools and agents — **every** registered operator, sorted by name. After the
`:keyword-toggle` definition above, the four built-ins and the new operator are
all present (descriptions elided here for brevity):

```lisp
(cl-weave:list-mutation-operators)
;; => ((:name :arithmetic-operator :description "...")
;;     (:name :boolean-literal :description "...")
;;     (:name :comparison-operator :description "...")
;;     (:name :conditional-branch :description "...")
;;     (:name :keyword-toggle :description "..."))
```

The built-in operators cover arithmetic calls, comparison calls, boolean
literals, and `if` branch swaps. `report-mutations-sexp` and
`report-mutations-json` emit stable, AI-readable mutation reports with killed,
survived, errored, and score fields. `mutation-summary` returns the same
aggregate as a plist (`:total`, `:killed`, `:survived`, `:errored`, `:score`)
for programmatic use, and each entry in the `run-mutations` result is a
`mutation-result` (readers `mutation-result-status`, `mutation-result-mutation`,
`mutation-result-condition`) wrapping a `mutation` (readers `mutation-id`,
`mutation-operator`, `mutation-path`, `mutation-original`, `mutation-replacement`,
`mutation-form`).

Use `mutation-score-passes-p` or `assert-mutation-score` to turn mutation
results into CI gates. A gate passes only when there are no errored mutants and
the mutation score meets the threshold. Because the score is `killed / total`,
surviving mutants lower the score but do not fail the gate on their own unless
they push the score below the threshold:

```lisp
(let ((results (cl-weave:run-mutations
                '(+ 1 1)
                (lambda (form mutation)
                  (declare (ignore mutation))
                  (= (eval form) 2)))))
  (cl-weave:assert-mutation-score results 0.95))
```
