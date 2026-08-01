# Maintenance Policy

`cl-weave` is stable (`1.x`) and evolves under [Semantic Versioning](versioning-policy.md)
with an emphasis on deterministic output, coherent public APIs, and explicit
upgrade notes.

For the release labeling and public-surface discipline, see
[versioning-policy.md](versioning-policy.md).

## Supported Surface

- The current development line is the primary support target.
- Security issues, correctness bugs, and documentation mismatches are handled
  against the current mainline behavior first.
- If versioned release branches are introduced later, the newest supported
  branch becomes the backport target for fixes.

## Release Expectations

- Release notes should summarize user-visible changes and any migration steps
  that matter for downstream ASDF systems.
- Breaking changes should be called out explicitly in GitHub Release notes
  and, when practical, accompanied by regression tests.
- Public reporter formats, CLI flags, and adoption guidance should stay in sync
  with the behavior exercised by the test suite.
- Breaking changes to the public surface ship only in a new major version, are
  called out clearly in the release notes and versioning policy, and carry a
  migration note at the point of change.

## Support Channels

- Use issues or private security reporting for problems that need maintainer
  attention.
- Use pull requests for fixes that can be validated locally and covered by
  regression tests.
- Use [docs/src/project/community-health.md](community-health.md) for workflow details, validation
  commands, and coding standards.
- Use [release-process.md](release-process.md) when a patch changes release
  notes, metadata, or other shipped contracts.
- Use [support-policy.md](support-policy.md) for the canonical support
  boundaries and report expectations.
