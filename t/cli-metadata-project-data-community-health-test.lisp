(in-package #:cl-weave/test)

(defun expect-document-fragments (document fragments &key normalize)
  (dolist (fragment fragments)
    (expect document
            :to-contain
            (if normalize
                (normalize-markdown-text fragment)
                fragment))))

(defun expect-document-without-fragments (document fragments &key normalize)
  (dolist (fragment fragments)
    (expect document
            :not :to-contain
            (if normalize
                (normalize-markdown-text fragment)
                fragment))))

(defmacro define-document-contract-tests (&body contracts)
  `(progn
     ,@(loop for contract in contracts
             for name = (first contract)
             for documents = (getf (rest contract) :documents)
             for existing = (getf (rest contract) :existing)
             for required = (getf (rest contract) :required)
             for forbidden = (getf (rest contract) :forbidden)
             collect
             `(it ,name
                (let ,(loop for (variable path . options) in documents
                            collect
                            `(,variable
                              ,(if (getf options :normalize)
                                   `(normalize-markdown-text
                                     (read-text-file
                                      (merge-pathnames ,path (uiop:getcwd))))
                                   `(read-text-file
                                     (merge-pathnames ,path (uiop:getcwd))))))
                  ,@(when existing
                      `((dolist (path ',existing)
                          (expect (probe-file
                                   (merge-pathnames path (uiop:getcwd)))
                                  :not :to-be nil))))
                  ,@(loop for (variable fragments) in required
                          for document = (assoc variable documents)
                          collect
                          `(expect-document-fragments
                            ,variable ',fragments
                            :normalize ,(not (null (getf (cddr document)
                                                        :normalize)))))
                  ,@(loop for (variable fragments) in forbidden
                          for document = (assoc variable documents)
                          collect
                          `(expect-document-without-fragments
                            ,variable ',fragments
                            :normalize ,(not (null (getf (cddr document)
                                                        :normalize))))))))))

