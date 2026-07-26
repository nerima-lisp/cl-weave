(in-package #:cl-weave/metadata)

(defparameter *metadata-commands*
  '("run" "list" "watch" "doctor" "metadata" "version" "help"))

(defparameter *metadata-extra-environment-variables*
  '("CL_WEAVE_PROPERTY_TESTS"
    "CL_WEAVE_PROPERTY_SEED"
    "CL_WEAVE_COVERAGE_REPORT_DIR"))

(defparameter *metadata-policy-documents*
  '("docs/src/community-health.md"
    "docs/src/distribution-policy.md"
    "docs/src/governance.md"
    "docs/src/issue-reporting.md"
    "docs/src/maintenance-policy.md"
    "docs/src/project-scope.md"
    "docs/src/pull-request-template.md"
    "docs/src/release-process.md"
    "docs/src/runtime-support.md"
    "docs/src/support-policy.md"
    "docs/src/triage-policy.md"
    "docs/src/versioning-policy.md"))

(defparameter *metadata-reference-documents*
  '((:name "readme"
     :path "README.md"
     :description "Primary user-facing guide and CLI reference.")
    (:name "ai-contract"
     :path "docs/src/ai-contract.md"
     :description "Machine-readable contract and metadata normalization guide.")
    (:name "adoption-guide"
     :path "docs/src/adoption.md"
     :description "Native adoption guide and downstream integration plan.")
    (:name "license"
     :path "LICENSE"
     :description "Canonical project license text.")))

(defparameter *metadata-distribution-channels*
  '((:name "source-self-test"
     :kind "nix"
     :install-command ()
     :run-command ("nix" "run" "." "--" "run" "cl-weave/test")
     :scope "Run the bundled ASDF test system through the packaged CLI."
     :references ("README.md"
                  "docs/src/distribution-policy.md"))
    (:name "nix-local-cli"
     :kind "nix"
     :install-command ("nix" "profile" "install" ".")
     :run-command ("nix" "run" "." "--" "--help")
     :scope "Install and run the packaged CLI from the current checkout."
     :references ("README.md"
                  "docs/src/distribution-policy.md"))
    (:name "nix-remote-cli"
     :kind "nix"
     :install-command ("nix" "profile" "install" "github:nerima-lisp/cl-weave")
     :run-command ("nix" "run" "github:nerima-lisp/cl-weave" "--" "--help")
     :scope "Install and run the packaged CLI without cloning the repository."
     :references ("README.md"
                  "docs/src/distribution-policy.md"))))

(defparameter *metadata-support-channels*
  '((:name "issue-tracker"
     :kind "github"
     :target "https://github.com/nerima-lisp/cl-weave/issues"
     :scope "Reproducible bugs, documentation gaps, and concrete feature requests.")
    (:name "pull-requests"
     :kind "github"
     :target "https://github.com/nerima-lisp/cl-weave/pulls"
     :scope "Validated fixes that are ready for review.")
    (:name "support-policy"
     :kind "document"
     :target "docs/src/support-policy.md"
     :scope "Canonical support boundaries, report contents, and escalation guidance.")))

