;;;; Package shared by every cl-weave/spec test file. A test file for a module
;;;; imports nothing more: reach other cl-weave internals with cl-weave::.

(defpackage #:cl-weave/spec-test
  (:use #:cl #:cl-weave/spec)
  (:shadowing-import-from #:cl-weave
   #:describe)
  (:import-from #:cl-weave
   #:assertion-failure
   #:expect
   #:it))
