# Installation

!!! info "Prerequisites"

    `cl-weave` is distributed as a [Nix flake](https://nixos.org/). You need
    [Nix](https://nixos.org/download/) with flakes enabled
    (`experimental-features = nix-command flakes`). The runtime targets SBCL on
    Linux first — see [Runtime Support](runtime-support.md) for the full matrix.

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
documented in [Runtime Support](runtime-support.md). A platform is
release-ready only when the ASDF load gate and the relevant CI entrypoints
pass there.

### Capability Matrix

Runtime metadata exposes `capabilityMatrix` so humans and agents can evaluate
framework readiness without guessing from examples. Every advertised
capability has a corresponding readiness entry; highlighted areas include
`vitest-dsl`, `expect-matchers`, `fixtures-and-restarts`, `mocks-and-spies`,
`property-and-mutation`, `structured-reporting`, `watch-and-parallelism`,
`isolation-and-cps`, and `ai-discovery-metadata`.
