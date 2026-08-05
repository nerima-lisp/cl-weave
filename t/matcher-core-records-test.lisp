(in-package #:cl-weave/test)

(describe "matcher public records"
  (it "exposes matcher names and descriptions"
    (let ((matcher (cl-weave::matcher-named :to-equal)))
      (expect (cl-weave:matcher-name matcher) :to-be :to-equal)
      (expect (cl-weave:matcher-description matcher) :to-be nil)))

  (it "exposes assertion failures through the test-failure base condition"
    (handler-case
        (progn
          (expect :actual :to-be :expected)
          (expect nil :to-be-truthy))
      (cl-weave:test-failure (condition)
        (expect (typep condition 'cl-weave:assertion-failure) :to-be-truthy)
        (expect (princ-to-string condition) :to-contain "Test assertion failed")))))

(describe "matcher-core low-level API"
  (it "rejects a matcher name that is not a symbol"
    (expect (lambda ()
              (cl-weave::register-matcher
               "not-a-symbol"
               (lambda (actual expected) (declare (ignore actual expected)) t)))
            :to-throw
            "matcher name must be a symbol"))

  (it "rejects a matcher function that is not a function"
    (expect (lambda ()
              (cl-weave::register-matcher :cl-weave-test-bad-fn "not-a-function"))
            :to-throw
            "must be registered with a function"))

  (it "rejects an unknown matcher name"
    (expect (lambda () (cl-weave::matcher-named :cl-weave-test-no-such-matcher))
            :to-throw
            "Unknown cl-weave matcher"))

  (it "rejects a non-string, non-NIL matcher description"
    (expect (lambda () (cl-weave::matcher-description-value 42 :cl-weave-test-matcher))
            :to-throw
            "description must be a string or NIL"))

  (it "passes NIL and string matcher descriptions through unchanged"
    (expect (cl-weave::matcher-description-value nil :cl-weave-test-matcher) :to-be nil)
    (expect (cl-weave::matcher-description-value "a description" :cl-weave-test-matcher)
            :to-equal
            "a description"))

  (it "derives a matcher spec name, function, and keyword description from a runtime spec list"
    (let ((spec (list :cl-weave-test-runtime-spec
                       (lambda (actual expected) (declare (ignore actual expected)) t)
                       :description
                       "built at runtime")))
      (expect (cl-weave::matcher-spec-name spec) :to-be :cl-weave-test-runtime-spec)
      (expect (functionp (cl-weave::matcher-spec-function spec)) :to-be-truthy)
      (expect (cl-weave::matcher-spec-description spec) :to-equal "built at runtime")))

  (it "derives a bare string description and a NIL description from a runtime spec list"
    (expect (cl-weave::matcher-spec-description
             (list :cl-weave-test-spec
                   (lambda (actual expected) (declare (ignore actual expected)) t)
                   "bare string"))
            :to-equal
            "bare string")
    (expect (cl-weave::matcher-spec-description
             (list :cl-weave-test-spec
                   (lambda (actual expected) (declare (ignore actual expected)) t)))
            :to-be
            nil)))
