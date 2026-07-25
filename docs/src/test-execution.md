# Test Execution

## Filtering

```lisp
(cl-weave:run-all :name-filter "math > adds")
```

`name-filter` is a case-insensitive substring matched against the rendered test
path, for example `suite > nested suite > case`. Filtering composes with
`describe-only` and `it-only`: focus narrows the candidate set first, then the
name filter selects matching paths.

For command-line and CI usage, use `--filter`:

```sh
timeout 120s nix run . -- run cl-weave/tests --filter 'math > adds'
```

Suites with no selected descendants do not run `before-all` or `after-all`, so
filtered runs do not leak fixture side effects from unrelated suites.
By default, a filter that selects zero tests exits successfully. CI jobs that
must reject empty selections can pass `--fail-with-no-tests`, set
`CL_WEAVE_PASS_WITH_NO_TESTS=false`, or call
`(cl-weave:run-all :pass-with-no-tests nil)`.

## Sharding

```lisp
(cl-weave:run-all :shard '(1 3))
(cl-weave:list-tests :reporter :json :shard '(2 3))
```

Shard indexes are one-based and use `(INDEX COUNT)`. cl-weave first applies
focus and `name-filter`, then assigns a stable discovery ordinal to the selected
tests. A test belongs to shard `INDEX` when its ordinal maps to that slot.

For command-line and CI usage, `--shard` uses `INDEX/COUNT`:

```sh
timeout 120s nix run . -- run cl-weave/tests --shard 1/3 --reporter json
```

Sharding composes with filtering, list mode, bail, ASDF `run-system`, and watch
mode. Suites with no descendants in the requested shard do not run
`before-all` or `after-all`.

## Sequence Ordering

```lisp
(cl-weave:run-all :order :random :seed 12345)
(cl-weave:list-tests :reporter :json :order :random :seed 12345)
```

The default order is `:defined`. `:order :random` applies a deterministic,
seeded order inside each suite while preserving suite hook boundaries. The same
seed produces the same execution order and list-mode order across SBCL
processes.

Selection is resolved before ordering: focus, `name-filter`, and shard choose
the test set first, then sequence ordering decides the order of the remaining
children. This keeps CI shard membership stable when teams rotate seeds to
reproduce order-dependent failures.

For command-line and CI usage:

```sh
timeout 360s nix run . -- run cl-weave/tests --sequence random --seed 12345
```

`--seed` controls the sequence *ordering*; it is independent of `--random-seed`,
which seeds `cl:random` inside test bodies for deterministic replay (below).

## Deterministic Replay

```lisp
(let ((cl-weave:*test-random-seed* 20260724))
  (cl-weave:run-all :reporter :json))

(cl-weave:replay-test "math > adds numbers" :seed 20260724)
```

Binding `*test-random-seed*` (or passing `--random-seed INTEGER`) seeds
`cl:*random-state*` per test from that base seed and the test's path, so
`cl:random` is reproducible and independent of execution order. The effective
per-test seed is recorded on each event and reported as `replaySeed`.
`replay-test` re-runs a single test by its Vitest-style path with journaling on,
returning the event and its recorded timeline — the fastest way to reproduce and
inspect one failure in isolation.

```sh
timeout 360s nix run . -- run cl-weave/tests --journal --random-seed 20260724
```

`--journal` records an execution-journal timeline (assertions, mock calls,
fixture hooks, and notes) for each attempt. See
[Time-Travel Debugging](time-travel-debugging.md) for the complete workflow,
including `with-execution-journal` and `journal-note`.

## Test Listing

```lisp
(cl-weave:list-tests :reporter :json :name-filter "math")
(cl-weave:collect-test-plan (cl-weave::root-suite) :name-filter "math")
```

List mode discovers selected tests without executing suite hooks or test
bodies. It composes with focus, filtering, skipped suites, and todo suites, and
emits `:run`, `:skip`, or `:todo` plan entries with `path`, `pathString`,
`location`, `reason`, `focused`, `retry`, `timeout-ms`, `concurrent`, and
`tags` metadata. `location` records the macro source file when
available; JSON emits `null` for manually constructed tests without source
metadata. Native test tags participate in
selection through `:include-tags` and `:exclude-tags` on `run`, `run-all`, and
`list-tests`. Inclusion accepts a test matching any requested tag; exclusion
rejects a test matching any excluded tag. Tag selection is resolved before
sharding.

