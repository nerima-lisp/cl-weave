# Time-Travel Debugging

`cl-weave` can record a chronological **execution journal** of what happened
inside each test attempt. This is the first layer of a time-travel debugging
workflow: a "flight recorder" timeline you can inspect after the fact instead
of sprinkling `print` statements and re-running.

The journal leans on Common Lisp strengths the framework already uses — the
condition system records a failing assertion *before* the failure unwinds the
stack, and dynamic bindings scope one journal per (possibly concurrent) test
attempt.

## Enabling the journal

Journaling is **off by default** so the hot `expect` path stays
allocation-free. Bind `cl-weave:*journal-enabled*` around a run to opt in:

```lisp
(let ((cl-weave:*journal-enabled* t))
  (cl-weave:run-all :reporter :json))
```

The flag rides in the runner's dynamic environment, so concurrent worker
threads inherit it automatically.

From the command line, pass `--journal` (and, for reproducible randomness,
`--random-seed N`) to `run` or `watch`:

```sh
nix run . -- run --journal --random-seed 42 --reporter json my-system
```

`--journal` enables the timeline; `--random-seed` sets the deterministic replay
base seed described under [Deterministic replay](#deterministic-replay).

## What a frame captures

Each recorded assertion becomes a `journal-frame` with these public readers:

| Reader | Meaning |
| --- | --- |
| `journal-frame-index` | 0-based position in the timeline |
| `journal-frame-kind` | frame category: `:assertion`, `:mock-call`, `:hook`, `:shrink-step`, `:note`, or [a kind of your own](#custom-frame-kinds) |
| `journal-frame-form` | the source form of the assertion |
| `journal-frame-matcher` | matcher keyword (`:to-be`), operator (`=`), or `:truthy` |
| `journal-frame-actual` | reported actual value / operand reports |
| `journal-frame-expected` | reported expected value / original form |
| `journal-frame-pass` | whether the assertion passed |
| `journal-frame-elapsed-internal-time` | ticks since the attempt started |

Both passing and failing assertions are recorded, so the timeline shows the
full lead-up to a failure — not just the assertion that finally blew up.

Mock invocations and fixture hooks are interleaved automatically. Every call to
a mock built with `make-mock-function`, `spy-on`, or `with-mocked-functions`
adds a `:mock-call` frame carrying its arguments, and each `before-each` /
`after-each` hook adds a `:hook` frame recording the phase and whether it
succeeded. Inside a failing `it-property` test, every candidate the shrinker
tries adds a `:shrink-step` frame — see [Watching a Shrink
Run](property-testing.md#watching-a-shrink-run) for details. The timeline
therefore reads as a chronological lifecycle trace — the setup, the calls, the
assertions, and the teardown in the order they happened:

```
      #0 hook before-each -> ok
      #1 mock-call (42)
      #2 assertion (EXPECT USER :TO-EQUAL EXPECTED) -> ok
      #3 assertion (EXPECT TOTAL :TO-BE 3) -> FAIL
      #4 hook after-each -> ok
```

## Reading the timeline from JSON

The JSON reporter emits a `timeline` array on every event. With journaling
off it is simply `[]`; with journaling on it contains one object per frame:

```json
{
  "status": "fail",
  "path": ["math", "adds numbers"],
  "assertion": { "matcher": ":to-be", "pass": false },
  "timeline": [
    { "index": 0, "kind": "assertion", "form": "(EXPECT (+ 1 2) :TO-BE 3)",
      "matcher": ":to-be", "actual": 3, "expected": 3, "pass": true,
      "elapsedInternalTime": 4 },
    { "index": 1, "kind": "assertion", "form": "(EXPECT (+ 1 1) :TO-BE 3)",
      "matcher": ":to-be", "actual": 2, "expected": 3, "pass": false,
      "elapsedInternalTime": 9 }
  ]
}
```

This addition is nested inside each event, so the top-level `test-results`
schema is unchanged.

## Reloading a saved timeline

The `sexp` reporter emits the same timeline as **readable Lisp data** — each
frame is a plist, and the whole results artifact is one form you can `read`
back. `journal-frame-from-plist` (and its list form `journal-frames-from-plists`)
is the exact inverse of that serialization, rebuilding `journal-frame` objects
from the saved plists. That closes the loop between CI and your REPL: capture a
run as an artifact in CI, then reconstruct its timeline locally and hand it to
every offline analysis tool — `explain-journal`, `journal-diff`,
`explain-journal-diff`, and `journal-where`:

```sh
cl-weave run --reporter sexp my-system > results.sexp
```

```lisp
(with-open-file (in "results.sexp")
  (let* ((artifact (read in))                       ; homoiconic: just READ it
         (event (first (getf (rest artifact) :events)))
         (frames (journal-frames-from-plists (getf event :timeline))))
    (princ (explain-journal frames))))
;; #0 assertion (EXPECT TOTAL :TO-BE 3) -> FAIL
```

No bespoke parser is involved — the sexp artifact *is* Lisp, so `read` plus
`journal-frame-from-plist` is the entire pipeline. A rebuilt timeline is
indistinguishable from a live one: `journal-diff` between a reconstructed run
and a fresh local run isolates exactly what changed between CI and your
machine.

## Reading the timeline in the terminal

The `spec` reporter prints the recorded timeline (and the replay seed, if any)
underneath each **failed** test, so you see the lead-up without leaving the
terminal or parsing JSON:

```
[FAIL] math > adds numbers (0.000s)
    condition: Test assertion failed: (EXPECT TOTAL :TO-BE 3)
    form: (EXPECT TOTAL :TO-BE 3)
    timeline (2 frames):
      #0 assertion (EXPECT PARTIAL :TO-BE 1) -> ok
      #1 assertion (EXPECT TOTAL :TO-BE 3) -> FAIL
    replay seed: 20260724 (bind *test-random-seed* to reproduce)
```

Passing tests stay a single line — the timeline is only expanded where it
helps.

## Recording notes and REPL inspection

`journal-note` drops a labelled value onto the timeline. It returns the value,
so you can wrap any expression transparently — a structured, replayable
alternative to a debugging print:

```lisp
(it "computes a running total"
  (let ((total (journal-note :total (reduce #'+ items))))
    (expect total :to-be 6)))
```

When journaling is off, `journal-note` is a no-op that just returns its value.

For ad-hoc exploration at the REPL, `with-execution-journal` runs a body with
journaling active and hands back the recorded frames:

```lisp
(with-execution-journal
  (expect 1 :to-be 1)
  (journal-note :sum (+ 1 2))
  (expect (evenp 4)))
;; => list of three journal-frame objects
```

`explain-journal` renders any frame list — from `with-execution-journal`,
`replay-test`, or a JSON timeline — as human-readable lines (returning a string,
or writing to a stream), using the same one-line format the spec reporter prints:

```lisp
(princ (explain-journal (replay-test "math > adds numbers")))
;; #0 assertion (EXPECT (+ 1 1) :TO-BE 2) -> ok
```

## Custom frame kinds

`journal-note` always records under `:note`. For a domain-specific event kind
of your own — say `:http-request` in an integration test, or `:state-change`
in a simulation — record it directly with the lower-level `record-journal-frame`,
the same function `journal-note` and every built-in frame kind (`:assertion`,
`:mock-call`, `:hook`, `:shrink-step`) are built on:

```lisp
(record-journal-frame :http-request
                      :form "GET /orders/42"
                      :actual response-status
                      :pass (= response-status 200))
```

Rendering falls back to the generic one-line format above, but you can give
your kind its own rendering by specializing `journal-frame-line-for-kind` —
an `eql`-specialized generic function `journal-frame-line` (and therefore the
spec reporter, `explain-journal`, and `explain-journal-diff`) all dispatch
through, so extending the timeline for a new kind never requires modifying
cl-weave itself:

```lisp
(defmethod journal-frame-line-for-kind ((kind (eql :http-request)) frame)
  (format nil "#~D ~A -> ~:[~A~;ok~]"
          (journal-frame-index frame)
          (journal-frame-form frame)
          (journal-frame-pass frame)
          (journal-frame-actual frame)))
```

This is the same open/closed extension point CLOS gives any generic function:
your method lives in your own test helpers, cl-weave never sees it, and it
composes with everything already built on `journal-frame-line` — breakpoints,
`journal-diff`, `journal-where`, and the reporters alike.

## Deterministic replay

A timeline is only actionable if you can make the failure happen again. Bind
`cl-weave:*test-random-seed*` to a non-negative integer and every test attempt
runs with `cl:*random-state*` deterministically derived from that base seed and
the test's own path:

```lisp
(let ((cl-weave:*test-random-seed* 20260724))
  (cl-weave:run-all :reporter :json))
```

Two properties make this useful:

- **Reproducible.** Re-running with the same base seed reproduces every
  `cl:random` draw in every test, so a flaky failure becomes a fixed one.
- **Order-independent.** Because each test's seed is mixed with its path, a
  test draws the same numbers whether it runs first, last, sharded, or
  concurrently. Sequencing changes cannot perturb it.

Or from the command line:

```sh
nix run . -- run --random-seed 20260724 my-system
```

The effective per-test seed is recorded on each event and surfaced in the JSON
reporter as `replaySeed` (or `null` when replay is disabled). Deterministic
seeding uses SBCL's `sb-ext:seed-random-state`; on other implementations the
seed is still reported but the random state is left untouched.

## Replaying a single test

`replay-test` re-runs one registered test in isolation with journaling on and
hands back its event and timeline. Give it the same Vitest-style path a reporter
printed, plus the `replaySeed`'s base seed to reproduce randomness exactly:

```lisp
(multiple-value-bind (event frames)
    (replay-test "math > adds numbers" :seed 20260724)
  (declare (ignore event))
  frames)
;; => the recorded journal-frame timeline for that one test
```

The path may be a `" > "`-joined string or a list of name strings. Without
`:seed`, the current `*test-random-seed*` applies. This is the programmatic core
of a time-travel workflow: reproduce a failure, then inspect exactly what led to
it — without re-running the whole suite.

## Comparing two runs

When a test is flaky, the question is *where* two runs diverged. `journal-diff`
compares two timelines frame by frame (ignoring timing) and returns the first
behavioural divergence, or `nil` when they match:

```lisp
(journal-diff
 (replay-test "cart > applies discount" :seed 1)
 (replay-test "cart > applies discount" :seed 2))
;; => (:index 3 :a #<journal-frame …> :b #<journal-frame …> :reason :mismatch)
```

The result plist carries `:index` (where they first differ), the two frames as
`:a` / `:b`, and a `:reason` of `:mismatch` (aligned frames differ) or `:length`
(one run recorded more frames than the other). Pairing it with `replay-test`
turns "sometimes it fails" into a precise pointer at the first step that changed.

`explain-journal-diff` renders that plist as human-readable text, the same way
`explain-journal` renders a frame list -- returning a string, or writing to a
stream -- so the divergence is copy-pasteable into a commit message, a CI log,
or a chat message without hand-formatting a plist:

```lisp
(princ (explain-journal-diff
        (journal-diff (replay-test "cart > applies discount" :seed 1)
                      (replay-test "cart > applies discount" :seed 2))))
;; diverged at frame #3 (mismatch)
;;   a: #3 assertion (EXPECT DISCOUNT :TO-BE 10) -> ok
;;   b: #3 assertion (EXPECT DISCOUNT :TO-BE 10) -> FAIL
```

A `nil` diff (no divergence) renders as `"no divergence: both timelines
matched"`, and a `:length` divergence renders the missing side as an explicit
placeholder rather than erroring on a `nil` frame.

## Querying the timeline

A timeline is a list of `journal-frame`s, and cl-weave already has a
declarative query engine for lists of facts: the [logic-query
engine](logic-programming.md) that powers `test-plan-where`. `journal-facts`
turns frames into the same kind of relations — `(:frame index)`, `(:kind index
kind)`, `(:form index form)`, `(:actual index actual)`, `(:expected index
expected)`, `(:pass index generalized-boolean)`, `(:elapsed-internal-time
index ticks)`, and `(:matcher index matcher)` when the frame has one — and
`journal-where` (with `query-journal` as its function form) queries them with
the same Prolog-style clauses as `logic-where` and `test-plan-where`:

```lisp
(let ((frames (replay-test "cart > applies discount")))
  (journal-where frames
    (:kind ?index :assertion)
    (:pass ?index nil)))
;; => (((?index . 3)) ((?index . 7)))
```

Because `journal-where` accepts either a frame list or an already-expanded
fact program, derived views compose the same way `test-plan-where` does —
append a `(:- head goal...)` rule onto `journal-facts` to name a pattern once
and reuse it, for example finding every assertion that failed only after a
shrink step landed on a new candidate:

```lisp
(let ((program (append
                (journal-facts frames)
                (logic-program
                 (:- (:regressed ?assertion-index ?shrink-index)
                     (:kind ?shrink-index :shrink-step)
                     (:pass ?shrink-index t)
                     (:kind ?assertion-index :assertion)
                     (:pass ?assertion-index nil))))))
  (journal-where program (:regressed ?assertion-index ?shrink-index)))
```

## Interactive breakpoints

The first three layers tell you *what* happened and let you make it happen
again. The fourth lets you stop time exactly where it matters and look around
— using nothing more exotic than Common Lisp's condition system and the real
debugger, since SBCL has no re-entrant continuations to rewind with.

Bind `cl-weave:*journal-breakpoint*` to an integer frame index, or a function
of one `journal-frame`, and the instant `record-journal-frame` records a
matching frame it signals `journal-breakpoint-hit` — with the test's dynamic
environment (locals, closures, call stack) still live:

```lisp
(replay-test "cart > applies discount" :seed 1 :breakpoint 3)
```

Left unhandled, a signalled `journal-breakpoint-hit` falls through to a real
`break`, dropping you into the interactive debugger at frame 3 — from there
`(current-journal-frames)` shows everything recorded so far, and the standard
`continue` restart resumes the test. `replay-test`'s `:breakpoint` argument is
the ergonomic entry point; the underlying `*journal-breakpoint*` special can
also be bound directly around `run-all` or `with-execution-journal` for the
same effect.

The natural pairing is with `journal-diff`: diff two runs to find the frame
index where they diverged, then replay with a breakpoint at that index to land
precisely on the divergence with the full call stack in hand:

```lisp
(let ((divergence (journal-diff
                    (replay-test "cart > applies discount" :seed 1)
                    (replay-test "cart > applies discount" :seed 2))))
  (replay-test "cart > applies discount" :seed 2
               :breakpoint (getf divergence :index)))
```

Because breaking is just a signal, tooling isn't limited to the debugger:
`handler-bind` the condition, read `journal-breakpoint-hit-frame`, and invoke
its `continue` restart to intercept a hit programmatically — for a custom
IDE integration, a logging probe, or (as in `cl-weave`'s own test suite) to
assert breakpoints fire at the right frame without ever touching a live
debugger. A function breakpoint composes with any predicate over a frame, for
example breaking only on the first *failing* assertion:

```lisp
(replay-test "cart > applies discount"
             :breakpoint (lambda (frame)
                           (and (eq (journal-frame-kind frame) :assertion)
                                (not (journal-frame-pass frame)))))
```

`*journal-breakpoint*` defaults to `nil`, so — like journaling itself — the
feature costs nothing until it is explicitly bound.

## Roadmap

The execution journal, deterministic replay, single-test replay, and
interactive breakpoints cover a complete time-travel design:

1. **Execution journal** — the assertion timeline described above. *(done)*
2. **Deterministic replay** — reproducible, order-independent per-test
   randomness with recorded seeds. *(done)*
3. **Single-test replay** — `replay-test` re-runs one test by path with its
   timeline and a reproducible seed. *(done)*
4. **Interactive breakpoints** — `*journal-breakpoint*` signals
   `journal-breakpoint-hit` at a chosen frame, dropping into a live debugger
   (or a `handler-bind`-driven programmatic hook) with the test's full dynamic
   environment intact. *(done)*

Cutting across all four layers, `journal-where` and `journal-facts` open the
timeline to the same declarative logic-query engine that already powers
`test-plan-where` — see [Querying the timeline](#querying-the-timeline).
