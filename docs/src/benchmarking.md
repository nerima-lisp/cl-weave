# Benchmarking

cl-weave includes a small, dependency-free micro-benchmarking helper for
*observing* how long code takes. It is deliberately separate from the assertion
engine: benchmarks report timings for you to read, while stable CI limits belong
in per-test `:timeout-ms` (see [Test Execution](test-execution.md)) or the
`:to-run-under-ms` matcher (see [Assertions and Matchers](assertions.md)).

## `benchmark` and `measure`

`benchmark` is a macro that times a body with its lexical bindings intact;
`measure` is the function it expands to, for when you already have a thunk.

```lisp
(let ((result (cl-weave:benchmark (:warmup 2 :samples 5 :iterations 100)
                (reduce #'+ (list 1 2 3 4 5)))))
  (cl-weave:mean-ms result))
```

```lisp
(cl-weave:measure (lambda () (reduce #'+ (list 1 2 3 4 5)))
                  :warmup 2 :samples 5 :iterations 100)
```

Both accept the same three options:

- `:warmup` — calls made and discarded before timing, to settle caches and JIT
  state (default `0`).
- `:samples` — number of timed samples collected (default `10`).
- `:iterations` — calls per sample; each sample is the **average** elapsed
  milliseconds of this many calls, which smooths out clock granularity for very
  fast code (default `1`).

`:warmup` must be a non-negative integer; `:samples` and `:iterations` must be
positive integers. Invalid values fail fast with a `cl-weave` error.

## Reading the result

Both forms return a `benchmark-result`. Its accessors expose the raw data, and
four helpers summarize the samples:

| Accessor / helper | Meaning |
| --- | --- |
| `benchmark-result-samples` | list of per-sample average milliseconds |
| `benchmark-result-iterations` | calls averaged into each sample |
| `benchmark-result-warmup` | warmup calls that were discarded |
| `minimum-ms` | fastest sample |
| `maximum-ms` | slowest sample |
| `mean-ms` | arithmetic mean of the samples |
| `median-ms` | median sample |

```lisp
(let ((result (cl-weave:benchmark (:samples 20) (compute-report))))
  (list :fastest (cl-weave:minimum-ms result)
        :median  (cl-weave:median-ms result)
        :mean    (cl-weave:mean-ms result)
        :slowest (cl-weave:maximum-ms result)))
```

## When (not) to gate on timings

Wall-clock timings vary with machine load, so treating them as CI pass/fail
gates makes suites flaky. Use benchmarks to investigate and compare
implementations interactively, and keep hard limits deterministic:

- a per-test budget with `:timeout-ms`, or
- an assertion with `(expect thunk :to-run-under-ms 5)` when you truly need a
  ceiling in the suite.
