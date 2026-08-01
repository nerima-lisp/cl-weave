# Project Scope

`cl-weave` is a Common Lisp test framework that aims to provide a small,
deterministic, AI-readable surface for test definition, execution, reporting,
and migration from adjacent ecosystems.

## In Scope

- Core `describe` / `it` style test definition.
- Assertions and matchers that keep failure output readable.
- Deterministic reporters and structured machine-readable output.
- Snapshot, property, mutation, and isolation helpers that fit the existing
  runner model.
- Explicit migration documentation for replaced APIs, without runtime aliases
  or wrappers.
- Machine-readable metadata that lets tooling discover supported commands,
  reporter schemas, and project links without scraping prose.

## Out Of Scope

- A general-purpose application framework.
- A broad plugin ecosystem before the core contract is stable.
- Implicit behavior that cannot be validated through the published test suite or
  contract files.
- Features that introduce nondeterminism without a compelling test framework
  benefit.

## Design Principles

- Prefer explicit contracts over hidden conventions.
- Prefer small public surfaces over clever abstractions.
- Prefer stable output shapes over ad hoc formatting.
- Prefer migration guides over silent breaks.

## When To Open An Issue

Open an issue when a change would affect:

1. public CLI behavior,
2. reporter output,
3. metadata or schema fields,
4. migration guidance for replaced APIs,
5. adoption or migration guidance, or
6. documented support and release policy.

If the change is security-sensitive, use [private GitHub security advisories](https://github.com/nerima-lisp/cl-weave/security/advisories/new) instead.
