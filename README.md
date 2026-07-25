# cl-weave

[![CI](https://github.com/takeokunn/cl-weave/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/takeokunn/cl-weave/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://takeokunn.github.io/cl-weave/)

`cl-weave` is a modern Common Lisp testing framework inspired by Vitest and
designed around Lisp's strengths: macros, conditions, dynamic bindings, and
reproducible Nix workflows. It is intentionally dependency-free at the core,
and easy to run in CI, embed in ASDF projects, and extend from the REPL.

Full documentation, including the DSL guide, matcher reference, AI discovery
contract, and every governance and policy document, is published at
<https://takeokunn.github.io/cl-weave/>. The source for that site lives in
[docs/src/](docs/src/README.md).

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

  (it "compares structures"
    (expect (list :ok 42) :to-equal (list :ok 42))))
```

```sh
nix run . -- run cl-weave/tests
```

See [Quick Start](https://takeokunn.github.io/cl-weave/quick-start/) for
more CLI examples and [Installation](https://takeokunn.github.io/cl-weave/installation/)
for every install path.

## Install

```sh
nix run github:takeokunn/cl-weave -- --help    # run without installing
nix profile install github:takeokunn/cl-weave  # install via Nix
nix develop -c nix profile install .           # from a local checkout
```

## Development

```sh
nix develop
nix flake check
nix build .#docs
```

Pull requests run `nix flake check`.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md) for the supported Nix workflow,
validation expectations, and public-surface rules. Project governance,
maintenance, and release policies are available in the
[documentation](https://takeokunn.github.io/cl-weave/).

## Support

Use the [Support Policy](https://takeokunn.github.io/cl-weave/support-policy/)
for the canonical support boundaries, and
[private GitHub security advisories](https://github.com/takeokunn/cl-weave/security/advisories/new)
for vulnerability reporting. Do not put exploit details in a public issue.

Community conduct is defined in [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and
release history is published through [GitHub Releases](https://github.com/takeokunn/cl-weave/releases).

## License

MIT. See [LICENSE](LICENSE).