(defparameter *metadata-community-health*
  `((:name "bug-report-form"
     :kind "github-issue-template"
     :path ".github/ISSUE_TEMPLATE/bug_report.md"
     :purpose "Structured bug intake that routes reporters to the canonical issue reporting guide."
     :references ("docs/src/community-health.md"
                  "docs/src/issue-reporting.md")
     :required-sections ("Summary"
                         "Reproduction"
                         "Expected Behavior"
                         "Actual Behavior"
                         "Validation"
                         "Additional Context")
     :contact-links nil)
    (:name "feature-request-form"
     :kind "github-issue-template"
     :path ".github/ISSUE_TEMPLATE/feature_request.md"
     :purpose "Structured feature intake that reinforces project scope and validation expectations."
     :references ("docs/src/community-health.md"
                  "docs/src/project-scope.md"
                  "docs/src/support-policy.md")
     :required-sections ("Problem"
                         "Proposed Change"
                         "Validation Plan"
                         "Scope Check"
                         "Public Surface Notes")
     :contact-links nil)
    (:name "issue-template-config"
     :kind "github-issue-template-config"
     :path ".github/ISSUE_TEMPLATE/config.yml"
     :purpose ,(concatenate 'string
                            "GitHub issue chooser configuration that redirects support and "
                            "security traffic to canonical policies.")
     :references ("docs/src/community-health.md"
                  "docs/src/support-policy.md"
                  "docs/src/issue-reporting.md")
     :required-sections nil
     :contact-links
     ((:name "Support policy"
       :target "https://github.com/nerima-lisp/cl-weave/blob/main/docs/src/support-policy.md"
       :purpose "Check whether the request belongs in issue tracking and what detail is required.")
      (:name "Security reporting"
       :target "https://github.com/nerima-lisp/cl-weave/security/advisories/new"
       :purpose "Report vulnerabilities through the private security contact path.")
      (:name "Issue reporting guide"
       :target "https://github.com/nerima-lisp/cl-weave/blob/main/docs/src/issue-reporting.md"
       :purpose "Review the canonical reproduction format before filing a bug.")))
    (:name "pull-request-template"
     :kind "github-pull-request-template"
     :path ".github/pull_request_template.md"
     :purpose
     "Default PR body that mirrors the canonical review checklist and public-surface prompts."
     :references ("docs/src/community-health.md"
                  "docs/src/pull-request-template.md")
     :required-sections ("Summary"
                         "Validation"
                         "Public Surface Impact"
                         "Follow-up Risk")
     :contact-links nil)
    (:name "codeowners"
     :kind "github-codeowners"
     :path ".github/CODEOWNERS"
     :purpose "Review ownership declaration for repository-wide changes."
     :references ("docs/src/community-health.md"
                  "docs/src/governance.md")
     :required-sections nil
     :contact-links nil)))

(defparameter *metadata-security-contacts*
  '((:name "security-reporting"
     :kind "github"
     :target "https://github.com/nerima-lisp/cl-weave/security/advisories/new"
     :scope "Private vulnerability reporting through GitHub security advisories.")))

(defparameter *metadata-lifecycle*
  '(:stage "stable"
    :status "active"
    :supported-line "main"
    :support-document "docs/src/support-policy.md"
    :versioning-document "docs/src/versioning-policy.md"))

(defparameter *metadata-governance*
  `(:policy-document "docs/src/governance.md"
    :review-ownership ".github/CODEOWNERS"
    :maintainer-responsibilities
    (,(concatenate 'string
       "Triaging issues and pull requests against the documented project "
       "scope and support boundaries.")
     "Protecting documented public-surface expectations recorded in the versioning policy."
     "Keeping machine-readable metadata, release notes, and policy documents synchronized."
     "Requiring regression coverage for public-surface changes when practical."
     "Handling security-sensitive reports through private GitHub security advisories.")
    :decision-documents
    ("docs/src/project-scope.md"
     "docs/src/support-policy.md"
     "docs/src/triage-policy.md"
     "docs/src/versioning-policy.md"
     "docs/src/release-process.md")
    :release-authority
    "Maintainers cut releases from the validated default branch state only."
    :continuity-expectation
    ,(concatenate 'string
                  "When the maintainer set changes, update governance, linked policies, and "
                  "machine-readable metadata in the same patch.")))

(defparameter *metadata-runtime-support*
  '(:policy-document "docs/src/runtime-support.md"
    :primary-implementation "SBCL"
    :supported-targets ((:implementation "SBCL"
                         :platforms ("Linux")
                         :status "supported"))
    :best-effort-targets ((:implementation "Other Common Lisp implementations"
                           :platforms ("implementation-dependent")
                           :status "best-effort"))
    :implementation-specific-features
    ("it-isolated subprocess execution"
     "coverage capture and reset/save integration"
     "allocation assertions in CI-focused tests"
     "MOP-dependent metadata and structural assertions")))

(defparameter *metadata-release-process*
  `(:policy-document "docs/src/release-process.md"
    :release-stage "stable"
    :checklist
    ("Run the full test suite."
     "Run nix flake check --print-build-logs when Nix is available."
     "Summarize user-visible changes in the release notes."
     "Check that README.md and docs/src/maintenance-policy.md still match the current workflow."
     ,(concatenate 'string
                   "Review docs/src/pull-request-template.md and .github/pull_request_template.md "
                   "so release-bound changes still capture public-surface notes, validation "
                   "commands, and follow-up risk in a consistent format.")
     ,(concatenate 'string
                   "Verify that cl-weave metadata still advertises the expected package links, "
                   "reporter list, and schema versions.")
     ,(concatenate 'string
                   "Verify that docs/src/distribution-policy.md still matches the documented "
                   "source and Nix install paths.")
     "Confirm the release notes mention any intentional public-surface breaks or migration steps.")
    :contract-sync-requirements
    ("Keep machine-readable metadata and human-facing documentation in sync."
     ,(concatenate 'string
                   "Keep distributionChannels, README.md, and docs/src/distribution-policy.md "
                   "synchronized when install paths change.")
     "Update tests and docs/src/ai-contract.md when a machine-readable contract changes.")))

(defparameter *metadata-continuous-integration*
  '(:policy-document "docs/src/release-process.md"
    :provider "github-actions"
    :workflow-path ".github/workflows/ci.yml"
    :job-name "check"
    :triggers ("pull_request" "push:main" "workflow_dispatch")
    :systems ("x86_64-linux")
    :artifact-bundle "cl-weave-test-reports-x86_64-linux"
    :cache-provider "cachix"
    :cache-modes ("pull-only" "push-enabled")
    :quality-gate-source "qualityGates"))
