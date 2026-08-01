# Support Policy

`cl-weave` is maintained as a small open source library with a narrow support
surface. The goal is to keep expectations explicit so users know where to ask
for help and what kind of response to expect.

## Where To Ask

- Use the issue tracker for reproducible bugs, documentation gaps, and concrete
  feature requests.
- Use pull requests for fixes that you can describe and validate locally.
- Use private security reporting for anything that could expose sensitive data,
  unintended code execution, or filesystem safety issues.

## What To Include

Good reports are specific enough to reproduce:

- exact command or API entrypoint
- version or commit
- implementation and runtime details
- operating system and shell, when relevant
- expected behavior
- actual behavior
- smallest reproduction you can provide

If the problem depends on a particular reporter, artifact format, or isolation
mode, say so explicitly.

## What This Project Does Not Promise

- instant response times
- support for undocumented internal APIs
- compatibility for behaviors that are not covered by the
  [release-process.md](release-process.md) and
  [versioning-policy.md](versioning-policy.md) contracts
- downstream application support outside the `cl-weave` test framework itself

## Practical Guidance

- Check [docs/src/project/pull-request-template.md](pull-request-template.md) before opening a pull request so
  the local validation workflow matches maintainer expectations.
- Check [docs/src/project/project-scope.md](project-scope.md) before filing a feature
  request.
- Check [docs/src/project/triage-policy.md](triage-policy.md) before opening a bug report
  or pull request.
- Check [docs/src/project/maintenance-policy.md](maintenance-policy.md) for support
  boundaries and release expectations.
- Check [docs/src/reference/runtime-support.md](../reference/runtime-support.md) for implementation and
  platform coverage.
