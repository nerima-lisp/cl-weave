# Security Policy

## Supported Versions

Security fixes are applied to the current mainline release. Earlier releases
are not supported; upgrade to the latest release before reporting a behavior
that may already be fixed. See
[docs/src/maintenance-policy.md](docs/src/maintenance-policy.md) for the
supported-surface policy.

## Reporting a Vulnerability

Do not open a public issue for a suspected vulnerability. Report it through
[GitHub private security advisories](https://github.com/nerima-lisp/cl-weave/security/advisories/new).

Include a minimal reproduction, affected version or commit, impact, and any
suggested mitigation. Avoid publishing exploit details until a maintainer has
coordinated disclosure with affected users.

## Response and Disclosure

Maintainers aim to acknowledge a report within seven calendar days, validate
the issue, and coordinate a fix or mitigation with the reporter. Do not
publish vulnerability details before a coordinated disclosure date is agreed.

## Scope

Security-sensitive reports include unintended code execution, unsafe filesystem
behavior, isolation escapes, disclosure of sensitive data, and vulnerabilities
in the packaged CLI or documented release path.

The detailed security and support boundaries are maintained in
[docs/src/support-policy.md](docs/src/support-policy.md) and
[docs/src/triage-policy.md](docs/src/triage-policy.md).
