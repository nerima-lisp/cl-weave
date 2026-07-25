# Quick Start

```lisp
(defpackage #:example/tests
  (:use #:cl)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave #:expect #:it))

(in-package #:example/tests)

(describe "math"
  (it "adds numbers"
    (expect (+ 1 1) :to-be 2))

  (it "checks predicates as data"
    (expect (= (+ 1 1) 2)))

  (it "compares structures"
    (expect (list :ok 42) :to-equal (list :ok 42))))
```

Run the self-test suite:

```sh
timeout 360s nix run . -- run cl-weave/tests
```

## Common CLI Invocations

```sh
timeout 360s nix run . -- run cl-weave/tests --reporter json --output cl-weave-results.json --retry 2 --test-timeout-ms 10000
timeout 360s nix run . -- run cl-weave/tests --reporter jsonl --output cl-weave-events.jsonl
timeout 360s nix run . -- run my-project-tests --update-snapshots --snapshot-dir tests/__snapshots__/ --snapshot-file snapshots.sexp
timeout 120s nix run . -- list cl-weave/tests --reporter json --filter 'math > adds'
timeout 120s nix run . -- metadata cl-weave/tests --output cl-weave-metadata.json
timeout 120s nix run . -- doctor --reporter json --output cl-weave-doctor.json
timeout 360s nix run . -- run cl-weave/tests --bail=1 --sequence random --seed 12345
timeout 360s nix run . -- run cl-weave/tests --journal --random-seed 12345 --reporter json --output cl-weave-results.json
timeout 360s nix run . -- watch cl-weave/tests --filter parser
timeout 120s nix run . -- watch cl-weave/tests --once --reporter json --filter 'math > adds' --output cl-weave-watch-once.json
```

Lisp-side agents can read the full structured framework metadata with
`(cl-weave:framework-metadata)` and the artifact-only contract with
`(cl-weave:reporter-artifact-schemas)` without shelling out to the CLI.

See the [Adoption Guide](adoption.md) for integrating `cl-weave` into an
existing ASDF project, and [AI Discovery](ai-discovery.md) for how agents and
generators should consume runtime metadata instead of scraping prose.
