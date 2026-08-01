# Pull Request Template

Use this guide for the full pull request checklist. The rendered GitHub
template at `.github/pull_request_template.md` presents the core prompts and
links reviewers here for the supporting context.

## Summary

What changed and why:

## Validation

List the commands you ran:

- `timeout 360s nix run . -- run cl-weave/test`
- `timeout 600s nix flake check --print-build-logs`
- any narrower command that directly exercises the change

## Public Surface Impact

State whether this is additive, behavior-preserving, or intentionally
breaking for the public surface:

## Follow-up Risk

Call out any remaining risk, unsupported edge case, or intentional follow-up:

## Related Issue Or Policy

Link the relevant issue, policy, or contract document:

## Notes For Reviewers

Identify review focus, rollout considerations, or questions that need an
explicit maintainer decision:
