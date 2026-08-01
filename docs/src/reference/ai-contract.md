# cl-weave AI Contract

`cl-weave` exposes structured test output as S-expressions and JSON so agents
can parse results without scraping human text.

## CLI Metadata Contract

Agents should use `cl-weave metadata [SYSTEM]` as the discovery entrypoint
before generating tests or interpreting project-specific matcher failures. The
command loads the requested ASDF system and then emits JSON by default:

```sh
timeout 120s nix run . -- metadata cl-weave/test --output cl-weave-metadata.json
```

Agents embedded in a Lisp process can call `(cl-weave:framework-metadata)` to
read the same root metadata and `(cl-weave:reporter-artifact-schemas)` to read
the artifact schema contracts without invoking the CLI.

The `mutations` artifact schema is also exposed there. Its JSON fields are
`schemaVersion`, `kind`, `total`, `killed`, `survived`, `errored`, `score`,
and `results`. Registered mutation operators are advertised separately through
`list-mutation-operators` and `mutation-operator-metadata`.

The JSON root is stable. The example below is abridged: agents should treat the
runtime `artifactSchemas` value as authoritative because it includes every
structured artifact kind currently advertised by the loaded version. Beyond
runtime commands and reporters, the same root metadata also exposes
`distributionChannels`, `supportChannels`, `communityHealth`,
`securityContacts`, `lifecycle`, `governance`, `runtimeSupport`,
`releaseProcess`, `continuousIntegration`, and `policyDocuments` so agents
can route issues, pull requests, compatibility-sensitive changes, and
CI-aware automation through canonical maintainer surfaces.

Agents should treat `distributionChannels` as the canonical install and run
table. Each entry exposes `name`, `kind`, `installCommand`, `runCommand`,
`scope`, and `references`, so tooling should prefer it over scraping README
examples when deciding how to install or invoke `cl-weave`. The human-facing
verification and scope policy for those channels lives in
`docs/src/project/distribution-policy.md`.

