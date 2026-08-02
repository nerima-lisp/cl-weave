(in-package #:cl-weave/test)

(describe "cli metadata CI"
  (it "serializes framework metadata from the supplied plist"
    (let* ((metadata (list
                      :kind "custom-metadata"
                      :schema-version 7
                      :version "test-version"
                      :commands '("custom-command")
                      :reporters '("custom-reporter")
                      :list-reporters '("custom-list-reporter")
                      :runtime-support
                      (list :policy-document "docs/src/reference/runtime-support.md"
                            :primary-implementation "SBCL"
                            :supported-targets
                            (list (list :implementation "SBCL"
                                        :platforms '("Linux")
                                        :status "supported"))
                            :best-effort-targets
                            (list (list :implementation "Other CL"
                                        :platforms '("implementation-dependent")
                                        :status "best-effort"))
                            :implementation-specific-features
                            '("custom runtime feature"))
                      :governance
                      (list :policy-document "docs/src/project/governance.md"
                            :review-ownership ".github/CODEOWNERS"
                            :maintainer-responsibilities
                            '("custom maintainer responsibility")
                            :decision-documents
                            '("docs/src/project/project-scope.md")
                            :release-authority "custom release authority"
                            :continuity-expectation "custom continuity expectation")
                      :release-process
                      (list :policy-document "docs/src/project/release-process.md"
                            :release-stage "stable"
                            :checklist '("custom release check")
                            :contract-sync-requirements
                            '("custom sync requirement"))
                      :continuous-integration
                      (list :policy-document "docs/src/project/release-process.md"
                            :provider "github-actions"
                            :workflow-path ".github/workflows/ci.yml"
                            :job-name "nix"
                            :triggers '("pull_request")
                            :systems '("x86_64-linux")
                            :artifact-bundle "custom-test-reports-x86_64-linux"
                            :cache-provider "cachix"
                            :cache-modes '("pull-only")
                            :quality-gate-source "qualityGates")
                      :artifact-schemas
                      (list (list :kind "custom-artifact"
                                  :commands '()
                                  :reporters '("custom-reporter")
                                  :schema-version 9
                                  :streaming t
                                  :fields
                                  (list (list :name "payload"
                                              :kind "object"
                                              :required t
                                              :description "custom payload"))))
                      :quality-gates
                      (list (list :name "custom-gate"
                                  :kind "custom-kind"
                                  :command '("custom" "check")
                                  :timeout-seconds 42
                                  :artifacts '("custom-artifact.json")
                                  :description "custom gate"))
                      :capabilities '("custom-capability")
                      :capability-matrix
                      (list (list :name "custom-capability"
                                  :status "implemented"
                                  :summary "custom capability summary"
                                  :public-apis '("custom-api")
                                  :quality-gates '("custom-gate")
                                  :documentation '("CUSTOM.md")))
                      :environment '("CUSTOM_ENV")
                      :options
                      (list (list :name "--custom"
                                  :commands '("custom-command")
                                  :argument "VALUE"
                                  :value-kind :custom-value
                                  :choices '("custom-choice")
                                  :command-choices
                                  '(("custom-command" ("custom-choice")))
                                  :environment '("CUSTOM_ENV")
                                  :description "custom option"))
                      :package-exports
                      (list (list :name "custom-package"
                                  :exports '("custom-export")))
                      :matchers
                      (list (list :name :custom-matcher
                                  :description "custom matcher"))
                      :distribution-channels
                      (list (list :name "custom-distribution"
                                  :kind "custom"
                                  :install-command '("custom" "install")
                                  :run-command '("custom" "run")
                                  :scope "custom scope"
                                  :references '("CUSTOM.md")))
                      :mutation-operators
                      (list (list :name :custom-mutator
                                  :description "custom mutation operator"))))
           (output (with-output-to-string (stream)
                     (cl-weave/metadata::write-framework-metadata-json
                      metadata stream))))
      (expect output :to-contain "\"kind\":\"custom-metadata\"")
      (expect output :to-contain "\"schemaVersion\":7")
      (expect output :to-contain "\"custom-command\"")
      (expect output :to-contain "\"custom-list-reporter\"")
      (expect output :to-contain "\"artifactSchemas\"")
      (expect output :to-contain "\"kind\":\"custom-artifact\"")
      (expect output :to-contain "\"commands\":[]")
      (expect output :to-contain "\"schemaVersion\":9")
      (expect output :to-contain "\"streaming\":true")
      (expect output :to-contain "\"fields\"")
      (expect output :to-contain "\"name\":\"payload\"")
      (expect output :to-contain "\"description\":\"custom payload\"")
      (expect output :to-contain "\"qualityGates\"")
      (expect output :to-contain "\"name\":\"custom-gate\"")
      (expect output :to-contain "\"kind\":\"custom-kind\"")
      (expect output :to-contain "\"command\":[\"custom\",\"check\"]")
      (expect output :to-contain "\"timeoutSeconds\":42")
      (expect output :to-contain "\"custom-artifact.json\"")
      (expect output :to-contain "\"capabilityMatrix\"")
      (expect output :to-contain "\"status\":\"implemented\"")
      (expect output :to-contain "\"summary\":\"custom capability summary\"")
      (expect output :to-contain "\"publicApis\":[\"custom-api\"]")
      (expect output :to-contain "\"documentation\":[\"CUSTOM.md\"]")
      (expect output :to-contain "\"--custom\"")
      (expect output :not :to-contain "\"aliases\":")
      (expect output :to-contain "\"valueKind\":\"custom-value\"")
      (expect output :to-contain "\"choices\":[\"custom-choice\"]")
      (expect output :to-contain "\"commandChoices\"")
      (expect output :to-contain "\"command\":\"custom-command\"")
      (expect output :to-contain "\"CUSTOM_ENV\"")
      (expect output :to-contain "\"custom option\"")
      (expect output :to-contain "\"custom-package\"")
      (expect output :to-contain "\"custom-matcher\"")
      (expect output :to-contain "\"distributionChannels\"")
      (expect output :to-contain "\"name\":\"custom-distribution\"")
      (expect output :to-contain "\"installCommand\":[\"custom\",\"install\"]")
      (expect output :to-contain "\"runCommand\":[\"custom\",\"run\"]")
      (expect output :to-contain "\"governance\"")
      (expect output :to-contain "\"reviewOwnership\":\".github\\/CODEOWNERS\"")
      (expect output :to-contain "\"custom maintainer responsibility\"")
      (expect output :to-contain "\"custom release authority\"")
      (expect output :to-contain "\"runtimeSupport\"")
      (expect output :to-contain "\"releaseProcess\"")
      (expect output :to-contain "\"continuousIntegration\"")
      (expect output :to-contain "\"workflowPath\":\".github\\/workflows\\/ci.yml\"")
      (expect output :to-contain "\"cacheModes\":[\"pull-only\"]")
      (expect output :to-contain "\"primaryImplementation\":\"SBCL\"")
      (expect output :to-contain "\"releaseStage\":\"stable\"")
      (expect output :not :to-contain "\"cl-weave-metadata\"")
      (expect output :not :to-contain "\"cl-weave\"")
      (expect output :not :to-contain "\"--testNamePattern\"")
      (expect output :not :to-contain "\"describe-it-dsl\"")))

  (it "advertises CI workflow operations as structured metadata"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (ci (getf metadata :continuous-integration)))
      (expect (getf metadata :schema-version) :to-be 23)
      (expect ci :not :to-be nil)
      (expect (getf ci :policy-document) :to-equal "docs/src/project/release-process.md")
      (expect (getf ci :provider) :to-equal "github-actions")
      (expect (getf ci :workflow-path) :to-equal ".github/workflows/ci.yml")
      (expect (getf ci :job-name) :to-equal "check")
      (expect (getf ci :triggers)
              :to-equal '("pull_request" "push:main" "workflow_dispatch"))
      (expect (getf ci :systems)
              :to-equal '("x86_64-linux"))
      (expect (getf ci :artifact-bundle)
              :to-equal "cl-weave-test-reports-x86_64-linux")
      (expect (getf ci :cache-provider) :to-equal "cachix")
      (expect (getf ci :cache-modes)
              :to-equal '("pull-only" "push-enabled"))
      (expect (getf ci :quality-gate-source) :to-equal "qualityGates")))

  (it "advertises CI quality gates as structured metadata"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (gates (getf metadata :quality-gates))
           (flake-gate (find-metadata-entry :name "flake-check" gates))
           (metadata-gate
             (find-metadata-entry :name "ai-metadata-artifact" gates))
           (jsonl-gate
             (find-metadata-entry :name "jsonl-events-artifact" gates))
           (watch-once-gate
             (find-metadata-entry :name "watch-once-artifact" gates))
           (junit-gate (find-metadata-entry :name "junit-artifact" gates)))
      (expect (getf metadata :schema-version) :to-be 23)
      (expect flake-gate :not :to-be nil)
      (expect (getf flake-gate :kind) :to-equal "nix")
      (expect (getf flake-gate :command)
              :to-equal '("nix" "flake" "check" "--print-build-logs"))
      (expect (getf flake-gate :timeout-seconds) :to-be 900)
      (expect (getf flake-gate :artifacts) :to-equal '())
      (expect metadata-gate :not :to-be nil)
      (expect (getf metadata-gate :command) :to-contain "metadata")
      (expect (getf metadata-gate :artifacts)
              :to-contain "cl-weave-metadata.json")
      (expect jsonl-gate :not :to-be nil)
      (expect (getf jsonl-gate :command) :to-contain "jsonl")
      (expect (getf jsonl-gate :artifacts)
              :to-contain "cl-weave-events.jsonl")
      (expect watch-once-gate :not :to-be nil)
      (expect (getf watch-once-gate :command)
              :to-equal '("nix" "run" "." "--" "watch" "cl-weave/test"
                          "--once" "--reporter" "json" "--filter"
                          "filtering > runs only tests matching a path substring"
                          "--fail-with-no-tests" "--output" "cl-weave-watch-once.json"))
      (expect (getf watch-once-gate :timeout-seconds) :to-be 120)
      (expect (getf watch-once-gate :artifacts)
              :to-equal '("cl-weave-watch-once.json"))
      (expect junit-gate :not :to-be nil)
      (expect (getf junit-gate :command) :to-contain "junit")
      (expect (getf junit-gate :artifacts)
              :to-contain "cl-weave-junit.xml")))

  (it "keeps CI workflow contract synchronized with metadata"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (ci (getf metadata :continuous-integration))
           (workflow (read-text-file #P".github/workflows/ci.yml"))
           (action (read-text-file +nix-setup-action-path+)))
      (expect (probe-file (merge-pathnames (getf ci :workflow-path) (uiop:getcwd)))
              :not :to-be nil)
      (expect (probe-file (merge-pathnames +nix-setup-action-path+
                                           (uiop:getcwd)))
              :not :to-be nil)
      (expect workflow :to-contain "pull_request:")
      (expect workflow :to-contain "branches: [main]")
      (expect workflow :to-contain "workflow_dispatch:")
      ;; One system, named literally. flake.nix declares x86_64-linux alone, so
      ;; there is no matrix to resolve through and the workflow spells the
      ;; system out wherever it needs it.
      (expect workflow :to-contain "runs-on: ubuntu-latest")
      (expect workflow :not :to-contain "matrix.system")
      (dolist (system (getf ci :systems))
        (expect workflow :to-contain (format nil ".#checks.~A." system)))
      (expect workflow :to-contain
              (format nil "name: ~A" (getf ci :artifact-bundle)))
      ;; Nix/Cachix setup is delegated to the shared composite action, so the
      ;; cachix-action pin and the cache modes live there rather than inline.
      (expect workflow :to-contain "uses: ./.github/actions/nix-setup")
      (expect action :to-contain "uses: cachix/cachix-action@")
      (dolist (mode (getf ci :cache-modes))
        (expect action :to-contain mode))
      (expect (getf ci :quality-gate-source) :to-equal "qualityGates")
      (expect (getf metadata :quality-gates) :to-satisfy (function consp))))

  (it "hardens GitHub Actions workflow boundaries"
    (labels ((count-occurrences (needle haystack)
               (loop for start = (search needle haystack)
                       then (search needle haystack
                                    :start2 (+ start (length needle)))
                     while start
                     count t))
             (expected-cachix-action
                 (cache-present-p pull-request-p token-present-p)
               (cond
                 ((not cache-present-p) :disabled)
                 ((and (not pull-request-p) token-present-p) :push-enabled)
                 (t :pull-only))))
      (let ((ci (read-text-file #P".github/workflows/ci.yml"))
            (docs (read-text-file #P".github/workflows/docs.yml"))
            (action (read-text-file +nix-setup-action-path+)))
        ;; Every remote action -- across both workflows and the shared composite
        ;; action -- is pinned to an immutable 40-char SHA with a version comment.
        (dolist (source (list ci docs action))
          (let ((action-lines (workflow-remote-action-lines source)))
            (expect action-lines :to-satisfy (function consp))
            (dolist (line action-lines)
              (expect (workflow-action-immutably-pinned-p line) :to-be-truthy)
              (expect line :to-contain " # v"))))
        ;; Each workflow checks out without persisting credentials, delegates
        ;; Nix/Cachix setup to the one composite action, and gates the push token
        ;; on non-pull_request at the workflow boundary -- a local `./` action is
        ;; resolved from the PR head, so the gate must precede handing in the
        ;; token. Its only secret reference is that one forwarded input.
        (dolist (workflow (list ci docs))
          (let ((checkout (workflow-step-for-name workflow "Checkout"))
                (setup (workflow-step-for-name workflow "Set up Nix")))
            (expect checkout :not :to-be nil)
            (expect checkout :to-contain "persist-credentials: false")
            (expect setup :not :to-be nil)
            (expect setup :to-contain "uses: ./.github/actions/nix-setup")
            (expect setup
                    :to-contain
                    "cachix-auth-token: ${{ github.event_name != 'pull_request' && secrets.CACHIX_AUTH_TOKEN || '' }}"))
          (expect (count-occurrences "secrets.CACHIX_AUTH_TOKEN" workflow)
                  :to-be 1)
          ;; The Determinate Systems installer authenticates anonymously, so no
          ;; workflow hands a GitHub token to the PR-head-resolved local action.
          (expect (count-occurrences "secrets.GITHUB_TOKEN" workflow)
                  :to-be 0))
        ;; The composite action holds the pull-vs-push gating exactly once, in
        ;; terms of its own inputs, and never names a secret itself.
        (let ((selection (action-step-for-name action "Resolve Cachix mode"))
              (pull-cache
                (action-step-for-name action "Configure Cachix (pull-only)"))
              (push-cache
                (action-step-for-name action "Configure Cachix (push-enabled)")))
          (expect selection :not :to-be nil)
          (expect selection :to-contain "id: cachix-mode")
          (expect selection :to-contain "shell: bash")
          ;; Both the token and the event name are read from the step's own
          ;; environment rather than interpolated into the script body, so a
          ;; cache name containing shell metacharacters cannot escape into it.
          (expect selection
                  :to-contain
                  (format nil
                          "env:~%        CACHIX_AUTH_TOKEN: ${{ inputs.cachix-auth-token }}"))
          (expect selection
                  :to-contain
                  "CACHIX_CACHE: ${{ inputs.cachix-cache }}")
          (expect selection
                  :to-contain
                  "EVENT_NAME: ${{ github.event_name }}")
          (expect selection
                  :to-contain
                  "if [[ -n \"$CACHIX_AUTH_TOKEN\" && \"$EVENT_NAME\" != \"pull_request\" ]]; then")
          (expect selection
                  :to-contain
                  "printf 'push=%s\\n' \"$push\" >> \"$GITHUB_OUTPUT\"")
          (expect selection :not :to-contain "set -x")
          (expect (count-occurrences "\"$CACHIX_AUTH_TOKEN\"" selection)
                  :to-be 1)
          (expect (count-occurrences "\"$GITHUB_OUTPUT\"" selection)
                  :to-be 1)
          (expect pull-cache
                  :to-contain
                  "if: ${{ inputs.cachix-cache != '' && steps.cachix-mode.outputs.push != 'true' }}")
          (expect pull-cache :to-contain "skipPush: true")
          (expect pull-cache :not :to-contain "authToken:")
          (expect push-cache
                  :to-contain
                  "if: ${{ inputs.cachix-cache != '' && steps.cachix-mode.outputs.push == 'true' }}")
          (expect push-cache
                  :to-contain
                  "authToken: ${{ inputs.cachix-auth-token }}")
          (expect action :not :to-contain "secrets."))
        (dolist (row '((nil nil nil :disabled)
                       (nil t t :disabled)
                       (t t nil :pull-only)
                       (t t t :pull-only)
                       (t nil nil :pull-only)
                       (t nil t :push-enabled)))
          (destructuring-bind
              (cache-present-p pull-request-p token-present-p expected)
              row
            (expect (expected-cachix-action
                     cache-present-p pull-request-p token-present-p)
                    :to-be expected)))
        (expect (workflow-job-preamble ci "check") :not :to-contain "secrets.")
        (expect (workflow-job-preamble docs "build") :not :to-contain "secrets.")
        (expect docs :to-contain "permissions: {}")
        (let ((build (workflow-job-block docs "build"))
              (deploy (workflow-job-block docs "deploy")))
          (expect build :to-contain
                  (format nil "permissions:~%      contents: read"))
          (expect build :not :to-contain "pages: write")
          (expect build :not :to-contain "id-token: write")
          (expect deploy :to-contain "pages: write")
          (expect deploy :to-contain "id-token: write")
          (expect deploy :not :to-contain "contents: read")))))


  (it "keeps CI workflow quality gates synchronized with metadata"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (gates (getf metadata :quality-gates))
           (system (ci-declared-system (getf metadata :continuous-integration)))
           (workflow (read-text-file #P".github/workflows/ci.yml"))
           (flake-step (workflow-step-for-name workflow "Run flake checks"))
           (materialize-step
             (workflow-step-for-name workflow "Materialize check artifacts"))
           (artifact-section (workflow-artifact-section workflow)))
      (expect flake-step :not :to-be nil)
      (expect flake-step :to-contain "timeout 900s")
      (expect flake-step :to-contain "nix flake check --print-build-logs")
      (expect materialize-step :not :to-be nil)
      (expect materialize-step :to-contain "timeout 120s")
      (expect materialize-step :to-contain
              "nix build --no-link --print-out-paths")
      (expect workflow :not :to-contain "nix run . --")
      (dolist (gate gates)
        (let ((name (getf gate :name))
              (artifacts (getf gate :artifacts)))
          (when artifacts
            (expect materialize-step
                    :to-contain
                    (format nil ".#checks.~A.~A" system name))
            (dolist (artifact artifacts)
              (expect artifact-section :to-contain artifact)))))))

  (it "keeps flake checks synchronized with metadata quality gates"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (gate-names (sort (remove "flake-check"
                                     (mapcar (lambda (entry) (getf entry :name))
                                             (getf metadata :quality-gates))
                                     :test #'string=)
                             #'string<))
           (check-names (sort (remove "default"
                                      (flake-check-names
                                       (read-text-file #P"flake.nix"))
                                      :test #'string=)
                              #'string<)))
      (expect gate-names :to-equal check-names)))

  (it "keeps distribution channel metadata synchronized with README and flake packaging"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (channels (getf metadata :distribution-channels))
           (readme (read-text-file #P"README.md"))
           (flake (read-text-file #P"flake.nix"))
           (source-channel
             (find-metadata-entry :name "source-self-test" channels))
           (local-channel
             (find-metadata-entry :name "nix-local-cli" channels))
           (remote-channel
             (find-metadata-entry :name "nix-remote-cli" channels))
           (homepage (getf metadata :homepage))
           (github-prefix "https://github.com/")
           (remote-ref (concatenate 'string
                                    "github:"
                                    (subseq homepage (length github-prefix)))))
      (dolist (channel channels)
        (dolist (reference (getf channel :references))
          (expect (probe-file (merge-pathnames reference (uiop:getcwd)))
                  :not :to-be nil))
        (unless (null (getf channel :install-command))
          (expect (markdown-contains-command-p readme
                                               (getf channel :install-command))
                  :to-be t))
        (expect (markdown-contains-command-p readme
                                             (getf channel :run-command))
                :to-be t))
      (expect source-channel :not :to-be nil)
      (expect (getf source-channel :run-command)
              :to-equal '("nix" "run" "." "--" "run" "cl-weave/test"))
      (expect (probe-file #P"scripts/") :to-be nil)
      (expect local-channel :not :to-be nil)
      ;; `nix profile install .` and `nix run .` resolve `packages.default`
      ;; and `apps.default`, and the flake preset's defaults for both are the
      ;; ASDF SYSTEM, not a CLI. Losing that would leave the nix-local-cli
      ;; channel's documented commands installing and running something that
      ;; is not a command-line tool, so that is the property to hold.
      ;;
      ;; What holds it has changed twice, and the assertion has followed it
      ;; both times rather than the property being weakened. It was
      ;; `packages = forAllSystems` while the flake emitted every output by
      ;; hand; then `packages.default =`/`apps.default =` while the flake
      ;; overrode the preset's two defaults itself; it is `executable` now,
      ;; because cl-nix-forge's `mkPackageFlake` takes that argument and
      ;; generates BOTH attributes from it. There is no override line left to
      ;; find -- the guarantee moved from this file remembering to write one
      ;; into the preset, which is strictly stronger. Removing `executable`
      ;; is what would regress the channel, so that is the line to hold.
      (expect flake :to-contain "executable = {")
      ;; `mainProgram` is not decoration here. cl-nix-forge's `mkApp` derives
      ;; the app's `program` through `lib.getExe`, which reads exactly this
      ;; attribute, so this line is what makes `nix run .` start
      ;; `bin/cl-weave`. That subsumes the former assertion on a literal
      ;; `program = "${package}/bin/cl-weave";`, an attribute the flake no
      ;; longer writes by hand.
      (expect flake :to-contain "mainProgram = \"cl-weave\";")
      (expect remote-channel :not :to-be nil)
      (expect homepage :to-satisfy
              (lambda (value)
                (and (stringp value)
                     (string= github-prefix
                              (subseq value 0
                                      (min (length value)
                                           (length github-prefix)))))))
      (expect (getf remote-channel :install-command) :to-contain remote-ref)
      (expect (getf remote-channel :run-command) :to-contain remote-ref)))

  (it "keeps the distribution policy synchronized with distribution metadata"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (channels (getf metadata :distribution-channels))
           (readme (normalize-markdown-text
                    (read-text-file
                     (merge-pathnames #P"docs/src/index.md"
                                      (uiop:getcwd)))))
           (distribution-document-raw
             (read-text-file
              (merge-pathnames #P"docs/src/project/distribution-policy.md"
                               (uiop:getcwd))))
           (distribution-document (normalize-markdown-text
                                   distribution-document-raw))
           (ai-contract (normalize-markdown-text
                         (read-text-file
                          (merge-pathnames #P"docs/src/reference/ai-contract.md"
                                           (uiop:getcwd))))))
      (expect (getf metadata :policy-documents)
              :to-contain "docs/src/project/distribution-policy.md")
      (expect readme :to-contain "docs/src/project/distribution-policy.md")
      (expect distribution-document :to-contain "# Distribution Policy")
      (expect distribution-document :to-contain "distributionChannels")
      (expect distribution-document :to-contain "README.md")
      (expect distribution-document :to-contain "docs/src/reference/ai-contract.md")
      (expect distribution-document :to-contain "flake.nix")
      (expect distribution-document :to-contain "SBOMs")
      (expect distribution-document :to-contain "provenance attestations")
      (dolist (channel channels)
        (expect distribution-document :to-contain (getf channel :name))
        (dolist (reference (getf channel :references))
          (unless (string= reference "docs/src/project/distribution-policy.md")
            (expect distribution-document :to-contain reference)))
        (unless (null (getf channel :install-command))
          (expect (markdown-contains-command-p distribution-document-raw
                                               (getf channel :install-command))
                  :to-be t))
        (expect (markdown-contains-command-p distribution-document-raw
                                             (getf channel :run-command))
                :to-be t))
      (expect ai-contract :to-contain "docs/src/project/distribution-policy.md")))

  (it "keeps the packaged CLI safe for parallel ASDF loads"
    ;; `--coverage` recompiles the system under test, and the sources a
    ;; delivered image ships with are read-only, so its FASLs have to land in
    ;; a writable per-user cache and nothing in the environment may redirect
    ;; them back beside those sources -- two builds sharing one output
    ;; directory is how concurrent runs race on a FASL.
    ;;
    ;; This used to grep flake.nix for a save-lisp-and-die string. The logic
    ;; is src/cli-image.lisp's now, so the gate reads the configuration the
    ;; .asd's own declared entry point actually installs instead of asserting
    ;; that a build file still contains a particular sentence.
    (let ((translations (declared-image-output-translations "cl-weave")))
      (expect (first translations) :to-be :output-translations)
      (expect translations
              :to-contain '(t (:home ".cache" "common-lisp" :implementation)))
      (expect translations :to-contain :ignore-inherited-configuration)))

)
