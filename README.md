# cl-weave

[![CI](https://github.com/nerima-lisp/cl-weave/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-weave/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-weave/)

`cl-weave` is a modern Common Lisp testing framework inspired by Vitest and
designed around Lisp's strengths: macros, conditions, dynamic bindings, and
reproducible Nix workflows. It is intentionally dependency-free at the core,
and easy to run in CI, embed in ASDF projects, and extend from the REPL. It is
the test framework used by every package in the nerima-lisp org.

Full documentation, including the DSL guide, matcher reference, and AI
discovery contract, is published at <https://nerima-lisp.github.io/cl-weave/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

```lisp
(defpackage #:example/test
  (:use #:cl)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave #:expect #:it))

(in-package #:example/test)

(describe "math"
  (it "adds numbers"
    (expect (+ 1 1) :to-be 2))

  (it "compares structures"
    (expect (list :ok 42) :to-equal (list :ok 42))))
```

```sh
nix run . -- run cl-weave/test
```

See [Quick Start](https://nerima-lisp.github.io/cl-weave/quick-start/) for
more CLI examples and [Installation](https://nerima-lisp.github.io/cl-weave/installation/)
for every install path.

## Install

```sh
nix run github:nerima-lisp/cl-weave -- --help    # run without installing
nix profile install github:nerima-lisp/cl-weave  # install via Nix
nix develop -c nix profile install .           # from a local checkout
```

As a flake input, pin a release tag rather than following the default branch:

```nix
# flake.nix
inputs.cl-weave = {
  url = "github:nerima-lisp/cl-weave/v1.0.1";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

## Documentation

- [Installation](https://nerima-lisp.github.io/cl-weave/installation/)
- [Quick Start](https://nerima-lisp.github.io/cl-weave/quick-start/)
- [DSL Guide](https://nerima-lisp.github.io/cl-weave/dsl-guide/)
- [API Reference](https://nerima-lisp.github.io/cl-weave/api-reference/)

## Development

```sh
nix develop          # SBCL, coreutils, jq, libxml2, paredit-cli
nix run .#test       # the self-test suite
nix flake check      # tests + formatting + docs, the same gate CI uses
nix build .#docs     # the documentation site, with mkdocs --strict
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` under the `cl-weave/test` system, and `run-tests.lisp` at the
repository root is the Lisp-level entry point. See
[Development](https://nerima-lisp.github.io/cl-weave/development/) for the full
workflow.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide, the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md),
and this project's
[Development](https://nerima-lisp.github.io/cl-weave/development/) page.

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md) and
this project's [Support Policy](https://nerima-lisp.github.io/cl-weave/support-policy/)
for the canonical support boundaries.

Report vulnerabilities through
[private GitHub security advisories](https://github.com/nerima-lisp/cl-weave/security/advisories/new).
Do not put exploit details in a public issue.

Community conduct is defined by the org-wide
[Code of Conduct](https://github.com/nerima-lisp/.github/blob/main/CODE_OF_CONDUCT.md),
and release history is in [CHANGELOG.md](CHANGELOG.md) and
[GitHub Releases](https://github.com/nerima-lisp/cl-weave/releases).

## License

MIT. See [LICENSE](LICENSE).
