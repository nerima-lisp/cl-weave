# Issue Reporting Guide

Use this guide when filing bugs, regressions, or behavior questions that need
maintainer attention.

For the current boundaries between issues, pull requests, and private security
reports, see [support-policy.md](support-policy.md).

## What To Include

Please include:

1. The exact command you ran.
2. The `cl-weave` version or commit if you are testing a local checkout.
3. The Common Lisp implementation and version.
4. Your operating system and shell if the issue touches the CLI.
5. The expected result and the actual result.
6. The smallest reproducer you can provide.
7. Any machine-readable metadata or reporter output that shows the failure.

For CLI or metadata issues, capture the command output directly when possible:

```sh
timeout 120s nix run . -- metadata cl-weave/tests --output cl-weave-metadata.json
```

## Report Template

Use this structure if you want a minimal report that is easy to triage:

- Summary:
- Environment:
  - cl-weave version or commit:
  - Common Lisp implementation and version:
  - Operating system and architecture:
  - Shell or terminal, if relevant:
- Command:

```sh
<exact command>
```

- Expected:
- Actual:
- Reproducer:

```lisp
<smallest failing case or fixture>
```

- Extra output:
  - metadata:
  - reporter output:
  - logs:

## Good Bug Reports

A good report should let a maintainer reproduce the issue without guessing.
Prefer a single failing command, a minimal test case, or a tiny fixture over a
large project archive.

If the issue only appears in one reporter, one matcher, or one isolation mode,
say so explicitly. That helps narrow the problem to the right layer quickly.

## Security-Sensitive Reports

If the problem involves unintended shell execution, path traversal, unsafe
snapshot writes, or subprocess isolation escapes, report it through the security
process instead of opening a public issue.

Use [private GitHub security advisories](https://github.com/nerima-lisp/cl-weave/security/advisories/new) for the current reporting policy.
