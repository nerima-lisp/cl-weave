(in-package #:cl-weave)

;; The portable baseline: no optional capability is available until an
;; implementation-specific file (currently only platform-sbcl.lisp) adds it
;; back. Listing every capability this codebase knows about here, rather than
;; just :timeout, keeps a second or third load of this file (ASDF :force t,
;; or a REPL reload) idempotent for all of them, not just the first one that
;; happened to need it.
(setf *platform-capabilities*
      (set-difference *platform-capabilities*
                      '(:timeout :isolation :concurrency)
                      :test #'eq)
      *platform-timeout-caller* nil
      *platform-timeout-condition-predicate* nil)