```json
{
  "schemaVersion": 23,
  "kind": "cl-weave-metadata",
  "version": "1.1.0",
  "homepage": "https://github.com/nerima-lisp/cl-weave",
  "bugTracker": "https://github.com/nerima-lisp/cl-weave/issues",
  "license": "MIT",
  "policyDocuments": [
    "docs/src/project/community-health.md",
    "docs/src/project/distribution-policy.md",
    "docs/src/project/governance.md",
    "docs/src/project/issue-reporting.md",
    "docs/src/project/maintenance-policy.md",
    "docs/src/project/project-scope.md",
    "docs/src/project/pull-request-template.md",
    "docs/src/project/release-process.md",
    "docs/src/reference/runtime-support.md",
    "docs/src/project/support-policy.md",
    "docs/src/project/triage-policy.md",
    "docs/src/project/versioning-policy.md"
  ],
  "referenceDocuments": [
    {
      "name": "readme",
      "path": "README.md",
      "description": "Primary user-facing guide and CLI reference."
    },
    {
      "name": "ai-contract",
      "path": "docs/src/reference/ai-contract.md",
      "description": "Machine-readable contract and metadata normalization guide."
    },
    {
      "name": "adoption-guide",
      "path": "docs/src/guide/adoption.md",
      "description": "Native adoption guide and downstream integration plan."
    },
    {
      "name": "license",
      "path": "LICENSE",
      "description": "Canonical project license text."
    }
  ],
  "distributionChannels": [
    {
      "name": "source-self-test",
      "kind": "nix",
      "installCommand": [],
      "runCommand": ["nix", "run", ".", "--", "run", "cl-weave/test"],
      "scope": "Run the bundled ASDF test system through the packaged CLI.",
      "references": ["README.md", "docs/src/project/distribution-policy.md"]
    },
    {
      "name": "nix-local-cli",
      "kind": "nix",
      "installCommand": ["nix", "profile", "install", "."],
      "runCommand": ["nix", "run", ".", "--", "--help"],
      "scope": "Install and run the packaged CLI from the current checkout.",
      "references": ["README.md", "docs/src/project/distribution-policy.md"]
    },
    {
      "name": "nix-remote-cli",
      "kind": "nix",
      "installCommand": ["nix", "profile", "install", "github:nerima-lisp/cl-weave"],
      "runCommand": ["nix", "run", "github:nerima-lisp/cl-weave", "--", "--help"],
      "scope": "Install and run the packaged CLI without cloning the repository.",
      "references": ["README.md", "docs/src/project/distribution-policy.md"]
    }
  ],
  "supportChannels": [
    {
      "name": "issue-tracker",
      "kind": "github",
      "target": "https://github.com/nerima-lisp/cl-weave/issues",
      "scope": "Reproducible bugs, documentation gaps, and concrete feature requests."
    },
    {
      "name": "pull-requests",
      "kind": "github",
      "target": "https://github.com/nerima-lisp/cl-weave/pulls",
      "scope": "Validated fixes that are ready for review."
    },
    {
      "name": "support-policy",
      "kind": "document",
      "target": "docs/src/project/support-policy.md",
      "scope": "Canonical support boundaries, report contents, and escalation guidance."
    }
  ],
  "communityHealth": [
    {
      "name": "bug-report-form",
      "kind": "github-issue-template",
      "path": ".github/ISSUE_TEMPLATE/bug_report.md",
      "purpose": "Structured bug intake that routes reporters to the canonical issue reporting guide.",
      "references": [
        "docs/src/project/community-health.md",
        "docs/src/project/issue-reporting.md"
      ],
      "requiredSections": [
        "Summary",
        "Reproduction",
        "Expected Behavior",
        "Actual Behavior",
        "Validation",
        "Additional Context"
      ],
      "contactLinks": []
    },
    {
      "name": "feature-request-form",
      "kind": "github-issue-template",
      "path": ".github/ISSUE_TEMPLATE/feature_request.md",
      "purpose": "Structured feature intake that reinforces project scope and validation expectations.",
      "references": [
        "docs/src/project/community-health.md",
        "docs/src/project/project-scope.md",
        "docs/src/project/support-policy.md"
      ],
      "requiredSections": [
        "Problem",
        "Proposed Change",
        "Validation Plan",
        "Scope Check",
        "Public Surface Notes"
      ],
      "contactLinks": []
    },
    {
      "name": "issue-template-config",
      "kind": "github-issue-template-config",
      "path": ".github/ISSUE_TEMPLATE/config.yml",
      "purpose": "GitHub issue chooser configuration that redirects support and security traffic to canonical policies.",
      "references": [
        "docs/src/project/community-health.md",
        "docs/src/project/support-policy.md",
        "docs/src/project/issue-reporting.md"
      ],
      "requiredSections": [],
      "contactLinks": [
        {
          "name": "Support policy",
          "target": "https://github.com/nerima-lisp/cl-weave/blob/main/docs/src/project/support-policy.md",
          "purpose": "Check whether the request belongs in issue tracking and what detail is required."
        },
        {
          "name": "Security reporting",
          "target": "https://github.com/nerima-lisp/cl-weave/security/advisories/new",
          "purpose": "Report vulnerabilities through the private security contact path."
        },
        {
          "name": "Issue reporting guide",
          "target": "https://github.com/nerima-lisp/cl-weave/blob/main/docs/src/project/issue-reporting.md",
          "purpose": "Review the canonical reproduction format before filing a bug."
        }
      ]
    },
    {
      "name": "pull-request-template",
      "kind": "github-pull-request-template",
      "path": ".github/pull_request_template.md",
      "purpose": "Default PR body that mirrors the canonical review checklist and public-surface prompts.",
      "references": [
        "docs/src/project/community-health.md",
        "docs/src/project/pull-request-template.md"
      ],
      "requiredSections": [
        "Summary",
        "Validation",
        "Public Surface Impact",
        "Follow-up Risk"
      ],
      "contactLinks": []
    },
    {
      "name": "codeowners",
      "kind": "github-codeowners",
      "path": ".github/CODEOWNERS",
      "purpose": "Review ownership declaration for repository-wide changes.",
      "references": [
        "docs/src/project/community-health.md",
        "docs/src/project/governance.md"
      ],
      "requiredSections": [],
      "contactLinks": []
    }
  ],
  "securityContacts": [
    {
      "name": "security-reporting",
      "kind": "github",
      "target": "https://github.com/nerima-lisp/cl-weave/security/advisories/new",
      "scope": "Private vulnerability reporting through GitHub security advisories."
    }
  ],
  "lifecycle": {
    "stage": "stable",
    "status": "active",
    "supportedLine": "main",
    "supportDocument": "docs/src/project/support-policy.md",
    "versioningDocument": "docs/src/project/versioning-policy.md"
  },
  "governance": {
    "policyDocument": "docs/src/project/governance.md",
    "reviewOwnership": ".github/CODEOWNERS",
    "maintainerResponsibilities": [
      "Triaging issues and pull requests against the documented project scope and support boundaries.",
      "Protecting documented public-surface expectations recorded in the versioning policy.",
      "Keeping machine-readable metadata, release notes, and policy documents synchronized.",
      "Requiring regression coverage for public-surface changes when practical.",
      "Handling security-sensitive reports through private GitHub security advisories."
    ],
    "decisionDocuments": [
      "docs/src/project/project-scope.md",
      "docs/src/project/support-policy.md",
      "docs/src/project/triage-policy.md",
      "docs/src/project/versioning-policy.md",
      "docs/src/project/release-process.md"
    ],
    "releaseAuthority": "Maintainers cut releases from the validated default branch state only.",
    "continuityExpectation": "When the maintainer set changes, update governance, linked policies, and machine-readable metadata in the same patch."
  },
  "runtimeSupport": {
    "policyDocument": "docs/src/reference/runtime-support.md",
    "primaryImplementation": "SBCL",
    "supportedTargets": [
      {
        "implementation": "SBCL",
        "platforms": ["Linux"],
        "status": "supported"
      }
    ],
    "bestEffortTargets": [
      {
        "implementation": "Other Common Lisp implementations",
        "platforms": ["implementation-dependent"],
        "status": "best-effort"
      }
    ],
    "implementationSpecificFeatures": [
      "it-isolated subprocess execution",
      "coverage capture and reset/save integration",
      "allocation assertions in CI-focused tests",
      "MOP-dependent metadata and structural assertions"
    ]
  },
  "releaseProcess": {
    "policyDocument": "docs/src/project/release-process.md",
    "releaseStage": "stable",
    "checklist": [
      "Run the full test suite.",
      "Run nix flake check --print-build-logs when Nix is available.",
      "Summarize user-visible changes in the release notes.",
      "Check that README.md and docs/src/project/maintenance-policy.md still match the current workflow.",
      "Review docs/src/project/pull-request-template.md and .github/pull_request_template.md so release-bound changes still capture public-surface notes, validation commands, and follow-up risk in a consistent format.",
      "Verify that cl-weave metadata still advertises the expected package links, reporter list, and schema versions.",
      "Verify that docs/src/project/distribution-policy.md still matches the documented source and Nix install paths.",
      "Confirm the release notes mention any intentional public-surface breaks or migration steps."
    ],
    "contractSyncRequirements": [
      "Keep machine-readable metadata and human-facing documentation in sync.",
      "Keep distributionChannels, README.md, and docs/src/project/distribution-policy.md synchronized when install paths change.",
      "Update tests and docs/src/reference/ai-contract.md when a machine-readable contract changes."
    ]
  },
  "continuousIntegration": {
    "policyDocument": "docs/src/project/release-process.md",
    "provider": "github-actions",
    "workflowPath": ".github/workflows/ci.yml",
    "jobName": "check",
    "triggers": [
      "pull_request",
      "push:main",
      "workflow_dispatch"
    ],
    "systems": [
      "x86_64-linux"
    ],
    "artifactBundle": "cl-weave-test-reports-x86_64-linux",
    "cacheProvider": "cachix",
    "cacheModes": [
      "pull-only",
      "push-enabled"
    ],
    "qualityGateSource": "qualityGates"
  },
  "commands": ["run", "list", "watch", "doctor", "metadata", "version", "help"],
  "reporters": ["spec", "sexp", "json", "jsonl", "tap", "github", "junit"],
  "listReporters": ["spec", "sexp", "json", "jsonl"],
  "artifactSchemas": [
    {
      "kind": "test-results",
      "commands": ["run", "watch"],
      "reporters": ["json"],
      "schemaVersion": 6,
      "streaming": false,
      "fields": [
        {
          "name": "events",
          "kind": "array",
          "required": true,
          "description": "Ordered test events."
        },
        { "name": "passed", "kind": "integer", "required": true },
        { "name": "skipped", "kind": "integer", "required": true },
        { "name": "todos", "kind": "integer", "required": true },
        { "name": "failed", "kind": "integer", "required": true },
        { "name": "errored", "kind": "integer", "required": true },
        { "name": "failedPaths", "kind": "array", "required": true },
        { "name": "erroredPaths", "kind": "array", "required": true }
      ]
    },
    {
      "kind": "cl-weave/results",
      "commands": ["run", "watch"],
      "reporters": ["sexp"],
      "schemaVersion": 4,
      "streaming": false,
      "fields": [
        {
          "name": "events",
          "kind": "list",
          "required": true,
          "description": "Ordered test events."
        },
        {
          "name": "failed-paths",
          "kind": "list",
          "required": true,
          "description": "Vitest-style paths with failed assertions."
        }
      ]
    },
    {
      "kind": "test-event",
      "commands": ["run", "watch"],
      "reporters": ["jsonl"],
      "schemaVersion": 3,
      "streaming": true,
      "fields": [
        {
          "name": "event",
          "kind": "object",
          "required": true,
          "description": "Single test event payload."
        }
      ]
    },
    {
      "kind": "test-plan-entry",
      "commands": ["list"],
      "reporters": ["jsonl"],
      "schemaVersion": 2,
      "streaming": true,
      "fields": []
    },
    {
      "kind": "doctor-report",
      "commands": ["doctor"],
      "reporters": ["json", "sexp"],
      "schemaVersion": 1,
      "streaming": false,
      "fields": [
        {
          "name": "status",
          "kind": "string",
          "required": true,
          "description": "Overall self-diagnostic status: pass, warn, or fail."
        },
        {
          "name": "runtime",
          "kind": "object",
          "required": true,
          "description": "Implementation and working-directory details for the current process."
        },
        {
          "name": "checks",
          "kind": "array",
          "required": true,
          "description": "Named self-diagnostic checks with per-check status and details."
        }
      ]
    }
  ],
  "capabilities": ["vitest-dsl", "describe-it-dsl", "artifact-schemas", "mop-architecture-assertions"],
  "capabilityMatrix": [
    {
      "name": "vitest-dsl",
      "status": "implemented",
      "summary": "Hierarchical and table-driven test registration.",
      "publicApis": ["describe", "it", "describe-each", "it-each", "it-concurrent", "it-property", "it-isolated"],
      "qualityGates": ["flake-check", "filtered-smoke", "plan-artifact"],
      "documentation": ["README.md", "docs/src/reference/ai-contract.md"]
    }
  ],
  "environment": ["CL_WEAVE_REPORTER"],
  "options": [
    {
      "name": "--filter",
      "commands": ["run", "list", "watch"],
      "argument": "TEXT",
      "valueKind": "test-name-pattern",
      "choices": [],
      "commandChoices": [],
      "environment": ["CL_WEAVE_TEST_FILTER"],
      "description": "Run or list tests whose Vitest-style path contains TEXT"
    }
  ],
  "qualityGates": [
    {
      "name": "flake-check",
      "kind": "nix",
      "command": ["nix", "flake", "check", "--print-build-logs"],
      "timeoutSeconds": 600,
      "artifacts": [],
      "description": "Run the complete Nix flake validation suite."
    }
  ],
  "packageExports": [{"name": "cl-weave", "exports": ["describe", "expect", "it"]}],
  "matchers": [{"name": "to-be", "description": null}],
  "mutationOperators": [{"name": "arithmetic-operator", "description": "..."}]
}
```

`--reporter sexp` prints the same data as a Lisp plist. `--reporter spec` is
accepted as the default CLI reporter and normalized to JSON for this command.
`doctor` accepts only `json` and `sexp`; `spec` is normalized to JSON there as
well.
`options[].argument` is the human-facing placeholder used in help text;
`options[].valueKind` is the machine-facing value category agents should use
when constructing commands. `options[].choices` lists finite accepted values for
enumerated options, for example `--reporter` and `--sequence`; non-enumerated
options use an empty array. Boolean flags use `"boolean"` and keep
`argument: null`.
`options[].commandChoices` lists command-specific finite values for options
whose accepted values differ by command, such as `--reporter`; each listed
choice is a subset of `options[].choices`. For example, `--reporter` accepts
`json` and `sexp` for `doctor`, while `list` also accepts `spec` and `jsonl`.
`artifactSchemas` lists every structured reporter artifact kind that agents can
request or observe. `commands` lists every CLI command that can emit the shape;
library-only artifacts use an empty array. `reporters` names the reporter
values that can emit the kind, `schemaVersion` is scoped to that artifact
shape, and `streaming` tells agents whether to parse one complete payload or
newline-delimited events. `fields` is a compact field map for planning parsers
and validating generated CI integrations without hard-coding reporter
internals. `doctor-report` is the canonical self-diagnostic artifact for
runtime and environment checks, and it does not depend on loading a requested
ASDF system. `watch --once` shares the run-result artifact contracts, so result
schemas advertise both `run` and `watch`. Agents must not infer the complete
artifact list from this document's shortened example; call `cl-weave metadata` and read
`artifactSchemas` directly.
For `test-results`, the registry version tracks the JSON/camelCase contract;
the S-expression payload carries its independent `:schema-version` value.
`capabilityMatrix` expands high-level `capabilities` into implementation status,
representative `publicApis`, validating `qualityGates`, and canonical
`documentation` paths. Agents should use it as the feature-readiness map for
adoption planning instead of inferring coverage from examples or file names.
`qualityGates` lists CI-grade commands as argv vectors with explicit
`timeoutSeconds` values and expected artifact paths. Agents should prefer these
runtime gates over scraping README examples when deciding how to validate a
change. One gate exercises `watch --once` explicitly so automation can verify
watch-mode resolution without entering a long-lived polling loop.
`packageExports` lists public external symbols by package in lower-case CL reader
spelling so agents can discover the supported DSL and runtime API without
scraping `package.lisp`.
`homepage`, `bugTracker`, and `license` are the canonical project source,
support, and licensing links; agents should prefer them over ad hoc repository
guesses when linking, filing issues, or summarizing project governance.
`referenceDocuments` lists the canonical non-policy documents that external
tools should read first for CLI usage, machine contracts, native adoption
planning, release notes, and licensing. Agents should prefer these explicit paths over
README section scraping when linking project materials.
`supportChannels` identifies the public support surfaces and intended routing
for bugs, contribution review, and support-boundary questions. Agents should
use these entries before inventing repository URLs or ad hoc escalation paths.
`securityContacts` identifies the canonical vulnerability disclosure surface.
Agents should use these entries instead of filing public issues for security
reports.
`lifecycle` summarizes the current release stage and supported line, then
points back to the support, versioning, and security documents that define the
operational contract in prose.
`governance` points at the canonical governance policy, review ownership file,
maintainer responsibilities, decision documents, release authority, and
continuity expectation for maintainer hand-offs. Agents should use it as the
machine-readable routing contract for compatibility-sensitive changes instead
of inferring governance from repository conventions.
`runtimeSupport` identifies the primary supported implementation, the
platform-level support matrix, and the implementation-specific features that
depend on SBCL behaviour. Agents should consult it before assuming portability
for isolated subprocess runs, coverage capture, allocation assertions, or
MOP-shaped metadata checks.
`releaseProcess` points at the canonical release policy, advertises the
current release stage, and records the checklist plus documentation sync
requirements that must hold when the machine-readable contract changes.
`policyDocuments` lists the canonical policy and governance documents that
describe maintainer authority, issue handling, release flow, support
boundaries, and project scope. The example root mirrors the runtime metadata
and should stay aligned with the CLI contract as new policy documents are
added. For project scope, governance, issue handling, release flow, and
public-surface expectations, agents should prefer the policy documents in
`docs/src/` over README summaries.

## DSL Naming Contract

The public DSL uses canonical Common Lisp hyphenated names. Agents should emit
forms such as `describe-each`, `it-concurrent`, `it-todo-each`,
`expect-not`, and `expect-resolves` directly. Fixture hooks are exported as
`before-all`, `after-all`, `before-each`, `around-each`, and `after-each`.

## S-Expression Reporter

```lisp
(cl-weave:run-all :reporter :sexp)
```

The reporter prints one form on a single line (it binds `*print-pretty*` to
`nil` for stable, machine-readable output); it is shown here across multiple
lines only for readability:

```lisp
(:cl-weave/results
 :schema-version 4
 :passed 1
 :skipped 0
 :todos 0
 :failed 0
 :errored 0
 :events
 ((:status :pass
   :path ("suite" "case")
   :path-string "suite > case"
   :location (:file "tests/example.lisp")
   :seconds 0
   :duration-ms 0
   :condition nil
   :secondary-conditions ()
   :reason nil
   :assertion nil)))
```

For assertion failures, `:assertion` contains:

```lisp
(:form (expect actual :to-be expected)
 :matcher :to-be
 :actual actual-value
 :expected (expected-value)
 :negated nil
 :pass nil)
```

Custom matchers registered with `cl-weave:defmatcher`,
`cl-weave:expect-extend`, or `cl-weave:extend-expect` use the same assertion
payload. The matcher keyword is stored in `:matcher`; the optional second and
third return values become `:actual` and `:expected`, which lets AI agents read
domain-specific failure data without parsing human messages.

Custom matcher definitions may attach a human-readable description as data.
`defmatcher` and `expect-extend` read a leading string in the body.
`extend-expect` accepts either a trailing string or `:description string`.
Agents can inspect the registry without macroexpanding test files:

```lisp
(cl-weave:list-matchers)
;; => ((:name :to-be :description nil)
;;     (:name :to-have-status
;;      :description "Checks that a response plist has the expected HTTP status."))

(cl-weave:matcher-metadata :to-have-status)
;; => (:name :to-have-status
;;     :description "Checks that a response plist has the expected HTTP status.")
```

`extend-expect` accepts a list of matcher specs. Each spec starts with a symbol
name and a two-argument function:

```lisp
((:to-have-status #<function>))
```

The function receives `(actual expected-operands)` and should return:

```lisp
(values pass-p reported-actual reported-expected)
```

`:to-throw` accepts no expected value, a condition class designator, a message
substring, or a predicate function. Failure payloads use:

```lisp
(:actual (:threw t
          :condition-type simple-error
          :message "missing user")
 :expected (:matcher :message-substring
            :value "needle"))
```

Mock function matchers report call and result histories in `:actual`:

```lisp
(:call-count 1
 :calls ((1 2))
 :result-count 1
 :results ((:type :return :value 3 :values (3)))
 :return-count 1
 :throw-count 0)
```

Thrown mock calls use `(:type :throw :condition-type simple-error :message "...")`.
`make-mock-function` produces the documented mock function contract and result
history shape. `mock-function-p` returns true only for
registered cl-weave mock functions and return false, not an error, for other
values.
`mock-implementation` mutates the implementation of an existing mock and
returns that mock. `mock-return-value` and `mock-return-values` are
constant return setters for single and Common Lisp multiple values.
`clear-mock` clears one registered mock history while
preserving its implementation.
`clear-all-mocks` clears every registered mock history
while preserving mock implementations.
`reset-mock` clears one mock history and replaces its implementation with the
default no-op function. `reset-all-mocks` applies that reset behavior to every
registered mock. `spy-on` replaces a symbol function cell with a registered mock
whose default implementation calls the original function. `mock-restore`
restores the function cell only when it is still bound to that
spy, clear the spy history, and restore the spy implementation to the original
function. `restore-all-mocks` restores active spies without resetting regular
mocks.
Return-value matchers compare their operands with the recorded Common Lisp
multiple values list. Ordered mock matchers use one-based indices:
`:to-have-been-nth-called-with` reports `(:index n :arguments (...))`, and
`:to-have-nth-returned-with` reports `(:index n :values (...))`. Nth returned
assertions count only successful `:return` results; thrown results remain in
`:results` but do not consume a returned index.

Smart assertions use the same shape. For predicate forms such as
`(expect (= (+ 1 1) 3))`, the matcher is the predicate symbol and `:actual`
contains operand reports:

```lisp
(:form (expect (= (+ 1 1) 3))
 :matcher =
 :actual ((:form (+ 1 1) :value 2)
          (:form 3 :value 3))
 :expected (= (+ 1 1) 3)
 :negated nil
 :pass nil)
```

## JSON Reporter

```lisp
(cl-weave:run-all :reporter :json)
```

The reporter prints one JSON object:

```json
{
  "schemaVersion": 6,
  "kind": "test-results",
  "passed": 1,
  "skipped": 0,
  "todos": 0,
  "failed": 0,
  "errored": 0,
  "failedPaths": [],
  "erroredPaths": [],
  "events": [
    {
      "status": "pass",
      "path": ["suite", "case"],
      "pathString": "suite > case",
      "location": {"file": "tests/example.lisp"},
      "seconds": 0.0,
      "durationMs": 0.0,
      "condition": null,
      "secondaryConditions": [],
      "reason": null,
      "assertion": null,
      "timeline": [],
      "replaySeed": null
    }
  ]
}
```

Every event also carries a `timeline` array and a `replaySeed`. `timeline` holds
the execution-journal frames recorded when `--journal` (or `*journal-enabled*`)
is active — one object per frame with `index`, `kind` (`assertion`,
`mock-call`, `hook`, or `note`), `form`, `matcher`, `actual`, `expected`,
`pass`, and `elapsedInternalTime` — and is `[]` otherwise. `replaySeed` is the
per-test deterministic seed used when `--random-seed` (or `*test-random-seed*`)
is set, or `null`. Both are nested inside each event, so schema v6 is unchanged.
See [Time-Travel Debugging](../guide/time-travel-debugging.md).

`location` is source metadata captured by the `it` family of macros. Portable
Common Lisp does not expose reliable source line numbers across implementations,
so the stable contract is the source file path only. JSON reporters emit
`null` when a test was constructed manually without location metadata.

The JSONL reporter is a streaming contract for CI logs and AI agents:

```lisp
(cl-weave:run-all :reporter :jsonl)
```

It prints one JSON object per line:

```jsonl
{"schemaVersion":1,"kind":"test-results-start","total":1}
{"schemaVersion":3,"kind":"test-event","event":{"status":"pass","path":["suite","case"],"pathString":"suite > case","location":{"file":"tests/example.lisp"},"seconds":0.0,"durationMs":0.0,"condition":null,"secondaryConditions":[],"reason":null,"assertion":null,"timeline":[],"replaySeed":null}}
{"schemaVersion":1,"kind":"test-results-summary","passed":1,"skipped":0,"todos":0,"failed":0,"errored":0,"failedPaths":[],"erroredPaths":[]}
```

`test-event.event` uses the same object shape as JSON result `events` entries.
`test-results-summary` uses the same counts and rerun path summaries as the JSON
result root object. Set `CL_WEAVE_REPORTER=jsonl` to select this reporter.

Assertion payloads are now structured JSON values when the underlying Common
Lisp data can be represented directly. Property lists become camelCase JSON
objects, vectors and proper lists become arrays, keywords become lowercase JSON
strings, and unstructured objects still fall back to printed strings. This
keeps isolated-process diagnostics and snapshot metadata machine-readable for
CI and agent consumers without changing the surrounding event envelope.

For Nix CLI CI and agent runs, the packaged application writes the same
reporter payload directly to an artifact file:

```sh
timeout 360s nix run . -- run cl-weave/test --reporter json --output cl-weave-results.json
```

`--output` affects only reporter output. The process still exits
with `0` when all selected events pass, skip, or todo, and exits with `1` when
any selected event fails or errors. Empty selections exit with `0` by default;
set `CL_WEAVE_PASS_WITH_NO_TESTS=false`, pass `--fail-with-no-tests`, or call
`run-all` with `:pass-with-no-tests nil` when CI must reject a zero-test run.

External snapshots are sidecar artifacts controlled by dynamic bindings or
CLI/environment settings:

```sh
timeout 360s nix run . -- run cl-weave/test --update-snapshots --snapshot-dir tests/__snapshots__/ --snapshot-file snapshots.sexp
```

Snapshot files are Lisp-readable alists keyed by the explicit snapshot key
passed to `:to-match-snapshot`. They do not alter reporter schemas, so agents
can compare reporter artifacts and snapshot artifacts independently.
State replay snapshots use `:to-match-snapshot-sequence` with a list or
non-string vector of states and one explicit prefix. The stored keys are
deterministic `prefix[n]` entries such as `vm/run[0]` and `vm/run[1]`. Update
mode replaces every existing entry for the prefix before writing the current
sequence, so shortened replays prune stale state snapshots. Verification fails
on missing or mismatched entries and also fails with `:reason
:unexpected-snapshot` when a stored `prefix[n]` exists at or beyond the current
state count.
Lisp-side agents can use `snapshot-entries` to read the current snapshot alist
and `snapshot-value` to retrieve one serialized snapshot value with a separate
presence flag. Both functions respect `*snapshot-directory*` and
`*snapshot-file-name*`, so CLI-driven and REPL-driven replay checks can share
the same artifact location.

Snapshot assertion failures use the normal `:assertion` payload. For missing
snapshots, `:actual` and `:expected` contain `:snapshot-key`, `:snapshot-file`,
`:value`, `:reason :missing-snapshot`, and `:present nil` on the expected side.
For mismatches, both sides include `:reason :snapshot-mismatch` and matching
`:difference` data:

```lisp
(:matcher :to-match-snapshot
 :actual (:snapshot-key "suite/case"
          :snapshot-file "tests/__snapshots__/snapshots.sexp"
          :value "(:ok 43)"
          :reason :snapshot-mismatch
          :difference (:line 1 :expected "(:ok 42)" :actual "(:ok 43)"))
 :expected (:snapshot-key "suite/case"
            :snapshot-file "tests/__snapshots__/snapshots.sexp"
            :value "(:ok 42)"
            :present t
            :reason :snapshot-mismatch
            :difference (:line 1 :expected "(:ok 42)" :actual "(:ok 43)")))
```

Sequence snapshot failures use `:matcher :to-match-snapshot-sequence` and add
`:snapshot-prefix`, `:snapshot-index`, and `:snapshot-count` to both sides of
the assertion payload. Unexpected stale entries report `:present nil` on the
actual side and `:present t` plus the stored serialized value on the expected
side.

Coverage output is a separate artifact, not a reporter schema field:

```sh
timeout 360s nix run . -- run cl-weave/test --coverage --coverage-output cl-weave.coverage
```

The CLI instruments product sources but not the test system and saves an SBCL
coverage state sidecar. Agents should treat it as a separate artifact and
continue to parse S-expression or JSON reporter output for test results.

## Mutation Reports

Mutation reports are explicit API output, not part of `run-all` reporter
payloads. Agents can call `run-mutations`, then serialize the resulting list
with `report-mutations-sexp` or `report-mutations-json`.

Mutation operators expose stable metadata separately from mutation results:

```lisp
(cl-weave:list-mutation-operators)
;; => ((:name :arithmetic-operator
;;      :description "Swaps arithmetic operator heads such as +, -, *, and /.")
;;     ...)

(cl-weave:mutation-operator-metadata :arithmetic-operator)
;; => (:name :arithmetic-operator
;;     :description "Swaps arithmetic operator heads such as +, -, *, and /.")
```

```lisp
(let ((results (cl-weave:run-mutations
                '(+ 1 1)
                (lambda (form mutation)
                  (declare (ignore mutation))
                  (= (eval form) 2)))))
  (cl-weave:assert-mutation-score results 0.95)
  (cl-weave:report-mutations-sexp results *standard-output*)
  (cl-weave:report-mutations-json results *standard-output*))
```

Mutation score gates are stricter than score-only checks. A passing gate
requires a score greater than or equal to the requested threshold, zero
survived mutants, and zero errored mutants. `mutation-score-passes-p` returns
`(values pass-p summary)`. `assert-mutation-score` returns the summary on
success or signals `mutation-score-failure` on failure. Agents can inspect
`mutation-score-failure-summary` and `mutation-score-failure-min-score`.

The S-expression mutation schema is:

```lisp
(:cl-weave/mutations
 :schema-version 1
 :summary (:total 1 :killed 1 :survived 0 :errored 0 :score 1.0)
 :results
 ((:status :killed
   :condition nil
   :mutation (:id 1
              :operator :arithmetic-operator
              :path ()
              :original (+ 1 1)
              :replacement (- 1 1)
              :form (- 1 1)))))
```

The JSON mutation schema is:

```json
{
  "schemaVersion": 1,
  "kind": "mutations",
  "total": 1,
  "killed": 1,
  "survived": 0,
  "errored": 0,
  "score": 1.0,
  "results": [
    {
      "status": "killed",
      "condition": null,
      "mutation": {
        "id": 1,
        "operator": "ARITHMETIC-OPERATOR",
        "path": [],
        "original": "(+ 1 1)",
        "replacement": "(- 1 1)",
        "form": "(- 1 1)"
      }
    }
  ]
}
```

`status` is one of `killed`, `survived`, or `errored`. Assertion failures from
cl-weave expectations count as killed mutants. Other signaled errors are kept
as `errored` so agents can distinguish production-code kills from harness
faults.

## TAP Reporter

```lisp
(cl-weave:run-all :reporter :tap)
```

The TAP reporter emits TAP version 13 for line-oriented CI logs:

```tap
TAP version 13
1..2
ok 1 - math > adds
not ok 2 - math > subtracts
  ---
  status: "fail"
  condition: "Expected 1 to be 2"
  secondary condition: "Cleanup failed"
  ...
```

Skipped and todo events use TAP directives:

```tap
ok 1 - parser > waits for fixture # SKIP fixture unavailable
ok 2 - parser > handles unicode
```

TAP is intentionally a stream format. Agents that need stable field names,
path arrays, assertion payloads, and focused rerun metadata should use the
S-expression or JSON reporters.

## GitHub Actions Reporter

```lisp
(cl-weave:run-all :reporter :github)
```

The GitHub Actions reporter emits workflow command annotations for failed and
errored tests:

```text
::error file=tests/math.lisp::math > subtracts [fail]%0AExpected 1 to be 2
cl-weave: 1 passed, 0 skipped, 0 todo, 1 failed, 0 errored, 2 total
```

Only `:fail` and `:error` events become annotations. Passing, skipped, and todo
events are represented only in the summary line so CI logs stay actionable.
Annotation data uses GitHub workflow command escaping. `file` is emitted when
source location metadata is available; otherwise cl-weave emits an annotation
without a `file` property. Secondary cleanup and hook conditions follow the
primary condition in capture order and use the same workflow-command escaping.

This reporter is a CI log affordance, not a structured artifact schema. Agents
that need stable fields should continue to use the S-expression or JSON
reporters.

For assertion failures, `assertion` contains:

```json
{
  "form": "(EXPECT ACTUAL :TO-BE EXPECTED)",
  "matcher": ":TO-BE",
  "actual": "ACTUAL-VALUE",
  "expected": "(EXPECTED-VALUE)",
  "negated": false,
  "pass": false
}
```

For smart assertions, `matcher`, `actual`, and `expected` are still printable
Lisp strings. A failing `(expect (= (+ 1 1) 3))` serializes the operand report
through the `actual` field, so agents can read the exact evaluated values
without scraping the human spec reporter.

Assertion count declarations are per test attempt. They are reset for retries
and concurrent tests, and the declaration forms do not increment the assertion
counter. A failing exact count check uses:

```lisp
(:form (expect-assertions 2)
 :matcher :assertions
 :actual 1
 :expected 2
 :negated nil
 :pass nil)
```

A failing "at least one assertion" check uses:

```lisp
(:form (expect-has-assertions)
 :matcher :has-assertions
 :actual 0
 :expected (:minimum 1)
 :negated nil
 :pass nil)
```

`path` is the canonical machine path. `pathString` is the same path rendered in
the Vitest-style human format used by filtering. `seconds` is retained for
JUnit parity; `durationMs` is the preferred field for dashboards and agents.
`failedPaths` and `erroredPaths` contain `pathString` values that can be passed
back through `CL_WEAVE_TEST_FILTER` for focused CI or agent reruns.

Performance and allocation matchers report measured values instead of the input
thunk when they fail. For example, a failing `:to-run-under-ms` assertion uses:

```lisp
(:actual (:elapsed-seconds 0.001d0
          :elapsed-ms 1.0d0
          :bytes-consed 0
          :values (:ok))
 :expected (:max-ms 0))
```

`:to-allocate-under` uses the same `:actual` shape and reports `(:max-bytes n)`
as `:expected`. JSON reporters stringify these Lisp payloads in the existing
`actual` and `expected` fields so agents can parse the measurement without
scraping human-oriented output.

Negated matcher assertions use either explicit matcher syntax or Vitest-style
DSL sugar:

```lisp
(expect value :not :to-be expected)
(expect-not value :to-be expected)
```

Both forms run through the same assertion engine. Failing negated assertions
set `:negated t` in the assertion detail and preserve the raw matcher result in
`:pass`, so agents can tell that the matcher itself succeeded but the negated
expectation failed.

Resolving and rejecting assertions use Lisp thunks:

```lisp
(expect-resolves (lambda () (fetch-account)) :to-satisfy #'account-ready-p)
(expect-rejects (lambda () (error "missing user")) :to-be-type-of 'simple-error)
```

`expect-resolves` applies the matcher to the thunk's primary value. If the
thunk signals a condition first, the assertion detail uses:

```lisp
(:matcher :resolves
 :actual (:state :rejected
          :condition-type simple-error
          :message "missing user")
 :expected (:state :resolved))
```

`expect-rejects` applies the matcher to the condition object. If the thunk
returns normally, the assertion detail uses:

```lisp
(:matcher :rejects
 :actual (:state :resolved :value :ok)
 :expected (:state :rejected))
```

String pattern matchers report normalized pattern semantics. A failing
`:to-match` assertion uses:

```lisp
(:actual (:value "common-lisp"
          :pattern "scheme"
          :mode :substring
          :reason :no-match)
 :expected (:pattern "scheme"
            :test :substring))
```

String patterns use substring search. Function designators use
`:mode :predicate` and pass when the predicate returns a non-`nil` value.
Failure reasons are `:not-a-string`, `:no-match`, `:predicate-false`,
`:predicate-error`, and `:invalid-pattern`.

NaN matchers report both type information and predicate results. A failing
`:to-be-nan` assertion uses:

```lisp
(:actual (:value 42
          :type integer
          :float nil
          :nan nil)
 :expected (:predicate :nan
            :test :float-nan-p))
```

`:to-be-nan` accepts no expected operands and passes only when the actual value
is a floating-point NaN.

Strict membership matchers report the candidate collection and match position.
A failing `:to-be-one-of` assertion uses:

```lisp
(:actual (:value :blocked
          :candidates (:pending :ready :done)
          :test eql
          :candidate-count 3
          :matched-index nil)
 :expected (:candidates (:pending :ready :done)
            :test eql
            :candidate-count 3))
```

`:to-be-one-of` accepts one list, vector, or hash table of candidates and uses
`eql`, matching the strict identity semantics of `:to-be`. Hash tables are
searched by value, not by key. Every candidate collection is limited to 100,000
entries.

Deep containment matchers report the searched container and equality predicate.
A failing `:to-contain-equal` assertion uses:

```lisp
(:actual (:container ((:id 1 :name "Ada"))
          :value (:id 2 :name "Grace")
          :test :equalp)
 :expected (:value (:id 2 :name "Grace")
            :test :equalp))
```

The matcher searches sequence elements and hash-table values with `equalp`.
Use `:to-contain` for substring checks and shallow `equal` membership; use
`:to-contain-equal` when nested Lisp data should compare structurally.

