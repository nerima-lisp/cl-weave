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
