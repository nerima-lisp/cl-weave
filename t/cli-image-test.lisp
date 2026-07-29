(in-package #:cl-weave/test)

(describe "delivered image installation prefix"
  (it "reads the prefix out of a bin or lib pathname alike"
    (expect (cl-weave/cli::anchor-prefix-pathname #P"/opt/cl-weave/bin/cl-weave")
            :to-equal #P"/opt/cl-weave/")
    (expect (cl-weave/cli::anchor-prefix-pathname #P"/opt/cl-weave/lib/cl-weave.core")
            :to-equal #P"/opt/cl-weave/"))

  (it "collapses the anchors of a standalone executable to one"
    ;; save-lisp-and-die :executable t writes a single file that is both the
    ;; runtime and the core, and that equality is the only signal the image
    ;; has that it is not running under a plain sbcl.
    (call-with-image-anchors
     #P"/opt/cl-weave/bin/cl-weave"
     #P"/opt/cl-weave/bin/cl-weave"
     (lambda ()
       (expect (cl-weave/cli::image-anchor-pathnames)
               :to-equal (list #P"/opt/cl-weave/bin/cl-weave")))))

  (it "keeps both anchors when a core is started by a separate runtime"
    (call-with-image-anchors
     #P"/opt/sbcl/bin/sbcl"
     #P"/opt/cl-weave/lib/cl-weave.core"
     (lambda ()
       (expect (cl-weave/cli::image-anchor-pathnames)
               :to-equal (list #P"/opt/sbcl/bin/sbcl"
                               #P"/opt/cl-weave/lib/cl-weave.core"))))))

(describe "installed source root"
  (it "prefers an explicitly configured root over any discovery"
    (let ((cl-weave/cli::*installed-source-root* #P"/configured/source/"))
      (expect (cl-weave/cli::installed-source-root)
              :to-equal #P"/configured/source/")))

  (it "finds the source tree installed beside the running image"
    (let* ((prefix (make-test-temporary-directory "cl-weave-image-prefix"))
           (root (merge-pathnames #P"share/common-lisp/source/" prefix))
           (binary (merge-pathnames #P"bin/cl-weave" prefix))
           (cl-weave/cli::*installed-source-root* nil))
      (unwind-protect
           (progn
             (ensure-directories-exist (merge-pathnames #P"cl-weave/" root))
             (call-with-image-anchors
              binary
              binary
              (lambda ()
                ;; TRUENAME, because the discovery probes the directory rather
                ;; than trusting the pathname it computed.
                (expect (cl-weave/cli::installed-source-root)
                        :to-equal (truename root)))))
        (uiop:delete-directory-tree prefix :validate t :if-does-not-exist :ignore))))

  (it "falls back to where ASDF found this system when nothing is installed"
    (let* ((prefix (make-test-temporary-directory "cl-weave-image-bare"))
           (binary (merge-pathnames #P"bin/cl-weave" prefix))
           (cl-weave/cli::*installed-source-root* nil))
      (unwind-protect
           (call-with-image-anchors
            binary
            binary
            (lambda ()
              (expect (cl-weave/cli::installed-source-root)
                      :to-equal (asdf:system-source-directory "cl-weave"))))
        (uiop:delete-directory-tree prefix :validate t :if-does-not-exist :ignore)))))

(describe "delivered image entry point"
  (it "re-reads the environment the image was dumped away from before running"
    (let ((root #P"/opt/cl-weave/share/common-lisp/source/")
          (temporary-setup 0)
          (source-registry nil)
          (output-translations nil)
          (pathname-defaults nil)
          (main-argv :not-called))
      (sb-ext:without-package-locks
        (with-mocked-functions
            (((symbol-function 'cl-weave/cli::installed-source-root)
              (lambda () root))
             ((symbol-function 'uiop:setup-temporary-directory)
              (lambda () (incf temporary-setup)))
             ((symbol-function 'asdf:initialize-source-registry)
              (lambda (&optional parameter)
                (setf source-registry parameter)))
             ((symbol-function 'asdf:initialize-output-translations)
              (lambda (&optional parameter)
                (setf output-translations parameter)))
             ((symbol-function 'cl-weave/cli::main)
              (lambda (&optional (argv :default))
                (setf pathname-defaults *default-pathname-defaults*
                      main-argv argv)
                t)))
          (let ((*default-pathname-defaults* #P"/nonexistent-build-sandbox/"))
            (cl-weave/cli::image-entry-point))))
      (expect temporary-setup :to-be 1)
      (expect source-registry
              :to-equal `(:source-registry (:tree ,root) :inherit-configuration))
      (expect output-translations
              :to-equal
              '(:output-translations (t (:home ".cache" "common-lisp" :implementation))
                :ignore-inherited-configuration))
      ;; MAIN must see the directory the user ran the binary in, not the one
      ;; the image happened to be dumped from.
      (expect pathname-defaults :to-equal (uiop:getcwd))
      ;; No argument, so MAIN reads the process argument vector itself.
      (expect main-argv :to-be :default)))

  (it "registers nothing extra when no shipped source tree can be found"
    (let ((source-registry :not-called))
      (sb-ext:without-package-locks
        (with-mocked-functions
            (((symbol-function 'cl-weave/cli::installed-source-root)
              (lambda () nil))
             ((symbol-function 'uiop:setup-temporary-directory)
              (lambda () nil))
             ((symbol-function 'asdf:initialize-source-registry)
              (lambda (&optional parameter)
                (setf source-registry parameter)))
             ((symbol-function 'asdf:initialize-output-translations)
              (lambda (&optional parameter)
                (declare (ignore parameter))
                nil))
             ((symbol-function 'cl-weave/cli::main)
              (lambda (&optional argv)
                (declare (ignore argv))
                t)))
          (let ((*default-pathname-defaults* #P"/nonexistent-build-sandbox/"))
            (cl-weave/cli::image-entry-point))))
      ;; :INHERIT-CONFIGURATION alone still honours the caller's
      ;; CL_SOURCE_REGISTRY, so an undiscoverable root degrades rather than
      ;; failing the run.
      (expect source-registry :to-equal '(:source-registry :inherit-configuration)))))
