# Governance

`cl-weave` is maintained as a small, review-driven project. This document makes
the maintainer operating model explicit so contributors and agents can tell how
decisions, reviews, and release authority work.

## Maintainer Role

Maintainers are responsible for:

- triaging issues and pull requests against [project-scope.md](project-scope.md)
  and [support-policy.md](support-policy.md)
- protecting documented public-surface expectations in
  [versioning-policy.md](versioning-policy.md)
- keeping machine-readable metadata, release notes, and policy documents in sync
- requiring regression coverage for public-surface changes when practical
- enforcing security handling through [private GitHub security advisories](https://github.com/nerima-lisp/cl-weave/security/advisories/new)

Repository-wide review ownership is declared in
[../.github/CODEOWNERS](../../.github/CODEOWNERS). CODEOWNERS routing is the
default review path, but maintainers may ask for additional review when a
change affects public contracts, release process, or downstream adoption.

## Decision Model

- Scope decisions follow [project-scope.md](project-scope.md).
- Support and escalation decisions follow [support-policy.md](support-policy.md)
  and [triage-policy.md](triage-policy.md).
- Public-surface-sensitive decisions follow
  [versioning-policy.md](versioning-policy.md).
- Release readiness decisions follow [release-process.md](release-process.md).

When a change touches multiple policies, maintainers should choose the narrowest
decision that preserves documented public-surface expectations and keeps
metadata contracts accurate.

## Review And Merge Expectations

- Submissions should arrive through the canonical issue and pull request paths.
- Pull requests should explain user-visible impact, public-surface risk, and the
  validating commands that were run.
- Maintainers should avoid merging changes that alter public CLI behavior,
  reporter shapes, metadata fields, or exported symbols without matching tests
  and documentation updates.
- Security-sensitive changes should stay on the private reporting path until the
  maintainer handling the issue decides disclosure is safe.

## Release Authority

Maintainers cut releases from the validated default branch state only. Before a
release, the maintainer responsible for the cut should verify the checklist in
[release-process.md](release-process.md), especially the parts that keep
machine-readable metadata and human-facing documentation synchronized.

## Maintainer Continuity

If the active maintainer set changes, update this document, the linked policy
documents, and the machine-readable metadata in the same patch. Repository
operations should remain understandable from published docs instead of relying
on unwritten maintainer knowledge.
