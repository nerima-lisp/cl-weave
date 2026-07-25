;;;; Lisp-level entry point for the cl-weave self-test suite.
;;;;
;;;;     sbcl --script run-tests.lisp
;;;;     nix run .#test
;;;;
;;;; Every nerima-lisp package exposes this same file at its root, so tooling
;;;; that runs a package's tests never has to know how that package loads its
;;;; suite. See PACKAGE_STANDARD.md in nerima-lisp/.github.

(require "asdf")

(let ((root (uiop:pathname-directory-pathname
             (or *load-truename* *load-pathname* (uiop:getcwd)))))
  ;; Resolve "cl-weave" and "cl-weave/test" out of this checkout regardless of
  ;; what the caller's CL_SOURCE_REGISTRY points at. Without this the script
  ;; silently tests whichever cl-weave happens to be on the registry first,
  ;; which for the framework itself would mean testing a released copy of the
  ;; very code the working tree is changing.
  (asdf:initialize-source-registry
   `(:source-registry (:directory ,root) :inherit-configuration))

  ;; Load and run rather than `asdf:test-system`. cl-weave is its own test
  ;; subject, and its suite contains a test that performs `test-op` on
  ;; cl-weave/test directly to assert the ASDF integration's failure path.
  ;; Driving the suite from an enclosing test-op puts that operation on the
  ;; plan twice and ASDF rejects it as a circular dependency. This mirrors the
  ;; body of the `:perform (test-op ...)` clause in cl-weave.asd, so
  ;; `asdf:test-system "cl-weave"` stays supported for downstream consumers.
  (handler-case
      (progn
        (asdf:load-system "cl-weave/test")
        (unless (uiop:symbol-call :cl-weave :run-all
                                  :reporter :spec :pass-with-no-tests nil)
          (format *error-output* "~&cl-weave self test suite failed.~%")
          (finish-output *error-output*)
          (uiop:quit 1)))
    (error (condition)
      (format *error-output* "~&cl-weave self tests failed: ~A~%" condition)
      (finish-output *error-output*)
      (uiop:quit 1))))

(finish-output *standard-output*)
(uiop:quit 0)
