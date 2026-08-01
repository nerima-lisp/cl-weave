# Getting Started

!!! info "Prerequisites"

    `cl-weave` is distributed as a [Nix flake](https://nixos.org/). You need
    [Nix](https://nixos.org/download/) with flakes enabled
    (`experimental-features = nix-command flakes`). The runtime targets SBCL on
    Linux first — see [Runtime Support](reference/runtime-support.md) for the full matrix.

Pick the path that matches how you want to use the framework.

=== "Run without installing"

    Fastest way to try the CLI — Nix fetches and runs it in one step, nothing
    is added to your profile:

    ```sh
    nix run github:nerima-lisp/cl-weave -- --help
    ```

    Ideal for CI and AI agents that only need a single invocation.

=== "Install into your profile"

    Add the `cl-weave` CLI to your Nix profile so it is on `PATH`:

    ```sh
    nix profile install github:nerima-lisp/cl-weave
    ```

=== "Local checkout (contributors)"

    Clone the repository, then work inside the reproducible dev shell:

    ```sh
    nix develop                                  # SBCL + tooling devShell
    nix run . -- --help                          # run the packaged CLI
    nix profile install .                         # install from the checkout
    timeout 600s nix flake check                  # every CI entrypoint
    timeout 360s nix run . -- run cl-weave/test --reporter spec
    ```

    `timeout` is an optional outer guard for CI and automation; it is not
    required by `cl-weave`. On systems that do not provide it, run the `nix`
    command without the prefix, or provide GNU coreutils through your
    environment.

The packaged CLI is intended for local use, CI, and AI agents.

## Supported Runtime

`cl-weave` targets SBCL first. Linux is the supported platform, and
SBCL-specific features such as subprocess isolation and coverage handling are
documented in [Runtime Support](reference/runtime-support.md). A platform is
release-ready only when the ASDF load gate and the relevant CI entrypoints
pass there.

### Capability Matrix

Runtime metadata exposes `capabilityMatrix` so humans and agents can evaluate
framework readiness without guessing from examples. Every advertised
capability has a corresponding readiness entry; highlighted areas include
`vitest-dsl`, `expect-matchers`, `fixtures-and-restarts`, `mocks-and-spies`,
`property-and-mutation`, `structured-reporting`, `watch-and-parallelism`,
`isolation-and-cps`, and `ai-discovery-metadata`.

## Quick Start

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
timeout 360s nix run . -- run cl-weave/test
```

### Common CLI Invocations

```sh
timeout 360s nix run . -- run cl-weave/test --reporter json --output cl-weave-results.json --retry 2 --test-timeout-ms 10000
timeout 360s nix run . -- run cl-weave/test --reporter jsonl --output cl-weave-events.jsonl
timeout 360s nix run . -- run my-project-tests --update-snapshots --snapshot-dir tests/__snapshots__/ --snapshot-file snapshots.sexp
timeout 120s nix run . -- list cl-weave/test --reporter json --filter 'math > adds'
timeout 120s nix run . -- metadata cl-weave/test --output cl-weave-metadata.json
timeout 120s nix run . -- doctor --reporter json --output cl-weave-doctor.json
timeout 360s nix run . -- run cl-weave/test --bail=1 --sequence random --seed 12345
timeout 360s nix run . -- run cl-weave/test --journal --random-seed 12345 --reporter json --output cl-weave-results.json
timeout 360s nix run . -- watch cl-weave/test --filter parser
timeout 120s nix run . -- watch cl-weave/test --once --reporter json --filter 'math > adds' --output cl-weave-watch-once.json
```

Lisp-side agents can read the full structured framework metadata with
`(cl-weave:framework-metadata)` and the artifact-only contract with
`(cl-weave:reporter-artifact-schemas)` without shelling out to the CLI.

See the [Adoption Guide](guide/adoption.md) for integrating `cl-weave` into an
existing ASDF project, and [AI Discovery](guide/ai-discovery.md) for how agents and
generators should consume runtime metadata instead of scraping prose.
