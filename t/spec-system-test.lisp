(in-package #:cl-weave/spec-test)

;;;; FR-001: cl-weave/spec is a separate ASDF system. Loading cl-weave alone
;;;; must not create its package or its exports.

(defun system-direct-dependencies (name)
  (mapcar (lambda (dependency)
            (if (consp dependency) (second dependency) dependency))
          (asdf:system-depends-on (asdf:find-system name))))

#+sbcl
(defun lisp-child-output (&rest forms)
  "Run FORMS, one --eval each, in a fresh SBCL whose source registry is the
checkout. Return (values stdout exit-code)."
  (let* ((root (asdf:system-source-directory "cl-weave"))
         (evals (list* "(require :asdf)"
                       (format nil "(asdf:initialize-source-registry '(:source-registry (:directory ~S) :inherit-configuration))" root)
                       (mapcar (lambda (form) (with-standard-io-syntax (prin1-to-string form))) forms)))
         (output (make-string-output-stream))
         (process (sb-ext:run-program
                   sb-ext:*runtime-pathname*
                   (append (list "--core" (namestring sb-ext:*core-pathname*)
                                 "--noinform" "--non-interactive" "--no-userinit")
                           (loop for form in evals collect "--eval" collect form))
                   :output output :error :output :input nil)))
    (values (get-output-stream-string output)
            (sb-ext:process-exit-code process))))

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

  #+sbcl
  (it "creates no cl-weave/spec package when only cl-weave is loaded"
    (multiple-value-bind (output code)
        (lisp-child-output
         '(asdf:load-system "cl-weave")
         '(format t "~&RESULT=~A~%" (if (find-package "CL-WEAVE/SPEC") "present" "absent")))
      (expect (list code (when (/= code 0) output)) :to-equal '(0 nil))
      (expect (and (search "RESULT=absent" output) t) :to-be t)))

  #+sbcl
  (it "creates the cl-weave/spec package when cl-weave/spec is loaded"
    (multiple-value-bind (output code)
        (lisp-child-output
         '(asdf:load-system "cl-weave/spec")
         '(format t "~&RESULT=~A~%" (if (find-package "CL-WEAVE/SPEC") "present" "absent")))
      (expect (list code (when (/= code 0) output)) :to-equal '(0 nil))
      (expect (and (search "RESULT=present" output) t) :to-be t))))
