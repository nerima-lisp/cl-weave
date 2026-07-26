(in-package #:cl-weave/test)

(defun expect-text-contract (text required &optional forbidden)
  (dolist (fragment required)
    (expect text :to-contain fragment))
  (dolist (fragment forbidden)
    (expect text :not :to-contain fragment)))

(defmacro define-metadata-contract-tests (value &rest required-fragments)
  `(expect-text-contract ,value ',required-fragments))

(defun expect-json-field-contracts-documented (document field-tables)
  (dolist (fields field-tables)
    (dolist (field fields)
      (destructuring-bind (metadata-key json-key writer) field
        (declare (ignore metadata-key writer))
        (expect document :to-contain json-key)))))

(in-package #:cl-weave/test)

;; Proclaimed special so the compile-time references below do not raise
;; undefined-variable warnings.  The values are installed at run time by the
;; define-json-plist-*-schema/endpoint macros (invoked under EVAL inside the
;; test), and stray compile warnings would otherwise leak onto the
;; *error-output* captured by the "preserves Unicode isolated output" test.
(defvar *coverage-fuzz-array-schema-fields*)
(defvar *coverage-fuzz-object-schema-fields*)
(defvar *coverage-fuzz-endpoint-fields*)

(describe "cli metadata schema contracts"
  (it "keeps the AI contract synchronized with metadata root fields"
    (let ((docs (read-text-file (merge-pathnames #P"docs/src/ai-contract.md"
                                                 (uiop:getcwd)))))
      (expect-json-field-contracts-documented
       docs
       (list cl-weave/metadata::*framework-metadata-json-fields*
             cl-weave/metadata::*json-capability-matrix-fields*
             cl-weave/metadata::*json-reference-document-fields*
             cl-weave/metadata::*json-distribution-channel-fields*
             cl-weave/metadata::*json-community-health-fields*
             cl-weave/metadata::*json-community-health-contact-link-fields*
             cl-weave/metadata::*json-governance-fields*
             cl-weave/metadata::*json-continuous-integration-fields*))))

  (it "keeps the AI contract example version synchronized with the CLI version"
    (let* ((docs (read-text-file (merge-pathnames #P"docs/src/ai-contract.md"
                                                  (uiop:getcwd))))
           (version (cl-weave/cli::cli-version)))
      (expect version :not :to-equal "unknown")
      (expect docs :to-contain (format nil "\"version\": \"~A\"" version))))

  (it "generates working writers from every json-plist definition macro"
    (eval '(cl-weave/metadata::define-json-plist-array-writer
            coverage-fuzz-array-writer
            '((:value "value" cl-weave/metadata::write-json-string-value))))
    (expect (with-output-to-string (stream)
              (funcall 'coverage-fuzz-array-writer '((:value "a") (:value "b")) stream))
            :to-equal "[{\"value\":\"a\"},{\"value\":\"b\"}]")

    (eval '(cl-weave/metadata::define-json-plist-object-writer
            coverage-fuzz-object-writer
            '((:value "value" cl-weave/metadata::write-json-string-value))))
    (expect (with-output-to-string (stream)
              (funcall 'coverage-fuzz-object-writer '(:value "a") stream))
            :to-equal "{\"value\":\"a\"}")

    (eval '(cl-weave/metadata::define-json-plist-array-schema
            *coverage-fuzz-array-schema-fields*
            coverage-fuzz-array-schema-writer
            '((:value "value" cl-weave/metadata::write-json-string-value))))
    (expect *coverage-fuzz-array-schema-fields* :not :to-be nil)
    (expect (with-output-to-string (stream)
              (funcall 'coverage-fuzz-array-schema-writer '((:value "a")) stream))
            :to-equal "[{\"value\":\"a\"}]")

    (eval '(cl-weave/metadata::define-json-plist-object-schema
            *coverage-fuzz-object-schema-fields*
            coverage-fuzz-object-schema-writer
            '((:value "value" cl-weave/metadata::write-json-string-value))))
    (expect *coverage-fuzz-object-schema-fields* :not :to-be nil)
    (expect (with-output-to-string (stream)
              (funcall 'coverage-fuzz-object-schema-writer '(:value "a") stream))
            :to-equal "{\"value\":\"a\"}")

    (eval '(cl-weave/metadata::define-json-plist-object-endpoint
            *coverage-fuzz-endpoint-fields*
            coverage-fuzz-endpoint-field-writer
            coverage-fuzz-endpoint-emitter
            record
            '((:value "value" cl-weave/metadata::write-json-string-value))))
    (expect *coverage-fuzz-endpoint-fields* :not :to-be nil)
    (expect (with-output-to-string (stream)
              (funcall 'coverage-fuzz-endpoint-emitter '(:value "a") stream))
            :to-equal (format nil "{\"value\":\"a\"}~%")))

  (it "keeps the AI contract release-process example synchronized with metadata"
    (let* ((docs (read-text-file (merge-pathnames #P"docs/src/ai-contract.md"
                                                  (uiop:getcwd))))
           (normalized-docs (normalize-markdown-text docs))
           (metadata (getf (cl-weave/metadata:framework-metadata) :release-process)))
      (expect normalized-docs
              :to-contain
              (normalize-markdown-text
               (format nil "\"policyDocument\": \"~A\"" (getf metadata :policy-document))))
      (expect normalized-docs
              :to-contain
              (normalize-markdown-text
               (format nil "\"releaseStage\": \"~A\"" (getf metadata :release-stage))))
      (dolist (item (getf metadata :checklist))
        (expect normalized-docs
                :to-contain
                (normalize-markdown-text item)))
      (dolist (item (getf metadata :contract-sync-requirements))
        (expect normalized-docs
                :to-contain
                (normalize-markdown-text item)))))

)
