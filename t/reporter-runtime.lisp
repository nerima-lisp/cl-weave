(in-package #:cl-weave/test)

(defun expect-special-variable-contracts (contracts)
  (dolist (contract contracts)
    (destructuring-bind (symbol default rebound) contract
      (expect (symbol-value symbol) :to-equal default)
      (progv (list symbol) (list rebound)
        (expect (symbol-value symbol) :to-equal rebound))
      (expect (symbol-value symbol) :to-equal default))))

(describe "runtime public controls"
  (it "provides dynamically bindable runtime defaults"
    (expect-special-variable-contracts
     '((cl-weave:*default-retry* 0 3)
       (cl-weave:*default-timeout-ms* nil 250)
       (cl-weave:*isolated-timeout-seconds* 5 0.5)
       (cl-weave:*max-workers* nil 4)
       (cl-weave:*test-name-filter* nil "focused"))))

  (it "exposes coverage unavailability reasons"
    (let ((condition (make-condition 'cl-weave::coverage-unavailable
                                     :reason "SB-COVER is missing")))
      (expect (cl-weave:coverage-unavailable-reason condition)
              :to-equal
              "SB-COVER is missing")
      (expect (princ-to-string condition)
              :to-contain
              "Coverage support is unavailable")))

  (it "explains result events through the spec reporter"
    (let* ((event (make-sample-event
                   :status :pass
                   :path '("public API" "reports a pass")))
           (output (with-output-to-string (stream)
                     (cl-weave:explain! (list event) stream))))
      (expect output :to-contain "public API > reports a pass")
      (expect output :to-contain "1 passed")
      (expect (multiple-value-list (cl-weave:explain! nil
                                                       (make-broadcast-stream)))
              :to-be
              nil))))
