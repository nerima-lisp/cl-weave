(in-package #:cl-weave/test)

(describe "cli metadata artifacts"
  (it "writes metadata artifacts through the CLI output option"
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
              (dolist (expected '("\"kind\":\"cl-weave-metadata\""
                                  "\"schemaVersion\":23"
                                  "\"artifactSchemas\"" "\"qualityGates\""
                                  "\"capabilityMatrix\"" "\"packageExports\""
                                  "\"policyDocuments\"" "\"referenceDocuments\""
                                  "\"distributionChannels\"" "\"supportChannels\""
                                  "\"communityHealth\"" "\"requiredSections\""
                                  "\"contactLinks\"" "\"securityContacts\""
                                  "\"lifecycle\"" "\"governance\""
                                  "\"runtimeSupport\"" "\"releaseProcess\""
                                  "\"continuousIntegration\""))
                (expect output :to-contain expected))))
        (when (probe-file output-file)
          (delete-file output-file))))
)
)
