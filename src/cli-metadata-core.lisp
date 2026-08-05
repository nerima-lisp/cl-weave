(in-package #:cl-weave/metadata)

(declaim
 (special *metadata-cli-options*
          *metadata-extra-environment-variables*
          *metadata-commands*
          *metadata-quality-gates*
          *metadata-capabilities*
          *metadata-capability-matrix*
          *metadata-policy-documents*
          *metadata-reference-documents*
          *metadata-distribution-channels*
          *metadata-support-channels*
          *metadata-community-health*
          *metadata-security-contacts*
          *metadata-lifecycle*
          *metadata-governance*
          *metadata-runtime-support*
          *metadata-release-process*
          *metadata-continuous-integration*))

(defun reporter-keyword-names (reporters)
  (mapcar (lambda (reporter)
            (string-downcase (symbol-name reporter)))
          reporters))

(defun metadata-run-reporters ()
  (reporter-keyword-names (cl-weave:run-reporters)))

(defun metadata-list-reporters ()
  (reporter-keyword-names (cl-weave:list-reporters)))

(defun metadata-output-reporters ()
  '("json" "sexp"))

(defmacro define-metadata-plist-accessors (&rest specifications)
  `(progn
     ,@(loop for (name key) in specifications
             collect `(defun ,name (entry)
                        (getf entry ,key)))))

(define-metadata-plist-accessors
  (metadata-entry-name :name)
  (metadata-entry-argument :argument)
  (metadata-entry-description :description)
  (metadata-entry-choices :choices)
  (metadata-entry-command-choices :command-choices)
  (metadata-entry-environment :environment))

(defun metadata-reporter-command-choices ()
  (let ((run-reporters (metadata-run-reporters))
        (list-reporters (metadata-list-reporters)))
    `(("run" ,run-reporters)
      ("watch" ,run-reporters)
      ("list" ,list-reporters)
      ("doctor" ,(metadata-output-reporters))
      ("metadata" ,(metadata-output-reporters)))))

(defun cli-option-usage-name (name argument)
  (if argument
      (format nil "~A ~A" name argument)
      name))

(defun cli-option-usage-label (entry)
  (cli-option-usage-name (metadata-entry-name entry)
                         (metadata-entry-argument entry)))

(defun cli-option-usage-lines (entry)
  (let* ((label (format nil "  ~A" (cli-option-usage-label entry)))
         (description (metadata-entry-description entry))
         (description-column 30))
    (if (< (length label) description-column)
        (list (format nil "~A~VT~A" label description-column description))
        (list label
              (format nil "~VT~A" description-column description)))))

(defun materialized-metadata-cli-option (entry)
  (let ((copy (copy-list entry)))
    (when (eq (metadata-entry-choices copy) :run-reporters)
      (setf (getf copy :choices) (metadata-run-reporters)))
    (when (eq (metadata-entry-command-choices copy)
              :reporter-command-choices)
      (setf (getf copy :command-choices) (metadata-reporter-command-choices)))
    copy))

(defun metadata-cli-options ()
  (mapcar #'materialized-metadata-cli-option *metadata-cli-options*))

(defun metadata-environment-variables ()
  (sort (remove-duplicates
         (append *metadata-extra-environment-variables*
                  (loop for entry in (metadata-cli-options)
                        append (metadata-entry-environment entry)))
         :test #'string=)
        #'string<))

(defun metadata-system ()
  (ignore-errors (asdf:find-system "cl-weave" nil)))

(defun cli-version ()
  (or (ignore-errors
        (let ((system (metadata-system)))
          (and system (asdf:component-version system))))
      "unknown"))

(defmacro define-framework-system-reader (name accessor)
  `(defun ,name ()
     (let ((system (metadata-system)))
       (and system (,accessor system)))))

(define-framework-system-reader framework-homepage asdf:system-homepage)
(define-framework-system-reader framework-bug-tracker asdf:system-bug-tracker)
(define-framework-system-reader framework-license asdf:system-license)

(defun package-export-metadata (package-designator)
  (let ((package (or (find-package package-designator)
                     (error "Unknown metadata package: ~A" package-designator))))
    (list :name (string-downcase (package-name package))
          :exports
          (sort (loop for symbol being the external-symbols of package
                      collect (symbol-name symbol))
                #'string<))))

(defmacro define-metadata-readers (&rest readers)
  `(progn
     ,@(loop for (name variable) in readers
             collect `(defun ,name () ,variable))))

(define-metadata-readers
  (metadata-policy-documents *metadata-policy-documents*)
  (metadata-reference-documents *metadata-reference-documents*)
  (metadata-distribution-channels *metadata-distribution-channels*)
  (metadata-support-channels *metadata-support-channels*)
  (metadata-community-health *metadata-community-health*)
  (metadata-security-contacts *metadata-security-contacts*)
  (metadata-lifecycle *metadata-lifecycle*)
  (metadata-governance *metadata-governance*)
  (metadata-runtime-support *metadata-runtime-support*)
  (metadata-release-process *metadata-release-process*)
  (metadata-continuous-integration *metadata-continuous-integration*))

(defun framework-metadata-core ()
  (list
   :kind "cl-weave-metadata"
   :schema-version 23
   :homepage (framework-homepage)
   :bug-tracker (framework-bug-tracker)
   :license (framework-license)
   :version (cli-version)
   :commands *metadata-commands*
   :reporters (metadata-run-reporters)
   :list-reporters (metadata-list-reporters)
   :artifact-schemas (cl-weave:reporter-artifact-schemas)
   :quality-gates *metadata-quality-gates*
   :capabilities *metadata-capabilities*
   :capability-matrix *metadata-capability-matrix*
   :environment (metadata-environment-variables)
   :options (metadata-cli-options)))

(defun framework-metadata-documentation ()
  (list
   :policy-documents (metadata-policy-documents)
   :reference-documents (metadata-reference-documents)))

(defun framework-metadata-community ()
  (list
   :distribution-channels (metadata-distribution-channels)
   :support-channels (metadata-support-channels)
   :community-health (metadata-community-health)
   :security-contacts (metadata-security-contacts)))

(defun framework-metadata-maintenance ()
  (list
   :lifecycle (metadata-lifecycle)
   :governance (metadata-governance)
   :runtime-support (metadata-runtime-support)
   :release-process (metadata-release-process)
   :continuous-integration (metadata-continuous-integration)))

(defun framework-metadata-ecosystem ()
  (list
   :package-exports (list (package-export-metadata :cl-weave)
                          (package-export-metadata :cl-weave/metadata)
                          (package-export-metadata :cl-weave/cli))
   :matchers (cl-weave:list-matchers)
   :mutation-operators (cl-weave:list-mutation-operators)))

(defun framework-metadata ()
  (append (framework-metadata-core)
          (framework-metadata-documentation)
          (framework-metadata-community)
          (framework-metadata-maintenance)
          (framework-metadata-ecosystem)))
