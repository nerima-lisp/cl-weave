# AI Discovery

Agents and generators should start from runtime metadata instead of scraping
source files or examples:

```sh
timeout 120s nix run . -- metadata cl-weave/test --reporter json --output cl-weave-metadata.json
```

The metadata payload advertises CLI commands, typed options, finite choices,
command-specific choices, environment variables, CI quality gates, public
package exports, matchers, mutation operators,
`mop-architecture-assertions`, `capabilityMatrix`, `artifactSchemas`, and
`distributionChannels`.
For runtime self-diagnostics, `doctor --reporter json` emits a structured
`doctor-report` artifact without requiring an ASDF system argument.
The report separates bundled `cl-weave` visibility, optional requested-system
resolution, workspace `.asd` discovery, and output-target configuration so CI
and agents can distinguish environment drift from an actually missing target
system.

`artifactSchemas` is the contract for structured artifacts
such as JSON run results, JSONL run events, JSON test plans, JSONL plan entries,
doctor reports, and mutation reports. Each entry declares the artifact kind, producing
commands, supported reporters, artifact-local `schemaVersion`, streaming mode,
and field map, so agents can plan parsers and CI integrations without
hard-coding reporter internals. Result artifacts intentionally advertise both
`run` and `watch`, because `watch --once` emits the same machine-readable shape
as a normal run. `qualityGates` exposes validation commands as argv vectors
with explicit timeouts and expected artifacts, so agents can reproduce CI
without scraping prose.

`distributionChannels` is the canonical install and run table for source
checkout execution, local Nix packaging, and remote Nix packaging. Agents
should prefer its `installCommand` and `runCommand` vectors over inferring
entrypoints from surrounding prose examples. The maintainer-facing verification
and scope boundary for those channels lives in
[Distribution Policy](../project/distribution-policy.md).

`capabilityMatrix` is the readiness table: each entry links a high-level
feature to implemented status, representative public APIs, validation gates,
and canonical documentation. The complete artifact and capability lists are
intentionally discovered from the command output; documentation examples are
illustrative.

See [AI Contract](../reference/ai-contract.md) for the full machine-readable normalization
contract, and [Doctor Report](../reference/doctor-report.md) for the self-diagnostic
artifact shape.