Partial object matchers report the original value, requested subset, and the
first divergent path. A failing `:to-match-object` assertion uses:

```lisp
(:actual (:value (:user (:name "Ada"))
          :subset (:user (:name "Grace"))
          :failure (:path (:user :name)
                    :reason :value-mismatch
                    :actual-value "Ada"
                    :expected-value "Grace"
                    :test :equalp))
 :expected (:subset (:user (:name "Grace"))
            :test :partial-equalp))
```

The subset can be a property list, association list, or hash table. Actual
objects can be property lists, association lists, hash tables, or CLOS objects
with matching slot names. Expected vectors are matched against actual sequences
with exact length and order. Failure reasons are `:missing-property`,
`:value-mismatch`, `:length-mismatch`, and `:type-mismatch`.

Property matchers report normalized path traversal data. A failing
`:to-have-property` assertion uses:

```lisp
(:actual (:path (:user :age)
          :present nil
          :value nil)
 :expected (:path (:user :age)
            :value 37))
```

When the path exists but the optional expected value differs, `:present` is true
and `:value` contains the value found at that path. Paths are always reported as
lists, even when the caller used a scalar or vector path.

Close numeric matchers report the comparison tolerance as data. A failing
`:to-be-close-to` assertion uses:

```lisp
(:actual (:value 31/100
          :expected-value 3/10
          :num-digits 2
          :difference 1/100
          :threshold 1/200)
 :expected (:value 3/10
            :num-digits 2
            :threshold 1/200))
```

Ordering matchers report the operator and real-number classification. A failing
`:to-be-greater-than` assertion for a non-real actual value uses:

```lisp
(:actual (:value "10"
          :expected-value 9
          :matcher :to-be-greater-than
          :operator >
          :actual-real nil
          :expected-real t)
 :expected (:value 9
            :matcher :to-be-greater-than
            :operator >))
```

The same payload shape applies to `:to-be-greater-than-or-equal`,
`:to-be-less-than`, and `:to-be-less-than-or-equal`.

MOP architecture matchers report normalized architecture data instead of the raw
input designator. A failing `:to-have-slot` assertion uses:

```lisp
(:actual (:class widget
          :slots (name state))
 :expected (:slot missing-slot))
```

A failing `:to-have-method-specialized-on` assertion uses:

```lisp
(:actual (:methods ((widget stream)
                    (widget t)))
 :expected (:specializers (missing t)))
```

Specializers are printed as class names; EQL specializers are printed as
`(eql value)`.

## Test Selection

Agents can narrow execution without changing source files:

```lisp
(cl-weave:run-all :reporter :json :name-filter "suite > case")
```

`name-filter` is a case-insensitive substring matched against the human path
format `suite > nested suite > case`. The command runner exposes the same
contract through `CL_WEAVE_TEST_FILTER`.

CLI flags use canonical kebab-case names only. Agent-generated commands must
emit the canonical option names directly, for example `--filter`,
`--output`, `--watch-interval`, `--coverage-output`, `--test-timeout-ms`,
`--pass-with-no-tests`, `--fail-with-no-tests`, `--snapshot-dir`,
`--snapshot-file`, `--max-workers`, `--update-snapshots`, `--journal`, and
`--random-seed`.

Filtering changes which events are emitted; it does not change the event shape
or reporter schema versions. If no test matches, reporters emit zero events and
the run is considered successful by default because no selected test failed.
Set `:pass-with-no-tests nil` or use the CLI/environment equivalent to make an
empty selection fail while keeping reporter payloads empty.

Suite-level `describe-skip`, `describe-skip-each`, `describe-todo`, and
`describe-todo-each` compose with the same selection rules. Selected descendant
cases are emitted as ordinary `:skip` or `:todo` events with the suite reason in
`:reason`; suite hooks and test bodies are not executed while the suite is
suppressed.

Conditional registration macros keep the same reporter contract.
`it-skip-if` and `describe-skip-if` emit ordinary `:skip` events when their
condition is true. `it-run-if` and `describe-run-if` emit ordinary `:skip`
events when their condition is false.
The deterministic reasons are `"conditional skip"` and `"conditional run-if"`.
Conditions are evaluated while the test file registers tests; reporters do not
add a new event field or schema version for conditional registration.

## Sharding Contract

Agents can partition selected tests for CI without changing source files:

```lisp
(cl-weave:run-all :reporter :json :name-filter "suite" :shard '(1 3))
(cl-weave:list-tests :reporter :json :shard '(2 3))
```

The command runner exposes the same contract through `CL_WEAVE_SHARD=INDEX/COUNT`.
Indexes are one-based and must satisfy `1 <= INDEX <= COUNT`.

Sharding is applied after focus and `name-filter`. The runner assigns a stable
discovery ordinal to each selected test and keeps only the ordinals that belong
to the requested shard. Reporter schemas are unchanged. If a shard selects no
tests, reporters emit zero events and the run is considered successful.

Suites with no descendants in the requested shard do not run `before-all` or
`after-all`, which keeps unrelated fixture side effects out of parallel CI jobs.

## Sequence Order Contract

Agents can reproduce order-dependent failures without changing source files:

```lisp
(cl-weave:run-all :reporter :json :order :random :seed 12345)
(cl-weave:list-tests :reporter :json :order :random :seed 12345)
```

The command runner exposes the same contract through
`CL_WEAVE_SEQUENCE=random` and `CL_WEAVE_SEQUENCE_SEED=N`. `random` is the only
accepted explicit order value; omitting the option preserves definition order.
When `CL_WEAVE_SEQUENCE_SEED` is explicitly set, it
must be a positive integer so failed CI runs can be reproduced from logs without
ambiguous seed parsing.

Ordering is applied after focus, `name-filter`, and shard selection. Shard
membership remains stable across seeds. Ordering is local to each suite so
`before-all`, `after-all`, `before-each`, `around-each`, and `after-each`
boundaries are preserved. Reporter schemas are unchanged. The same seed and
same test tree produce the same execution and list-mode order across SBCL
processes.

## Fixture Continuation Contract

`around-each` registers a single-argument hook. The argument is the continuation
for the remaining `around-each` hooks and the test body. `before-each` hooks run
before `around-each`; `after-each` hooks run after the continuation returns or
unwinds. Around hooks compose from outer suites to inner suites. Use
`unwind-protect` inside an around hook for deterministic cleanup. Reporter
schemas are unchanged.

`after-each` and `after-all` hooks are guaranteed to run even when the test body
or an inner hook performs a non-local transfer of control. This includes SBCL
timeout conditions and any debugger-invoked restart that unwinds through the
runner: the runner drives its after-each and after-all phases from an
`unwind-protect` cleanup clause, so a fixture teardown is not skipped because an
earlier condition escaped classification as `error`. Error collection for the
`before-each`, `after-each`, `before-all`, and `after-all` phases captures
`serious-condition`, not only `error`, so a timeout raised inside one of those
hooks is recorded as a hook failure rather than aborting the run. A condition
that escapes the test body or an `around-each` hook propagates as the primary
condition; when a primary condition and a teardown condition both occur, the
primary condition propagates and the teardown conditions are attached as
`:secondary-conditions`.

## CPS Continuation Helper Contract

`with-continuation-result` and `with-continuation-values` bind the continuation
symbol supplied in the binding list while evaluating their form. The tested CPS
API should call that local function, usually as `#'next`.

```lisp
(with-continuation-result (value next calledp)
    (compute-cps input #'next)
  (expect calledp :to-be-truthy)
  (expect value :to-equal expected))
```

`with-continuation-result` binds the first value passed to the continuation.
`with-continuation-values` binds the complete value list. The optional third
binding receives whether the continuation was called. If the continuation is not
called, cl-weave signals `assertion-failure` with matcher
`:continuation-called`, actual `(:called nil)`, and expected `(:called t)`.

## Test Plan Contract

Agents can discover selected tests without executing hooks or test bodies:

```lisp
(cl-weave:list-tests :reporter :json :name-filter "parser")
(cl-weave:collect-test-plan (cl-weave::root-suite) :name-filter "parser")
```

The packaged CLI exposes the same discovery mode:

```sh
timeout 120s nix run . -- list cl-weave/test --reporter json --filter parser --shard 1/2 --sequence random --seed 12345
```

The JSON test plan reporter prints one object:

```json
{
  "schemaVersion": 3,
  "kind": "test-plan",
  "total": 1,
  "runnable": 1,
  "skipped": 0,
  "todos": 0,
  "tests": [
    {
      "status": "run",
      "path": ["suite", "case"],
      "pathString": "suite > case",
      "location": {"file": "tests/example.lisp"},
      "reason": null,
      "focused": false,
      "retry": 0,
      "timeoutMs": null,
      "concurrent": false,
      "tags": []
    }
  ]
}
```

The S-expression test plan reporter uses the same data:

```lisp
(:cl-weave/test-plan
 :schema-version 3
 :total 1
 :runnable 1
 :skipped 0
 :todos 0
 :tests
 ((:status :run
   :path ("suite" "case")
   :path-string "suite > case"
   :location (:file "tests/example.lisp")
   :reason nil
   :focused nil
   :retry 0
   :timeout-ms nil
   :tags nil
   :concurrent nil)))
```

Plan `status` is `:run`, `:skip`, or `:todo`; JSON uses `run`, `skip`, or
`todo`. Focus and `CL_WEAVE_TEST_FILTER` narrow discovery with the same rules as
execution. Suite-level skip and todo suppression produces selected descendant
plan entries without running suite hooks or case bodies. `pathString` can be
fed back to `CL_WEAVE_TEST_FILTER` for focused execution after discovery.
The JSONL test plan reporter uses the same entry shape as JSON test plan
`tests` entries:

```jsonl
{"schemaVersion":1,"kind":"test-plan-start","total":1}
{"schemaVersion":2,"kind":"test-plan-entry","test":{"status":"run","path":["suite","case"],"pathString":"suite > case","location":{"file":"tests/example.lisp"},"reason":null,"focused":false,"retry":0,"timeoutMs":null,"concurrent":false,"tags":[]}}
{"schemaVersion":1,"kind":"test-plan-summary","total":1,"runnable":1,"skipped":0,"todos":0}
```

List mode supports `spec`, `sexp`, `json`, and `jsonl` reporters. It exits with status
`0` after writing the plan, including when no tests match.

Agents that need symbolic selection can avoid parsing reporter output and use
the Lisp-native logic layer:

```lisp
(cl-weave:test-plan-facts (cl-weave:collect-test-plan (cl-weave::root-suite)))
;; => ((:test ("suite" "case"))
;;     (:status ("suite" "case") :run)
;;     (:retry ("suite" "case") 0)
;;     ...)

(cl-weave:test-plan-where
 (cl-weave:collect-test-plan (cl-weave::root-suite))
 (:status ?test :run)
 (:focused ?test))
;; => (((?test . ("suite" "case"))))
```

Logic variables are symbols whose names start with `?`. Facts, rules, and query
clauses stay as plain lists; `logic-program`, `logic-run`, `logic-where`, and
`test-plan-where` are macro syntax over that data contract. Rules use Prolog
shape `(:- head goal...)`, `logic-query` resolves them with recursive
backtracking, and `(:limit n)` as the first query form caps result count. The
stable public relation names are `:test`, `:status`, `:reason`, `:focused`,
`:retry`, `:timeout-ms`, `:concurrent`, and `:location`.

Agents can derive higher-level plan views by appending rules to
`test-plan-facts` and querying the combined program directly:

```lisp
(let* ((plan (cl-weave:collect-test-plan (cl-weave::root-suite)))
       (program (append
                 (cl-weave:test-plan-facts plan)
                 (cl-weave:logic-program
                  (:- (:selected ?test)
                      (:status ?test :run)
                      (:focused ?test)
                      (:concurrent ?test))))))
  (cl-weave:test-plan-where program
    (:selected ?test)))
;; => (((?test . ("suite" "case"))))
```

## Bail Contract

Agents can stop after the first failure or after a fixed number of failing
events:

```lisp
(cl-weave:run-all :reporter :json :bail t)
(cl-weave:run-all :reporter :json :bail 2)
```

The command runner exposes the same control through `CL_WEAVE_BAIL`. Accepted
values are `true`, `yes`, `on`, `t`, `false`, `no`, `off`, `0`, `nil`, or a
positive integer. Other boolean environment variables use the same false tokens:
`0`, `false`, `no`, `off`, and `nil`.

Bail counts only emitted `:fail` and `:error` events. `:pass`, `:skip`, and
`:todo` events do not advance the counter. When the limit is reached, reporters
emit only the selected events that were executed before the runner stopped.
The event shape, summary fields, `schemaVersion`, `path`, `pathString`, and
`location` contracts are unchanged.

## Retry And Timeout Contract

Case options are passed as a keyword plist immediately after the case name:

```lisp
(it "eventually stable" (:retry 2 :timeout-ms 500)
  (expect (probe) :to-be :ready))

(it-concurrent "parallel-safe case" (:timeout-ms 500)
  (expect (probe-independent-service) :to-be :ready))

(describe-concurrent "parallel-safe suite"
  (it "inherits concurrent mode"
    (expect (probe-independent-service) :to-be :ready))
  (it-sequential "uses shared state"
    (expect (probe-shared-state) :to-be :ready)))
```

`:retry` is the number of extra attempts after the first attempt. Retries apply
only to `:fail` and `:error` attempt events. The runner emits only the final
event, so reporter schemas do not expose intermediate attempts.

Command runners can set a global retry default with `--retry N` or
`CL_WEAVE_RETRY=N`. Local `:retry` wins over the global default, including
`:retry 0` for one-shot cases inside a globally retried suite.

`:timeout-ms` is a per-attempt wall-clock budget. When an attempt times out, the
final event status is `:fail`, `:condition` prints a `test-timeout`, and
`:assertion` is `nil`. Fixture hooks are still executed through the same
`before-each` / `around-each` / `after-each` contract as ordinary test attempts.

Command runners can set a global timeout default with `--test-timeout-ms N`,
`CL_WEAVE_TEST_TIMEOUT_MS=N`, or `CL_WEAVE_TEST_TIMEOUT=N`. Local `:timeout-ms`
wins over the global default. List mode and structured test-plan reporters
expose the effective retry and timeout values after applying these defaults.

Command runners can bound adjacent concurrent batches with `--max-workers N` or
`CL_WEAVE_MAX_WORKERS=N`. List mode remains discovery-only and does not consume
the worker setting.

`(:execution-mode :concurrent)` and `it-concurrent` mark a case as safe for
parallel execution with adjacent concurrent cases. `describe-concurrent` applies
the same mode to descendants, while
`it-sequential` opts individual cases out.
Reporter schemas continue to expose the effective mode as the stable
`concurrent` boolean. Event arrays and test-plan arrays remain in selected
definition order. `:bail` disables concurrent batching to keep fast-fail
semantics exact.

## Expected Failure Contract

`it-fails` registers ordinary runnable cases with the same option plist as `it`.

```lisp
(it-fails "documents a known parser bug" (:retry 1 :timeout-ms 500)
  (expect (parse-fragment input) :to-be :accepted))
```

Reporter schemas are unchanged. A raw `assertion-failure` becomes final status
`:pass`. An implementation error or timeout retains its raw `:error` or `:fail`
status. A raw normal completion becomes final status `:fail` with an
`expected-failure-missed` condition. `:reason` remains reserved for skip and
todo events; expected-failure metadata is not emitted as an event reason.

Retry observes transformed attempt events. This means an unexpectedly passing
expected-failure case is retryable as `:fail`, while the first assertion
failure becomes `:pass` and stops retrying. Errors and timeouts follow the
ordinary retry policy.

## Interactive Restart Contract

Each runnable attempt exposes three Common Lisp restarts while fixtures, the
test body, and timeout boundary are active:

- `continue-test` returns a normal `:pass` event for the current attempt.
- `skip-test` returns a normal `:skip` event and accepts an optional reason.
- `retry-test` reruns the attempt without decrementing the configured `:retry`
  count.

Reporter schemas are unchanged. The final event is still one of the ordinary
event statuses, and no intermediate retry or restart metadata is emitted. If no
handler or debugger invokes a restart, failures, errors, and timeouts keep the
same CI behavior described above.