For command-line and CI usage, `list` prints the selected test plan
and exits with status `0`:

```sh
timeout 120s nix run . -- list cl-weave/tests --reporter json --filter 'math'
```

List mode supports `spec`, `sexp`, `json`, and `jsonl` reporters. `--output FILE`
writes the plan payload to an artifact file.

AI agents can also query plans as plain Lisp facts:

```lisp
(cl-weave:test-plan-where
 (cl-weave:collect-test-plan (cl-weave::root-suite))
 (:status ?test :run)
 (:focused ?test)
 (:concurrent ?test))
;; => (((?test . ("suite" "case"))))
```

`test-plan-facts` emits data such as `(:test path)`, `(:status path status)`,
`:focused`, `:reason`, `:retry`, `:timeout-ms`, and `:location`. Each entry
returned by `collect-test-plan` is a `test-plan-entry` struct with matching
readers — `test-plan-entry-path`, `test-plan-entry-status`,
`test-plan-entry-focused`, `test-plan-entry-reason`, `test-plan-entry-retry`,
`test-plan-entry-timeout-ms`, `test-plan-entry-concurrent`,
`test-plan-entry-tags`, and `test-plan-entry-location` — so you can inspect a
plan directly without going through the fact relations.
`logic-where`, `logic-program`, `logic-run`, and `test-plan-where` keep data and
logic separate: relations stay plain lists, while query and rule syntax stays in
macros. Variables are symbols whose names start with `?`, clauses are matched
left-to-right, and `(:limit n)` caps backtracking results. See
[Logic Programming](logic-programming.md) for the full engine — the
`logic-query` function, `:max-steps` bounding, and the `logic-search-exhausted`
recovery restarts.

Rules use a Prolog-style `(:- head goal...)` form:

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

`query-test-plan` and `test-plan-where` accept either collected plan entries or
an already-expanded logic program, so derived views can be layered on top of
`test-plan-facts` without a second adapter:

```lisp
(let* ((plan (cl-weave:collect-test-plan (cl-weave::root-suite)))
       (program (append
                 (cl-weave:test-plan-facts plan)
                 (cl-weave:logic-program
                  (:- (:selected ?test)
                      (:status ?test :run)
                      (:focused ?test))))))
  (cl-weave:test-plan-where program
    (:selected ?test)))
```

## Bail

```lisp
(cl-weave:run-all :bail t)
(cl-weave:run-all :bail 2)
```

`:bail t` stops after the first `:fail` or `:error` event. A positive integer
stops after that many failing or errored events. Skips and todos do not count
toward the bail limit.

For command-line and CI usage, `--bail` accepts `true`, `yes`, `on`,
`t`, `false`, `no`, `off`, `0`, `nil`, or a positive integer:

```sh
timeout 120s nix run . -- run cl-weave/tests --bail 1
```

`--bail` is an optional-value flag, so it may also appear on its own. A bare
`--bail` defaults to `true`, and the separated form only consumes the following
token when that token is a valid bail literal (one of the values above). A
positional target after a bare `--bail` is therefore left for argument parsing
rather than swallowed, so both of these select `cl-weave/tests` with
fast-fail enabled:

```sh
timeout 120s nix run . -- run --bail cl-weave/tests
timeout 120s nix run . -- run cl-weave/tests --bail
```

Use the inline `--bail=VALUE` form to force value parsing; an invalid inline
value (for example `--bail=maybe`) is reported as an error instead of being
reinterpreted as a positional argument.

Bail composes with focus and filtering. Reporters emit only the events that were
selected and executed before the runner stopped.

## Subprocess Isolation

