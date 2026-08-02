(in-package #:cl-weave/test)

(describe "cli metadata rendering"
  (it "prints AI-friendly framework metadata"
    (let ((options (parse-cli '("metadata" "cl-weave/test"))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :metadata)
      (expect (cl-weave/cli::cli-options-systems options)
              :to-equal '("cl-weave/test"))
      (let ((output (framework-metadata-output options)))
        (expect-text-contract
         output
         '("\"kind\":\"cl-weave-metadata\"" "\"schemaVersion\":23"
           "\"homepage\"" "\"bugTracker\"" "\"commands\"" "\"metadata\""
           "\"artifactSchemas\"" "\"kind\":\"test-results\"" "\"schemaVersion\":6"
           "\"fields\"" "\"name\":\"events\"" "\"kind\":\"array\"" "\"required\":true"
           "\"kind\":\"test-plan\"" "\"schemaVersion\":2" "\"streaming\":true"
           "\"qualityGates\"" "\"capabilityMatrix\""
           "\"distributionChannels\"" "\"name\":\"source-self-test\"" "\"installCommand\":[]"
           "\"runCommand\":[\"nix\",\"run\",\".\",\"--\",\"run\",\"cl-weave\\/test\"]"
           "\"governance\"" "\"policyDocument\":\"docs\\/src\\/project\\/governance.md\""
           "\"reviewOwnership\":\".github\\/CODEOWNERS\"" "\"maintainerResponsibilities\""
           "\"decisionDocuments\"" "\"name\":\"vitest-dsl\"" "\"publicApis\""
           "\"qualityGates\":[\"flake-check\",\"filtered-smoke\",\"plan-artifact\"]"
           "\"documentation\":[\"README.md\",\"docs\\/src\\/reference\\/ai-contract.md\"]" "\"name\":\"flake-check\""
           "\"command\":[\"nix\",\"flake\",\"check\",\"--print-build-logs\"]" "\"timeoutSeconds\":900"
           "\"name\":\"ai-metadata-artifact\"" "\"cl-weave-metadata.json\"" "\"name\":\"tap-artifact\""
           "\"Verify TAP output for line-oriented CI logs.\"" "\"name\":\"filtered-smoke\""
           "\"nix\",\"run\",\".\",\"--\",\"run\",\"cl-weave\\/test\",\"--filter\",\"filtering > runs only tests matching a path substring\",\"--fail-with-no-tests\""
           "\"options\"" "\"listReporters\"" "\"valueKind\"" "\"commandChoices\""
           "\"name\":\"--reporter\"" "\"command\":\"metadata\"" "\"choices\":[\"json\",\"sexp\"]"
           "\"--filter\"" "\"CL_WEAVE_TEST_FILTER\"" "\"--update-snapshots\"" "\"matchers\""
           "\"to-be-even\"" "\"mutationOperators\"" "\"arithmetic-operator\"" "\"packageExports\""
           "\"cl-weave\"" "\"DESCRIBE\"" "\"EXPECT\"" "\"expect-has-assertions\"")
         '("\"--testNamePattern\"" "\"--updateSnapshots\"" "\"vitestAliases\"")))))

  (it "allows Lisp-native metadata output"
    (let ((options (parse-cli '("metadata" "--reporter" "sexp"))))
      (let ((output (framework-metadata-output options)))
        (expect output :to-contain ":KIND \"cl-weave-metadata\"")
        (expect output :to-contain ":OPTIONS")
        (expect output :to-contain ":PACKAGE-EXPORTS"))))

)
