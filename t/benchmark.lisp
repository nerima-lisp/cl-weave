(in-package #:cl-weave/test)

(describe "benchmark API"
  (it "runs warmups and samples with the requested iteration count"
    (let ((calls 0))
      (let ((result (cl-weave:measure (lambda () (incf calls))
                                      :warmup 2 :samples 3 :iterations 4)))
        (expect calls :to-be 14)
        (expect (cl-weave:benchmark-result-warmup result) :to-be 2)
        (expect (cl-weave:benchmark-result-iterations result) :to-be 4)
        (expect (length (cl-weave:benchmark-result-samples result)) :to-be 3)
        (expect (cl-weave:minimum-ms result) :to-be-less-than-or-equal
                (cl-weave:median-ms result))
        (expect (cl-weave:median-ms result) :to-be-less-than-or-equal
                (cl-weave:maximum-ms result)))))

  (it "preserves lexical bindings in benchmark bodies"
    (let ((value 41))
      (let ((result (cl-weave:benchmark (:samples 1 :iterations 1)
                      (incf value))))
        (expect value :to-be 42)
        (expect (cl-weave:mean-ms result) :to-be-greater-than-or-equal 0))))

  (it "rejects invalid benchmark options"
    (dolist (arguments '((:warmup -1) (:samples 0) (:iterations 0)))
      (expect (lambda ()
                (apply #'cl-weave:measure (lambda () nil) arguments))
              :to-throw "must be a"))))
