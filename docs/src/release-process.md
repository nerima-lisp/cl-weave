# Release Process

This document describes the release flow for `cl-weave`, which follows
[Semantic Versioning](versioning-policy.md). Stable releases began at `1.0.0`.

## Release Goals

- Keep the public CLI and reporter contracts stable unless the GitHub Release
  notes call out a deliberate break.
- Keep machine-readable metadata and human-facing documentation in sync.
- Keep downstream ASDF consumers able to adopt new versions with a small
  upgrade step.

For public-surface discipline and migration expectations, see
[versioning-policy.md](versioning-policy.md).

## Suggested Release Checklist

1. Bump the version string in lockstep across `cl-weave.asd` (`:version`) and
   the `"version"` field in the embedded JSON contract in
   `docs/src/ai-contract.md`. (`flake.nix` derives its package version from the
   `.asd` `:version`, so it needs no manual edit.) Choose the major/minor/patch
   increment per the [versioning policy](versioning-policy.md).
2. Run the full test suite.
3. Run `nix flake check --print-build-logs` when Nix is available.
4. Summarize user-visible changes in the release notes.
5. Check that `README.md` and `docs/src/maintenance-policy.md` still match the
   current workflow.
6. Review `docs/src/pull-request-template.md` and
   `.github/pull_request_template.md` so release-bound changes still capture
   public-surface notes, validation commands, and follow-up risk in a
   consistent format.
7. Verify that `cl-weave metadata` still advertises the expected package links,
   reporter list, and schema versions.
8. Verify that `docs/src/distribution-policy.md` still matches the documented
   source and Nix install paths.
9. Confirm the release notes mention any intentional public-surface breaks or
   migration steps.
10. Merge the reviewed release pull request to the default branch. Discover its
    name with `DEFAULT=$(gh repo view --json defaultBranchRef --jq
    .defaultBranchRef.name)` and fetch it with `git fetch origin "$DEFAULT"`.
11. Create an annotated tag from the merged commit and push it: `git tag -a
    vX.Y.Z "origin/$DEFAULT" -m "Release vX.Y.Z"` followed by `git push origin
    vX.Y.Z`. The release workflow rejects tags that are not stable `vX.Y.Z`
    versions, do not match `cl-weave.asd`, or are not reachable from the
    repository default branch.
12. Verify the workflow completed successfully and that the matching GitHub
    Release exists with the generated test-report archive attached. The
    workflow creates the release as an empty **draft**: it writes no body at
    all. Paste in the notes from step 4 and publish with `gh release edit
    vX.Y.Z --notes-file <file> --draft=false`.

The GitHub Release description is the canonical public release history, and
since the 2026-08-01 org revision it is the only one — this repository has no
`CHANGELOG.md`. A draft appears neither under "Latest release" nor in the
default output of `gh release list`, so a release whose notes were forgotten
never reaches downstream.

## Maintenance Boundaries

- Security fixes and correctness fixes target the current mainline behavior
  first.
- If release branches are introduced later, backports should follow the current
  maintenance policy.
- Keep `distributionChannels`, `README.md`, and
  `docs/src/distribution-policy.md` synchronized when install paths change.
- Update tests and `docs/src/ai-contract.md` when a machine-readable contract
  changes.
