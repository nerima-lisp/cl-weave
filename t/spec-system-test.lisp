(in-package #:cl-weave/spec-test)

;;;; FR-001: cl-weave/spec is a separate ASDF system. Loading cl-weave alone
;;;; must not create its package or its exports. The guarantee is structural,
;;;; so these checks read the system definitions and the core sources; they give
;;;; the same answer on every runtime and in a read-only source tree.

(defun system-direct-dependencies (name)
  (mapcar (lambda (dependency)
            (if (consp dependency) (second dependency) dependency))
          (asdf:system-depends-on (asdf:find-system name))))

(defun cl-weave-source-files ()
  "Pathnames of the source files of the cl-weave system that exist on disk."
  (let ((files '()))
    (labels ((walk (component)
               (if (typep component 'asdf:cl-source-file)
                   (let ((path (asdf:component-pathname component)))
                     (when (probe-file path) (push path files)))
                   (when (typep component 'asdf:parent-component)
                     (mapc #'walk (asdf:component-children component))))))
      (walk (asdf:find-system "cl-weave")))
    files))

(defun file-defines-spec-package-p (path)
  "True when a line of PATH is a package definition naming cl-weave/spec."
  (with-open-file (stream path :external-format :utf-8)
    (loop for line = (read-line stream nil)
          while line
          thereis (and (or (search "defpackage" line) (search "define-package" line))
                       (search "cl-weave/spec" (string-downcase line))
                       t))))

(describe "cl-weave/spec system"
  (it "depends only on cl-weave"
    (expect (system-direct-dependencies "cl-weave/spec") :to-equal '("cl-weave")))

  (it "is a dependency of cl-weave/test"
    (expect (and (member "cl-weave/spec" (system-direct-dependencies "cl-weave/test")
                         :test #'string=)
                 t)
            :to-be t))

  (it "is not a dependency of cl-weave"
    (expect (member "cl-weave/spec" (system-direct-dependencies "cl-weave")
                    :test #'string=)
            :to-be nil))

  (it "has no source file inside the cl-weave system"
    (expect (remove-if-not (lambda (component)
                             (member "spec" (pathname-directory
                                             (asdf:component-pathname component))
                                     :test #'string=))
                           (asdf:component-children (asdf:find-system "cl-weave")))
            :to-be nil))

  (it "defines the cl-weave/spec package in no source file of the cl-weave system"
    (let ((files (cl-weave-source-files)))
      (expect (plusp (length files)) :to-be t)
      (expect (remove-if-not #'file-defines-spec-package-p files) :to-be nil))
    ;; Known-positive input: the detector must see the real definition.
    (expect (file-defines-spec-package-p
             (asdf:system-relative-pathname "cl-weave/spec" "src/spec/package.lisp"))
            :to-be t)))
