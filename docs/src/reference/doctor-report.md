# doctor-report

`cl-weave doctor` is the machine-readable self-diagnostic entrypoint for CI, agents, and local triage.

## Purpose

Use `doctor` when you need to answer two different questions without conflating them:

- Is the bundled `cl-weave` runtime itself visible and healthy?
- Is the specific target system you want to operate on resolvable in the current workspace?

The command is intentionally useful even when no positional ASDF system argument is supplied. That mode reports runtime-only diagnostics and should not be treated as a missing-project failure.

## Recommended invocations

Emit JSON to standard output:

```sh
cl-weave doctor --reporter json
```

Persist a diagnostic artifact for CI:

```sh
cl-weave doctor my-test-system --reporter json --output doctor-report.json
```

Emit Lisp-native data:

```sh
cl-weave doctor --reporter sexp
```

## Artifact shape

`doctor --reporter json` emits a `doctor-report` object with these top-level fields:

- `schemaVersion`
- `kind`
- `status`
- `version`
- `runtime`
- `checks`

`kind` is always `doctor-report`.

`status` is the aggregate status across all checks. Individual checks remain the primary signal for triage because one failing target-system check does not mean the bundled runtime itself is unavailable.

## Runtime metadata

`runtime` describes the active Common Lisp process. It is intended to help distinguish workspace issues from implementation or environment drift.

Representative fields include:

- implementation type and version
- machine instance and machine type
- software type and software version
- current working directory

## Checks

Each `checks` entry contains:

- `name`
- `status`
- `summary`

Current check names, in emission order:

### `runtime`

Reports the resolved Lisp implementation, version, and host software type for the current process.

Interpretation:

- `pass`: always `pass`; this check is a fixed informational summary, not a pass/fail diagnostic

This check is a quick human-readable complement to the structured `runtime` object described above; use the top-level `runtime` object for machine parsing.

### `cl-weave-system`

Reports whether the bundled `cl-weave` ASDF system is visible in the current runtime.

Interpretation:

- `pass`: the runtime can resolve `cl-weave`
- `fail`: the runtime cannot resolve the bundled system, which usually indicates a broken invocation environment

### `requested-system`

Reports whether the optional positional ASDF system argument resolves.

Interpretation:

- `pass` with a runtime-only summary: no positional system was requested; this is expected for pure self-diagnostics
- `pass`: the requested system resolves
- `fail`: the requested system does not resolve

This check is intentionally separated from `cl-weave-system` so automation can tell the difference between:

- a broken `cl-weave` runtime
- a healthy runtime pointed at a missing or misnamed target system

### `workspace-asd-files`

Reports whether the current workspace appears to contain `.asd` files.

Interpretation:

- `pass`: at least one `.asd` file was discovered
- `warn`: no `.asd` files were discovered from the current working directory

This is a discovery hint, not a substitute for `requested-system`.

### `output-target`

Reports where the artifact is being written.

Interpretation:

- `pass`: output is directed to standard output
- `pass`: output is directed to the path given by `--output`

This check is useful for CI auditing because it makes output routing explicit in the artifact itself.

### `command-metadata`

Reports whether framework metadata advertises the `doctor` command.

Interpretation:

- `pass`: runtime metadata and command discovery remain aligned
- `fail`: metadata drift exists and AI/CI discovery should be considered untrustworthy until fixed

## Triage guidance

When `requested-system` fails but `cl-weave-system` passes, the problem is usually one of:

- wrong system name
- missing dependency checkout
- wrong working directory
- ASDF source-registry configuration drift

When `cl-weave-system` fails, debug the invocation environment first. Investigating the target workspace before restoring the bundled runtime usually wastes time.

When `workspace-asd-files` warns but `requested-system` passes, treat the warning as informational. The target system may still be resolvable through ASDF registry configuration outside the current directory tree.

## CI usage

For CI and agent runs, prefer emitting `doctor-report` before deeper operations when environment drift is plausible. A minimal sequence is:

1. Run `cl-weave doctor --reporter json --output doctor-report.json`
2. Inspect `checks`
3. Only proceed to `metadata`, `list`, or `run` once the runtime and target-resolution signals are understood

This keeps environment failures, discovery failures, and test failures separated into different artifacts.
