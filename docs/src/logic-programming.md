# Logic Programming

cl-weave ships a small, dependency-free logic-query engine — unification with
backtracking, in the miniKanren / Datalog family. It has two uses:

1. **Query your test plan declaratively** — "which tests are focused?", "which
   have a retry budget?" — instead of scraping reporter output (see
   [Test Execution](test-execution.md#test-listing)).
2. **General relational queries** over facts and rules you define.

Data and logic stay separate: relations are plain keyword-headed lists, while
query and rule syntax lives in macros.

## Facts, relations, and variables

- A **relation** is a list whose head is a keyword: `(:parent "grand" "parent")`.
- A **variable** is any symbol whose name starts with `?`, e.g. `?parent`.
  `logic-variable-p` tests for one.
- `logic-program` collects facts and rules into a program. It quotes each
  entry, so you write literal data — no quoting by hand.

```lisp
(cl-weave:logic-variable-p '?parent) ;; => t
(cl-weave:logic-variable-p 'parent)  ;; => nil
```

## Querying: `logic-run`, `logic-where`, `logic-query`

`logic-run` and `logic-where` are query macros of the form
`(logic-run program clause...)`. Each clause is a relation; shared variables
unify across clauses, which are matched left to right. A query returns a list of
solutions, and each solution is an association list mapping the query variables
to their values.

```lisp
(let ((program (cl-weave:logic-program
                (:parent "grand" "parent")
                (:parent "parent" "child"))))
  (cl-weave:logic-run program
    (:parent ?parent "child")))
;; => (((?parent . "parent")))
```

`logic-where` and `logic-run` are two spellings of the same behavior — use
whichever reads better at the call site. Both expand to the underlying
`logic-query` function, which you can call directly when the program or clauses
are computed rather than written literally:

```lisp
(cl-weave:logic-query
 (cl-weave:logic-program (:parent "parent" "child"))
 '((:parent ?p "child")))
;; => (((?p . "parent")))
```

## Rules and recursion

A **rule** uses the Prolog-style `(:- head goal...)` form: the head relation
holds whenever every goal holds. Rules may be recursive, which is what makes the
engine more than a fact lookup.

```lisp
(let ((program (cl-weave:logic-program
                (:parent "grand" "parent")
                (:parent "parent" "child")
                (:- (:ancestor ?left ?right)
                    (:parent ?left ?right))
                (:- (:ancestor ?left ?right)
                    (:parent ?left ?middle)
                    (:ancestor ?middle ?right)))))
  (cl-weave:logic-run program
    (:ancestor ?left "child")))
;; => (((?left . "parent"))
;;     ((?left . "grand")))
```

## Bounding the search

Two leading option clauses bound a query:

- `(:limit n)` caps the number of solutions returned.
- `(:max-steps n)` caps the number of resolution steps before the search stops.

```lisp
(let ((program (cl-weave:logic-program
                (:color :red) (:color :green) (:color :blue))))
  (cl-weave:logic-run program
    (:limit 2)
    (:color ?c)))
;; => (((?c . :red)) ((?c . :green)))
```

Each option accepts `nil` (unbounded) or a positive integer; any other value
signals a `cl-weave` error when the query is built.

## Recovering from an exhausted search

When a query reaches its `:max-steps` budget, cl-weave signals the restartable
`logic-search-exhausted` error. Its readers report the search state —
`logic-search-exhausted-steps`, `logic-search-exhausted-limit`,
`logic-search-exhausted-pending` (frames still to explore), and
`logic-search-exhausted-partial-results`. Two restarts let a handler recover in
place instead of unwinding:

- `return-partial-results` — stop and return the solutions found so far.
- `increase-limit` — continue with a larger step budget (the new limit must
  exceed the steps already taken).

```lisp
(let ((program (cl-weave:logic-program
                (:parent "grand" "parent")
                (:parent "parent" "child")
                (:- (:ancestor ?l ?r) (:parent ?l ?r))
                (:- (:ancestor ?l ?r) (:parent ?l ?m) (:ancestor ?m ?r)))))
  (handler-bind ((cl-weave:logic-search-exhausted
                  (lambda (condition)
                    (declare (ignore condition))
                    (invoke-restart 'cl-weave:return-partial-results))))
    (cl-weave:logic-run program
      (:max-steps 3)
      (:ancestor ?l ?r))))
;; => (((?l . "grand") (?r . "parent")))
```

## Querying the test plan

The engine's primary application is declarative test selection.
`test-plan-facts` turns a collected plan into relations such as `(:test path)`,
`(:status path status)`, `(:focused path)`, `(:retry path n)`,
`(:timeout-ms path ms)`, `(:concurrent path)`, and `(:location path loc)`.
`test-plan-where` (and the `query-test-plan` function) accept either collected
plan entries or an already-expanded fact program, so you can layer derived
views on top of `test-plan-facts` without a second adapter. See
[Test Execution](test-execution.md#test-listing) for worked test-plan queries,
including composing your own `(:- (:selected ?test) ...)` rules.

## Querying the execution journal

The same adapter shape queries a [time-travel journal](time-travel-debugging.md):
`journal-facts` turns a list of `journal-frame`s into relations keyed by frame
index, and `journal-where` (`query-journal`) queries them exactly like
`test-plan-where` — accepting frames or an expanded program, and composing
with your own rules. See [Querying the
timeline](time-travel-debugging.md#querying-the-timeline) for the full
walkthrough.