(describe "community health"
  (define-document-contract-tests
    ("keeps OSS operations documents discoverable"
     :documents ((readme #P"docs/src/index.md"))
     :existing ("LICENSE" ".github/ISSUE_TEMPLATE/bug_report.md"
                ".github/ISSUE_TEMPLATE/feature_request.md"
                ".github/ISSUE_TEMPLATE/config.yml"
                ".github/pull_request_template.md" ".github/CODEOWNERS"
                "docs/src/project/community-health.md")
     :required ((readme ("LICENSE"
                         ".github/ISSUE_TEMPLATE/bug_report.md"
                         ".github/ISSUE_TEMPLATE/feature_request.md"
                         ".github/ISSUE_TEMPLATE/config.yml"
                         ".github/pull_request_template.md" ".github/CODEOWNERS"
                         "docs/src/project/community-health.md" "docs/src/project/governance.md"))))
    ("keeps maintenance and versioning policies aligned with release expectations"
     :documents ((maintenance-document #P"docs/src/project/maintenance-policy.md" :normalize t)
                 (versioning-document #P"docs/src/project/versioning-policy.md" :normalize t))
     :required ((maintenance-document ("public-surface discipline"
                                       "migration steps" "user-visible changes"))
                (versioning-document ("additive only" "behavior-preserving"
                                      "intentionally breaking")))))

  (it "keeps license contracts synchronized with repository metadata"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (reference-documents (getf metadata :reference-documents))
           (license-entry
             (find-metadata-entry :path "LICENSE" reference-documents))
           (license-document (read-text-file
                              (merge-pathnames #P"LICENSE"
                                               (uiop:getcwd)))))
      (expect license-entry :not :to-be nil)
      (expect (probe-file (merge-pathnames "LICENSE" (uiop:getcwd)))
              :not :to-be nil)
      (expect license-document :to-contain "MIT License")
      (expect license-document :to-contain "takeokunn")))

  (it "keeps the community health contract synchronized with GitHub intake files"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (entries (getf metadata :community-health))
           (document (normalize-markdown-text
                      (read-text-file
                       (merge-pathnames #P"docs/src/project/community-health.md"
                                        (uiop:getcwd))))))
      (expect (getf metadata :policy-documents)
              :to-contain "docs/src/project/community-health.md")
      (expect document :to-contain "# Community Health")
      (dolist (entry entries)
        (expect (probe-file (merge-pathnames (getf entry :path) (uiop:getcwd)))
                :not :to-be nil)
        (expect document :to-contain (getf entry :path))
        (dolist (reference (getf entry :references))
          (expect (probe-file (merge-pathnames reference (uiop:getcwd)))
                  :not :to-be nil)
          (unless (string= reference "docs/src/project/community-health.md")
            (expect document :to-contain reference)))
        (let ((entry-text (normalize-markdown-text
                           (read-text-file
                            (merge-pathnames (getf entry :path)
                                             (uiop:getcwd))))))
          (dolist (section (getf entry :required-sections))
            (expect entry-text
                    :to-contain
                    (normalize-markdown-text
                     (format nil "# ~A" section))))
          (dolist (link (getf entry :contact-links))
            (expect entry-text :to-contain (getf link :name))
            (expect entry-text :to-contain (getf link :target)))))))

  (it "keeps support and security routing synchronized with public intake surfaces"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (homepage (getf metadata :homepage))
           (policy-documents (getf metadata :policy-documents))
           (reference-documents (getf metadata :reference-documents))
           (support-channels (getf metadata :support-channels))
           (security-contacts (getf metadata :security-contacts))
           (readme (normalize-markdown-text
                    (read-text-file
                     (merge-pathnames #P"docs/src/index.md"
                                      (uiop:getcwd)))))
           (support-document (normalize-markdown-text
                              (read-text-file
                               (merge-pathnames #P"docs/src/project/support-policy.md"
                                                (uiop:getcwd)))))
           (issue-guide (normalize-markdown-text
                         (read-text-file
                          (merge-pathnames #P"docs/src/project/issue-reporting.md"
                                           (uiop:getcwd)))))
           (issue-config (read-text-file
                          (merge-pathnames #P".github/ISSUE_TEMPLATE/config.yml"
                                           (uiop:getcwd))))
           (support-policy-url (format nil "~A/blob/main/docs/src/project/support-policy.md"
                                       homepage))
           (security-reporting-url (format nil "~A/security/advisories/new"
                                           homepage)))
      (dolist (path policy-documents)
        (expect (probe-file (merge-pathnames path (uiop:getcwd)))
                :not :to-be nil)
        (expect readme :to-contain path))
      (dolist (entry reference-documents)
        (let ((path (getf entry :path)))
          (expect (probe-file (merge-pathnames path (uiop:getcwd)))
                  :not :to-be nil)
          (unless (string= path "README.md")
            (expect readme :to-contain path))))
      (dolist (channel support-channels)
        (expect (getf channel :target) :not :to-be nil)
        (case (intern (string-upcase (getf channel :name)) :keyword)
          (:ISSUE-TRACKER
           (expect readme :to-contain (getf channel :target))
           (expect support-document :to-contain "Use the issue tracker")
           (expect issue-guide :to-contain "Use this guide when filing bugs")
           (expect issue-guide :to-contain "support-policy.md"))
          (:PULL-REQUESTS
           (expect readme :to-contain (getf channel :target))
           (expect support-document :to-contain "Use pull requests"))
          (:SUPPORT-POLICY
           (expect readme :to-contain (getf channel :target))
           (expect (probe-file (merge-pathnames (getf channel :target)
                                                (uiop:getcwd)))
                   :not :to-be nil)
           (expect issue-config :to-contain "name: Support policy")
           (expect issue-config :to-contain support-policy-url)
           (expect issue-config
                   :to-contain
                   "about: Check whether the request belongs in issue tracking and what detail is required."))))
      (dolist (entry security-contacts)
        (expect (getf entry :target) :to-equal security-reporting-url)
        (expect readme :to-contain (getf entry :target))
        (expect support-document :to-contain "Use private security reporting")
        (expect issue-guide :to-contain "security process")
        (expect issue-guide :to-contain security-reporting-url)
        (expect issue-config :to-contain "name: Security reporting")
        (expect issue-config :to-contain security-reporting-url)
        (expect issue-config
                :to-contain
                "about: Report vulnerabilities through the private security contact path."))))

  (it "keeps issue reporting guidance synchronized with bug intake contracts"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (community-health (getf metadata :community-health))
           (bug-report-entry
             (find-metadata-entry :name "bug-report-form" community-health))
           (issue-guide (normalize-markdown-text
                         (read-text-file
                          (merge-pathnames #P"docs/src/project/issue-reporting.md"
                                           (uiop:getcwd)))))
           (support-document (normalize-markdown-text
                              (read-text-file
                               (merge-pathnames #P"docs/src/project/support-policy.md"
                                                (uiop:getcwd)))))
           (community-document (normalize-markdown-text
                                (read-text-file
                                 (merge-pathnames #P"docs/src/project/community-health.md"
                                                  (uiop:getcwd)))))
           (bug-template (normalize-markdown-text
                          (read-text-file
                           (merge-pathnames #P".github/ISSUE_TEMPLATE/bug_report.md"
                                            (uiop:getcwd))))))
      (expect bug-report-entry :not :to-be nil)
      (expect (getf metadata :policy-documents)
              :to-contain "docs/src/project/issue-reporting.md")
      (expect issue-guide :to-contain "# Issue Reporting Guide")
      (expect issue-guide :to-contain "support-policy.md")
      (expect issue-guide :to-contain "security process")
      (expect issue-guide :to-contain "security/advisories/new")
      (dolist (detail '("The exact command you ran."
                        "The `cl-weave` version or commit if you are testing a local checkout."
                        "The Common Lisp implementation and version."
                        "Your operating system and shell if the issue touches the CLI."
                        "The expected result and the actual result."
                        "The smallest reproducer you can provide."
                        "Any machine-readable metadata or reporter output that shows the failure."))
        (expect issue-guide
                :to-contain
                (normalize-markdown-text detail)))
      (dolist (detail '("exact command or API entrypoint"
                        "version or commit"
                        "implementation and runtime details"
                        "operating system and shell, when relevant"
                        "expected behavior"
                        "actual behavior"
                        "smallest reproduction you can provide"))
        (expect support-document :to-contain (normalize-markdown-text detail)))
      (expect community-document :to-contain "docs/src/project/issue-reporting.md")
      (dolist (section (getf bug-report-entry :required-sections))
        (expect bug-template
                :to-contain
                (normalize-markdown-text
                 (format nil "# ~A" section))))
      (expect bug-template :to-contain "docs/src/project/issue-reporting.md")
      (expect bug-template :to-contain "canonical reproduction details")))

  (it "keeps pull request intake guidance synchronized with PR contracts"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (community-health (getf metadata :community-health))
           (pr-entry
             (find-metadata-entry :name "pull-request-template" community-health))
           (community-document (normalize-markdown-text
                                (read-text-file
                                 (merge-pathnames #P"docs/src/project/community-health.md"
                                                  (uiop:getcwd)))))
           (triage-document (normalize-markdown-text
                             (read-text-file
                              (merge-pathnames #P"docs/src/project/triage-policy.md"
                                               (uiop:getcwd)))))
           (release-document (normalize-markdown-text
                              (read-text-file
                               (merge-pathnames #P"docs/src/project/release-process.md"
                                                (uiop:getcwd)))))
           (pr-guidance (normalize-markdown-text
                         (read-text-file
                          (merge-pathnames #P"docs/src/project/pull-request-template.md"
                                           (uiop:getcwd)))))
           (pr-template (normalize-markdown-text
                         (read-text-file
                          (merge-pathnames #P".github/pull_request_template.md"
                                           (uiop:getcwd))))))
      (expect pr-entry :not :to-be nil)
      (expect community-document :to-contain "docs/src/project/pull-request-template.md")
      (expect triage-document :to-contain "Keep PRs narrowly scoped when possible.")
      (expect triage-document :to-contain "Include tests for any behavior change")
      (expect triage-document :to-contain "Call out compatibility impact explicitly")
      (expect triage-document
              :to-contain
              "Link to the relevant issue, policy, or contract document")
      (expect release-document :to-contain "docs/src/project/pull-request-template.md")
      (expect release-document :to-contain ".github/pull_request_template.md")
      (expect release-document :to-contain "follow-up risk")
      (dolist (section (getf pr-entry :required-sections))
        (let ((heading (normalize-markdown-text
                        (format nil "# ~A" section))))
          (expect pr-template :to-contain heading)
          (expect pr-guidance :to-contain heading)))
      (expect pr-guidance :to-contain "## Related Issue Or Policy")
      (expect pr-guidance :to-contain "## Notes For Reviewers")
      (expect pr-template :to-contain "docs/src/project/pull-request-template.md")))

  (it "keeps runtime support metadata synchronized with published support docs"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (runtime-support (getf metadata :runtime-support))
           (readme (read-text-file #P"docs/src/getting-started.md"))
           (runtime-document (read-text-file #P"docs/src/reference/runtime-support.md")))
      (expect (getf metadata :policy-documents)
              :to-contain "docs/src/reference/runtime-support.md")
      (expect (getf runtime-support :policy-document)
              :to-equal "docs/src/reference/runtime-support.md")
      (expect readme :to-contain "## Supported Runtime")
      (expect readme :to-contain "[Runtime Support](reference/runtime-support.md)")
      (expect readme :to-contain (getf runtime-support :primary-implementation))
      (expect readme :to-contain "Linux")
      (expect readme :to-contain "subprocess isolation")
      (expect readme :to-contain "coverage handling")
      (expect runtime-document
              :to-contain (getf runtime-support :primary-implementation))
      (dolist (entry (getf runtime-support :supported-targets))
        (expect runtime-document :to-contain (getf entry :implementation))
        (expect runtime-document :to-contain (getf entry :status))
        (dolist (platform (getf entry :platforms))
          (expect runtime-document :to-contain platform)))
      (dolist (entry (getf runtime-support :best-effort-targets))
        (expect runtime-document :to-contain (getf entry :implementation))
        (expect runtime-document :to-contain (getf entry :status))
        (dolist (platform (getf entry :platforms))
          (if (string= platform "implementation-dependent")
              (progn
                (expect runtime-document
                        :to-contain
                        "Other Common Lisp implementations may work")
                (expect runtime-document :to-contain "best-effort"))
              (expect runtime-document :to-contain platform))))
      (dolist (feature (getf runtime-support :implementation-specific-features))
        (expect runtime-document
                :to-contain
                (cond ((string= feature "it-isolated subprocess execution")
                       "`it-isolated` subprocess execution")
                      ((string= feature
                                "MOP-dependent metadata and structural assertions")
                       "some MOP-dependent metadata and structural assertions")
                      (t
                       feature))))))

  (it "keeps the governance document aligned with maintainer operations"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (governance (getf metadata :governance))
           (document (normalize-markdown-text
                      (read-text-file
                       (merge-pathnames #P"docs/src/project/governance.md"
                                        (uiop:getcwd)))))
           (codeowners (read-text-file
                        (merge-pathnames (getf governance :review-ownership)
                                         (uiop:getcwd)))))
      (expect (getf metadata :policy-documents) :to-contain "docs/src/project/governance.md")
      (expect (getf governance :policy-document) :to-equal "docs/src/project/governance.md")
      (expect (getf governance :review-ownership)
              :to-equal ".github/CODEOWNERS")
      (expect (probe-file (merge-pathnames (getf governance :review-ownership)
                                           (uiop:getcwd)))
              :not :to-be nil)
      (expect codeowners :to-contain "@")
      (expect document :to-contain "# Governance")
      (dolist (path (append (mapcar (lambda (path)
                                      (subseq path (1+ (or (position #\/ path :from-end t)
                                                           -1))))
                                    (getf governance :decision-documents))
                            '("../.github/CODEOWNERS")))
        (expect document :to-contain path))
      (expect-document-fragments
       document
       '("triaging issues and pull requests against"
         "support-policy.md"
         "versioning-policy.md"
         "machine-readable metadata, release notes, and policy documents in sync"
         "regression coverage for public-surface changes"
         "private reporting path"
         "Maintainers cut releases from the validated default branch state only."
         "If the active maintainer set changes"
         "machine-readable metadata in the same patch."
         "public CLI behavior"
         "reporter shapes"
         "exported symbols"))
      (expect-document-fragments codeowners '("*" "@"))))

  (it "keeps the release-process document synchronized with release metadata"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (release-process (getf metadata :release-process))
           (document (normalize-markdown-text
                      (read-text-file
                       (merge-pathnames (getf release-process :policy-document)
                                        (uiop:getcwd))))))
      (expect document :to-contain "# Release Process")
      (dolist (item (getf release-process :checklist))
        (expect document :to-contain (normalize-markdown-text item)))
      (dolist (item (getf release-process :contract-sync-requirements))
        (expect document :to-contain (normalize-markdown-text item)))))

  (it "keeps lifecycle metadata synchronized with compatibility policies"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (lifecycle (getf metadata :lifecycle))
           (support-document (normalize-markdown-text
                              (read-text-file
                               (merge-pathnames (getf lifecycle :support-document)
                                                (uiop:getcwd)))))
           (versioning-document (normalize-markdown-text
                                 (read-text-file
                                  (merge-pathnames (getf lifecycle :versioning-document)
                                                   (uiop:getcwd)))))
           (maintenance-document (normalize-markdown-text
                                  (read-text-file
                                   (merge-pathnames #P"docs/src/project/maintenance-policy.md"
                                                    (uiop:getcwd)))))
           (ai-contract (read-text-file
                         (merge-pathnames #P"docs/src/reference/ai-contract.md"
                                          (uiop:getcwd)))))
      (expect (getf metadata :policy-documents)
              :to-contain (getf lifecycle :support-document))
      (expect (getf metadata :policy-documents)
              :to-contain (getf lifecycle :versioning-document))
      (expect (getf metadata :policy-documents)
              :to-contain "docs/src/project/maintenance-policy.md")
      (expect support-document :to-contain "release-process.md")
      (expect support-document :to-contain "versioning-policy.md")
      (expect support-document :to-contain "pull-request-template.md")
      (expect support-document :to-contain "runtime-support.md")
      (expect versioning-document :to-contain (getf lifecycle :stage))
      (expect versioning-document :to-contain "breaking changes")
      (expect versioning-document :to-contain "reporter shape")
      (expect versioning-document :to-contain "release-process.md")
      (expect versioning-document :to-contain "maintenance-policy.md")
      (expect maintenance-document
              :to-contain
              "current development line is the primary support target")
      (expect maintenance-document :to-contain "support boundaries")
      (expect maintenance-document :to-contain "versioning policy")
      (expect maintenance-document :to-contain "community-health.md")
      (expect maintenance-document :to-contain "release-process.md")
      (expect ai-contract :to-contain "\"lifecycle\": {")
      (expect ai-contract
              :to-contain
              (format nil "\"stage\": \"~A\"" (getf lifecycle :stage)))
      (expect ai-contract
              :to-contain
              (format nil "\"supportedLine\": \"~A\""
                      (getf lifecycle :supported-line)))
      (expect ai-contract
              :to-contain
              (format nil "\"supportDocument\": \"~A\""
                      (getf lifecycle :support-document)))
      (expect ai-contract
              :to-contain
              (format nil "\"versioningDocument\": \"~A\""
                      (getf lifecycle :versioning-document))))))
