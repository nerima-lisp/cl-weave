# Distribution Policy

`cl-weave` publishes a small set of canonical distribution channels. This
document defines what each channel is for, how maintainers verify it, and which
integrity guarantees are intentionally out of scope.

## Canonical Channels

The machine-readable source of truth is `distributionChannels` in
`cl-weave metadata`. Human-facing documentation should describe the same three
channels:

- `source-self-test`: run `nix run . -- run cl-weave/test` from a source
  checkout to validate the bundled ASDF test suite.
- `nix-local-cli`: install with `nix profile install .` from the current
  checkout root, then run `nix run . -- --help` to validate the packaged CLI.
- `nix-remote-cli`: run `nix profile install github:nerima-lisp/cl-weave` and
  `nix run github:nerima-lisp/cl-weave -- --help` to validate the packaged CLI
  fetched from the repository reference.

## Verification Expectations

- Keep `README.md`, `docs/src/ai-contract.md`, and metadata `distributionChannels`
  synchronized when install or run commands change.
- For a release or production deployment, consume an immutable Git revision
  rather than an unqualified branch reference. Record that revision alongside
  the command that was run.
- Inspect `flake.lock` changes as dependency updates. A lock-file update changes
  the dependency graph even when the Common Lisp sources are unchanged.
- Verify a pinned revision with `nix flake check
  github:nerima-lisp/cl-weave/<revision> --print-build-logs`, then build the same
  reference with `nix build github:nerima-lisp/cl-weave/<revision> --no-link`.
  This verifies the checks and package from the exact source reference that a
  consumer will use.
- Run the source checkout path before release so the repository still passes its
  bundled self-test suite.
- Run the local Nix packaging path before release so the packaged CLI still
  starts with the documented entrypoint.
- Run the remote Nix packaging path when validating release-facing install
  guidance or repository reference changes.
- Treat `nix flake check --print-build-logs` as the packaging regression gate
  when Nix is available.
- Do not describe a channel as release-ready while ASDF loading, source
  self-tests, or documented CLI entrypoints time out. Record the failing gate in
  `README.md` or `docs/src/runtime-support.md` before publishing adoption guidance.

## Integrity And Scope

- `cl-weave` does not currently publish separate signed tarballs, detached
  signatures, SBOMs, or provenance attestations outside the source repository
  and Nix build graph.
- The canonical integrity boundary is an immutable repository revision together
  with its version-controlled source tree, `flake.lock`, and reproducible Nix
  packaging path defined in `flake.nix`.
- Nix evaluation and build success demonstrate reproducibility within the
  declared flake inputs; they are not a substitute for artifact signing,
  vulnerability review, or an externally issued provenance attestation.
- If maintainers add another public distribution channel later, update this
  document, the metadata contract, and release-process checks in the same patch.