## Table-Driven Macro Expansion

`it-each` and `describe-each` are compile-time expansion helpers,
not runtime loop constructs.

```lisp
(it-each ((1 2 3)
          (13 21 34))
    "adds ~A and ~A"
    (left right total)
  (expect (+ left right) :to-be total))
```

`it-each` emits independent `it` registrations. `describe-each`
emits independent `describe` registrations, and the generated suite bodies use
the same fixture, assertion, filtering, and reporter contracts as hand-written
suites.

Reporters do not expose table metadata. Agents should treat expanded table cases
as ordinary events whose identity is the formatted path emitted by the runner.

## ASDF Runner Contract

Agents can discover declared source files before choosing a focused run:

```lisp
(cl-weave:asdf-system-files "my-project-tests" :include-dependencies t)
```

`run-system` and `watch-system` preserve reporter contracts because both call
`run-all` after ASDF loading:

```lisp
(cl-weave:run-system "my-project-tests" :reporter :json :name-filter "parser" :shard '(1 2) :order :random :seed 12345 :bail 1 :coverage t :coverage-output "my-project-tests.coverage" :coverage-report-directory "my-project-tests-coverage-report/" :pass-with-no-tests t)
(cl-weave:watch-system "my-project-tests" :reporter :json :shard '(1 2) :order :random :seed 12345 :bail 1 :coverage t :coverage-output "my-project-tests.coverage" :coverage-report-directory "my-project-tests-coverage-report/" :pass-with-no-tests t :once t)
```

`watch-system` writes status lines to `:status-stream`, which defaults to
`*error-output*`, and writes reporter payloads to `:stream`. Watch reruns keep
the same coverage destination and zero-test acceptance policy as the initial
invocation. CI should keep `CL_WEAVE_WATCH` unset; watch mode is for local
agents and REPL sessions. The CLI and script runner expose the same one-shot
contract through `--once` and `CL_WEAVE_WATCH_ONCE=1`, which execute the
initial watch run and exit without entering the polling loop.

Tests may declare `:watch-depends-on` paths. Relative dependencies resolve from
the defining test file. A watch cycle containing only registered test files or
declared dependencies selects the affected test paths; any unknown changed file
forces a full-suite rerun. This conservative fallback prevents incomplete
dependency declarations from silently omitting tests.

## Property Failure Contract

`it-property` failures are normal assertion failures with matcher `:property`.
The assertion payload keeps the original generated values and the minimized
values in `:actual`, plus the deterministic seed and zero-based generated case
index needed for focused reproduction:

```lisp
(:actual (:seed 12345
          :case-index 7
          :values (17 (:open 2))
          :minimal (1 (:open 1))
          :condition "Assertion failed ...")
 :expected (value command))
```

Generator combinators do not create new event types. `src/property-core.lisp`,
`src/property-generators.lisp`, and `src/property-runner.lisp` separate
generator data, value production, shrinking, and property execution;
`src/registration.lisp` only expands `it-property` into that runner. `gen-map`,
`gen-one-of`, `gen-recursive`, `gen-tuple`, and `gen-such-that` only affect
generated values and shrink candidates before the same `assertion-failure`
payload is reported. `gen-character`, `gen-string`, and `gen-vector` cover
sequence-heavy APIs with bounded lengths and shrink candidates. `gen-symbol`,
`gen-keyword`, `gen-sexp`, and `gen-form` are convenience generators for
Lisp-native property tests and macro-expansion inputs. `gen-state-machine`
accepts an initial state, a `(state event)` transition function, an event
generator, and bounded event length options. It returns a plist with `:initial`,
`:events`, `:states`, and `:final`; shrinking shrinks only the event stream and
then deterministically recomputes states. The same seed, case index, generated
values, and minimal payload contract applies to state-machine traces.

Property CI controls are strict. `CL_WEAVE_PROPERTY_TESTS` must parse as a
positive integer, and `CL_WEAVE_PROPERTY_SEED` must parse as an integer. Invalid
values are cl-weave errors, not implementation-level parser errors, so agents
can treat them as configuration failures.

## Isolated Process Contract

`it-isolated` expands to a normal `it` case that calls `run-isolated` and then
asserts the returned `isolated-result` succeeded. The child process loads the
declared ASDF systems before evaluating the body.

```lisp
(it-isolated "native boundary"
    (:systems ("my-project-tests") :timeout 5 :keep-files :on-failure)
  (expect (call-native) :to-be :ok))
```

`run-isolated` returns an `isolated-result` with:

```lisp
(:status :pass-or-fail-or-timeout
 :exit-code 0
 :stdout "..."
 :stderr "..."
 :timed-out-p nil
 :elapsed-ms 12
 :script-path "/tmp/cl-weave-isolated-....lisp"
 :stdout-path "/tmp/cl-weave-isolated-....stdout"
 :stderr-path "/tmp/cl-weave-isolated-....stderr"
 :home-path "/tmp/cl-weave-isolated-....home/")
```

The `:stdout` and `:stderr` strings are the full child-process captures decoded
as UTF-8 text. Decoding reads the capture files by character, so non-ASCII
output (for example `雪😀` on stdout or `警告` on stderr) is returned exactly,
with no trailing NUL padding from an octet-versus-character length mismatch.

The path accessors are populated only when files are retained. `:keep-files`
accepts `nil`, `t`, or `:on-failure`; `:on-failure` keeps artifacts for
`:fail` and `:timeout` results while still deleting successful child-process
artifacts. With the default `:keep-files nil`, the public result path slots are
always `nil`. Cleanup is synchronous: the parent regains control only after an
`unwind-protect` cleanup clause has made a best-effort attempt to delete the
script, stdout, stderr, and home-directory files (`delete-file` and
`uiop:delete-directory-tree`, each wrapped in `ignore-errors`). There is no
cleanup registry, retry queue, or background worker; a delete that fails is
silently skipped rather than retried.

When `it-isolated` fails, the assertion matcher is `:isolated` and the payload
keeps the child process diagnostics:

```lisp
(:actual (:status :timeout
          :exit-code nil
          :timed-out-p t
          :elapsed-ms 100
          :stdout ""
          :stderr ""
          :script-path "/tmp/cl-weave-isolated-....lisp"
          :stdout-path "/tmp/cl-weave-isolated-....stdout"
          :stderr-path "/tmp/cl-weave-isolated-....stderr"
          :home-path "/tmp/cl-weave-isolated-....home/")
 :expected (:status :pass :exit-code 0))
```

This is intended for FFI and crash-boundary tests where agents must preserve
the parent runner while still receiving parseable failure data.

`run-isolated` spawns a single SBCL subprocess via `sb-ext:run-program` and
tracks only that direct child; it does not create a separate session or
process group, and it does not track or signal any grandchild processes the
child spawns. On timeout, the tracked child receives `SIGTERM` (15), then
`SIGKILL` (9) after a short grace period if it is still alive. This is process
cleanup for the direct child only, not an OS security sandbox or a containment
guarantee over descendant processes.

## Stability

- `:schema-version` and `schemaVersion` change only when the shape changes.
- `metadata.schemaVersion` is the discovery payload shape. Individual entries in
  `artifactSchemas` carry their own artifact-level `schemaVersion` values.
- JSON result artifacts use `kind: "test-results"` so agents can classify
  artifacts without filename or command context.
- `:path` is a list of suite names followed by the case name.
- `:status` is one of `:pass`, `:skip`, `:todo`, `:fail`, or `:error`; JSON
  uses the corresponding lowercase strings.
- `:condition` is a printable string or `nil`; JSON uses a string or `null`.
- `:secondary-conditions` is an ordered list of printable cleanup and hook
  conditions; JSON uses the `secondaryConditions` array, including an empty
  array when none were captured.
- `:reason` is a skip or todo reason string for `:skip` and `:todo` events,
  otherwise `nil`; JSON uses a string or `null`.
- `:assertion` is `nil` unless the failure came from `expect`; JSON uses an
  object or `null`.
- JSON `form`, `matcher`, `actual`, and `expected` fields are printable Lisp
  strings.
