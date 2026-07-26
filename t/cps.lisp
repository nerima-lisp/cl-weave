(in-package #:cl-weave/test)

(describe "cps continuation helpers"
  (it "captures the primary value passed to the local continuation"
    (with-continuation-result (result next calledp)
        (funcall (lambda (next)
                   (funcall next :ok :ignored))
                 #'next)
      (expect calledp :to-be-truthy)
      (expect result :to-be :ok)))

  (it "captures every value passed to the local continuation"
    (with-continuation-values (values next calledp)
        (funcall (lambda (next)
                   (funcall next :ok 42 "done"))
                 #'next)
      (expect calledp :to-be-truthy)
      (expect values :to-equal '(:ok 42 "done"))))

  (it "signals assertion-failure when the continuation is not called"
    (handler-case
        (with-continuation-result (result next)
            :not-called
          result)
      (assertion-failure (condition)
        (let ((detail (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :continuation-called)
          (expect (cl-weave::assertion-detail-actual detail) :to-equal '(:called nil))
          (expect (cl-weave::assertion-detail-expected detail) :to-equal '(:called t))))
      (:no-error (&rest values)
        (declare (ignore values))
        (error "Expected with-continuation-result to fail.")))))

