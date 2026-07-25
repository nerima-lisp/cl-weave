(in-package #:cl-weave)

(defun normalize-expectation (tokens)
  (when (null tokens)
    (error "cl-weave: expect requires a matcher, for example (expect value :to-be expected)."))
  (if (eq (first tokens) :not)
      (values t (second tokens) (cddr tokens))
      (values nil (first tokens) (rest tokens))))

(defun assert-expectation (actual expectation form &optional (capture-success-detail-p t))
  (multiple-value-bind (negated matcher-name expected) (normalize-expectation expectation)
    (call-with-matcher-result/k
     (matcher-named matcher-name)
     actual
     expected
     (lambda (raw-pass reported-actual reported-expected)
       (let* ((pass (if negated (not raw-pass) raw-pass))
              (detail
                (when (or capture-success-detail-p (not pass) (journaling-active-p))
                  (make-assertion-detail
                   :form form
                   :matcher matcher-name
                   :actual reported-actual
                   :expected reported-expected
                   :negated negated
                   :pass raw-pass))))
         (when (journaling-active-p)
           (record-assertion-frame detail))
         (unless pass
           (signal-assertion-failure detail))
         (values pass detail))))))
