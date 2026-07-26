(in-package #:cl-weave/test)

(describe "cli metadata artifacts"
  (it "writes AI metadata artifacts through the CLI output option"
    (let* ((output-file (test-temporary-pathname "cl-weave-metadata.json"))
           (options (parse-cli (list "metadata"
                           "--reporter" "json"
                           "--output" (namestring output-file)))))
      (when (probe-file output-file)
        (delete-file output-file))
      (unwind-protect
           (progn
             (expect (with-output-to-string (*standard-output*)
                       (cl-weave/cli::run-command options))
                     :to-equal "")
             (let ((output (read-text-file output-file)))
               (define-metadata-contract-tests
                output
                "\"kind\":\"cl-weave-metadata\"" "\"schemaVersion\":23"
                "\"artifactSchemas\"" "\"qualityGates\"" "\"capabilityMatrix\""
                "\"packageExports\"" "\"policyDocuments\"" "\"referenceDocuments\""
                "\"distributionChannels\"" "\"supportChannels\""
                "\"communityHealth\"" "\"requiredSections\"" "\"contactLinks\""
                "\"purpose\":\"Check whether the request belongs in issue tracking and what detail is required.\""
                "\"securityContacts\"" "\"lifecycle\"" "\"governance\""
                "\"runtimeSupport\"" "\"releaseProcess\"" "\"continuousIntegration\"")))
        (when (probe-file output-file)
          (delete-file output-file))))
)
)
