# Runtime Support

`cl-weave` is developed primarily on SBCL. That is the runtime used by the
repository's test suite, coverage flow, subprocess isolation path, and CI
validation.

## Supported Platforms

- SBCL on Linux is the supported target for the current release
  line.
- Other Common Lisp implementations may work for the dependency-free core, but
  they are best-effort and can lag behind SBCL-specific behavior.

## Current Verification Gate

The supported SBCL target is release-ready only when ASDF loading succeeds.
The packaged CLI bootstraps the project through `asdf:load-asd` plus
`asdf:load-system`, matching this gate exactly.
Targeted source checks are useful for narrowing a defect, but they are not a
substitute for the release gate.

Required release gate:

```lisp
(asdf:load-system :cl-weave :force t)
```

The documented self-test and CLI commands should pass after that load gate is
green.

## SBCL-Dependent Features

The following features rely on SBCL-specific facilities or repository
integration around SBCL:

- `it-isolated` subprocess execution
- coverage capture and reset/save integration
- allocation assertions in CI-focused tests
- some MOP-dependent metadata and structural assertions

When a feature depends on implementation-specific behavior, the documentation
and tests should say so explicitly.

## Reporting Runtime Issues

Include these details when reporting a runtime problem:

- implementation and version
- operating system and architecture
- exact command or API entrypoint
- whether the failure appears on SBCL or only on another implementation

If you want portability work beyond SBCL, open a feature request and include
the target implementation, the behavior you need, and a reproduction case.
