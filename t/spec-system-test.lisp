(in-package #:cl-weave/spec-test)

;;;; FR-001: cl-weave/spec is a separate ASDF system. Loading cl-weave alone
;;;; must not create its package or its exports. The guarantee is structural,
;;;; so these checks read the system definitions and the core sources; they give
;;;; the same answer on every runtime and in a read-only source tree.

(defun system-direct-dependencies (name)
  (mapcar (lambda (dependency)
            (if (consp dependency) (second dependency) dependency))
          (asdf:system-depends-on (asdf:find-system name))))

(defun component-source-files (root)
  (let ((files '()))
    (labels ((walk (component)
               (cond ((typep component 'asdf:cl-source-file)
                      (push (asdf:component-pathname component) files))
                     ((typep component 'asdf:parent-component)
                      (mapc #'walk (asdf:component-children component))))))
      (walk root))
    (nreverse files)))

(defun stream-defines-spec-package-p (stream)
  (let ((package (make-package (string (gensym "SPEC-READER-")) :use '(:cl)))
        (eof (gensym "EOF")))
    (unwind-protect
         (let ((*package* package) (*read-eval* nil))
           (loop for form = (read stream nil eof)
                 until (eq form eof)
                 thereis (and (consp form)
                              (eq (first form) 'cl:defpackage)
                              (consp (rest form))
                              (typep (second form) '(or symbol string))
                              (string= (string (second form)) "CL-WEAVE/SPEC"))))
      (delete-package package))))

(defun file-defines-spec-package-p (path)
  (with-open-file (stream path :external-format :utf-8)
    (stream-defines-spec-package-p stream)))

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
    (flet ((spec-path-p (path)
             (member "spec" (pathname-directory path) :test #'string=)))
      (let* ((files (component-source-files (asdf:find-system "cl-weave")))
             (parent (make-instance 'asdf:system :name "fixture"
                                    :pathname (asdf:system-source-directory "cl-weave")))
             (nested (asdf::parse-component-form
                      parent '(:module "src" :components
                               ((:module "spec" :components ((:file "package"))))))))
        (expect (plusp (length files)) :to-be t)
        (expect (remove-if-not #'spec-path-p files) :to-be nil)
        (expect (length (remove-if-not #'spec-path-p (component-source-files nested)))
                :to-be 1))))

  (it "defines the cl-weave/spec package in no source file of the cl-weave system"
    (let ((files (component-source-files (asdf:find-system "cl-weave"))))
      (expect (plusp (length files)) :to-be t)
      (expect (remove-if-not #'file-defines-spec-package-p files) :to-be nil))
    ;; Known-positive input: the detector must see the real definition.
    (expect (file-defines-spec-package-p
             (asdf:system-relative-pathname "cl-weave/spec" "src/spec/package.lisp"))
            :to-be t)
    (expect (with-input-from-string (stream (format nil "(DEFPACKAGE~%  #:cl-weave/spec (:use #:cl))"))
              (stream-defines-spec-package-p stream))
            :to-be t)
    (expect (with-input-from-string (stream "; (defpackage #:cl-weave/spec)")
              (stream-defines-spec-package-p stream))
            :to-be nil)))
