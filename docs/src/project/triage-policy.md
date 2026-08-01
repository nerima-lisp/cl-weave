# Triage Policy

This document describes how issues and pull requests should be prioritized for
`cl-weave`.

## Issue Priority

- Highest priority: security problems, data loss, unsafe filesystem behavior,
  subprocess isolation escapes, and test framework regressions that block
  existing workflows.
- Medium priority: correctness bugs, compatibility regressions, and contract
  drift between implementation and documentation.
- Lower priority: documentation improvements, migration polish, and additive
  enhancements that do not affect current users directly.

## Issue Quality

Good issues should include:

1. the exact command or workflow,
2. the observed behavior,
3. the expected behavior,
4. the smallest reproducer available,
5. environment details that matter to the failure.

## Pull Request Expectations

- Keep PRs narrowly scoped when possible.
- Include tests for any behavior change that can be exercised locally.
- Call out compatibility impact explicitly when changing a public surface.
- Link to the relevant issue, policy, or contract document when the change is
  driven by one.

## Maintainer Response

Maintainers should use the policy and contract docs to decide whether a report
belongs in a bug fix, a documentation change, or a deliberate compatibility
discussion.
