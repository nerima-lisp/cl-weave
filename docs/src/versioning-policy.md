# Versioning Policy

As of `1.0.0`, `cl-weave` is **stable** and follows
[Semantic Versioning 2.0.0](https://semver.org/). Version numbers communicate
compatibility, not just change scope.

## Current Model

- **MAJOR** (`x.0.0`) — an intentionally breaking, documented change to the
  public surface. Breaking changes ship only in a new major version.
- **MINOR** (`1.x.0`) — a backward-compatible, additive change to the public
  surface.
- **PATCH** (`1.0.x`) — a backward-compatible, behavior-preserving bug fix.

Within a major series, non-breaking changes preserve the documented CLI output,
reporter shape, reporter `schema-version`, and machine-readable metadata.

## Public Surface

The compatibility promise covers:

- exported symbols in the `cl-weave` package,
- the CLI: option names, semantics, and exit codes,
- reporter output shape, including the JSON/sexp reporter `schema-version`,
- the machine-readable metadata surface (`--metadata` and friends).

Reporter schema versions are the compatibility signal for consumers: a schema
version only changes when the payload shape changes, and such a change is a
breaking change under this policy.

## Public Surface Discipline

- Prefer one coherent public API over layered aliases and transition shims.
- Add new surface additively; reserve removals and renames for a major bump.
- When a public contract changes, update docs, metadata, and tests in the same
  change.

## Deprecation

- Deprecations are announced in release notes and docs before removal.
- A deprecated surface keeps working for the remainder of its major series.
- Removal happens only at the next major version, with a migration note at the
  point of removal.

## Release Notes

Each release makes it clear whether it is:

1. additive only (minor),
2. behavior-preserving (patch), or
3. intentionally breaking for a documented reason (major).

That label matches the actual change set and the regression tests that support
it. A breaking change is always explicit in GitHub Release notes,
docs, and tests.

Before cutting a release or documenting a public break, review
[release-process.md](release-process.md) and
[maintenance-policy.md](maintenance-policy.md) so GitHub Release notes,
validation, and support expectations stay aligned.