```lisp
(it-isolated "ffi parser rejects invalid input"
    (:systems ("my-project-tests") :timeout 5 :keep-files :on-failure)
  (expect (parse-native-buffer #(0 1 2)) :to-equal :invalid))

(let ((result (run-isolated
               '(error "native boundary failed")
               :systems '("my-project-tests")
               :package "MY-PROJECT/TESTS"
               :timeout 5
               :keep-files :on-failure)))
  (expect (isolated-result-status result) :to-be :fail))
```

`it-isolated` runs the body in a fresh SBCL subprocess and reports non-zero
exits or timeouts as normal structured assertion failures. Use it around FFI,
native parser, and crash-boundary tests where the parent REPL or CI process
must stay alive. `run-isolated` returns captured stdout/stderr strings in all
cases. Alongside `isolated-result-status`, `isolated-result-stdout`, and
`isolated-result-stderr`, the result reports `isolated-result-exit-code`,
`isolated-result-elapsed-ms`, and `isolated-result-timed-out-p` for the child's
exit status, wall-clock duration, and whether it hit the isolation timeout.
`:keep-files` accepts `nil`, `t`, or `:on-failure`; the last option keeps
artifacts only for non-passing child processes. When files are retained, the
generated script, stdout, stderr, and temporary HOME directory paths are exposed
via
`isolated-result-script-path`, `isolated-result-stdout-path`,
`isolated-result-stderr-path`, and `isolated-result-home-path`. With the
default `:keep-files nil`, those public path accessors always return `nil`.
Cleanup is synchronous: control returns to the parent only after an
`unwind-protect` cleanup clause has made a best-effort attempt to delete the
script, stdout, stderr, and home-directory files (`delete-file` and
`uiop:delete-directory-tree`, each wrapped in `ignore-errors`). There is no
cleanup registry, retry queue, or background worker; a delete that fails is
silently skipped rather than retried.

`run-isolated` spawns a single SBCL subprocess via `sb-ext:run-program` and
tracks only that direct child; it does not create a separate session or
process group, and it does not track or signal any grandchild processes the
child spawns. On timeout, the tracked child receives `SIGTERM` (15), then
`SIGKILL` (9) after a short grace period if it is still alive. This is process
cleanup for the direct child only, not an OS security sandbox or a containment
guarantee over descendant processes.

## ASDF System Runner And Watch Mode

```lisp
(cl-weave:asdf-system-files "my-project-tests" :include-dependencies t)
(cl-weave:run-system "my-project-tests" :reporter :spec)
(cl-weave:watch-system "my-project-tests"
                       :reporter :json
                       :name-filter "parser"
                       :shard '(1 2)
                       :bail 1
                       :coverage t
                       :coverage-output "my-project-tests.coverage"
                       :pass-with-no-tests t
                       :include-dependencies t
                       :interval 0.5)
```

`asdf-system-files` returns the existing source files declared by an ASDF
system. `run-system` reloads the system with ASDF, then runs the currently
registered cl-weave tests. `watch-system` uses ASDF dependency information and
file write dates to rerun only after declared source files change. When every
changed file is a registered test-definition file or an explicit dependency,
watch mode narrows the rerun to the affected tests. Declare dependencies on a
test with `:watch-depends-on`; relative paths are resolved from the file that
defines the test:

```lisp
(it "parses tokens" (:watch-depends-on '("../src/parser.lisp"))
  (expect (parse-token "name") :to-equal '(:name "name")))
```

Changes to unknown files, newly added files, or deleted files fall back to a
full-suite rerun so implementation edits cannot silently skip affected tests.
Coverage collection and `:pass-with-no-tests` policy are forwarded on every
watch rerun, so local watch sessions exercise the same success criteria and
coverage artifact path as an equivalent one-shot `run-all`.
Reporter output goes to `:stream`; watch status goes to `:status-stream`, which
defaults to `*error-output*`.

The script runner enables watch mode with environment variables:

```sh
timeout 360s nix run . -- watch cl-weave/tests
timeout 360s nix run . -- watch cl-weave/tests --once
timeout 360s nix run . -- watch cl-weave/tests --watch-interval 0.25
```

CI should use `run` rather than `watch`, with `--reporter junit`, `tap`,
`json`, or `jsonl` as appropriate.
