(in-package #:cl-weave)

(defun normalized-mutation-timeout-ms (timeout-ms)
  (cond
    ((null timeout-ms) nil)
    ((and (integerp timeout-ms) (plusp timeout-ms))
     (require-platform-capability :timeout)
     timeout-ms)
    (t (error "Mutation timeout must be NIL or a positive integer in milliseconds: ~S"
              timeout-ms))))

(defun call-mutation-test (mutation test timeout-ms)
  (call-with-platform-timeout/k
   (and timeout-ms (/ timeout-ms 1000.0))
   (lambda () (funcall test (mutation-form mutation) mutation))
   #'identity))

(defun make-mutation-outcome (mutation status &optional condition)
  (make-mutation-result :mutation mutation :status status :condition condition))

(defun run-mutation (mutation test timeout-ms)
  (handler-case
      (make-mutation-outcome mutation
                              (if (call-mutation-test mutation test timeout-ms)
                                  :survived
                                  :killed))
    (assertion-failure (condition)
      (make-mutation-outcome mutation :killed condition))
    (platform-timeout ()
      (make-mutation-outcome mutation :errored
                              (make-condition 'test-timeout
                                              :timeout-ms timeout-ms)))
    (error (condition)
      (make-mutation-outcome mutation :errored condition))))

(defun run-mutations (form test &key (operators *default-mutation-operators*)
                                     timeout-ms)
  (check-type test function)
  (let ((timeout-ms (normalized-mutation-timeout-ms timeout-ms)))
    (mapcar (lambda (mutation)
              (run-mutation mutation test timeout-ms))
            (collect-mutations form :operators operators))))

(defun count-mutation-status (results status)
  (count status results :key #'mutation-result-status))

(defun mutation-summary (results)
  (let* ((total (length results))
         (killed (count-mutation-status results :killed))
         (survived (count-mutation-status results :survived))
         (errored (count-mutation-status results :errored)))
    (list :total total
          :killed killed
          :survived survived
          :errored errored
          :score (if (zerop total)
                     1.0
                     (/ killed total 1.0)))))

(defun normalized-mutation-score-threshold (min-score)
  (unless (and (realp min-score) (<= 0 min-score 1))
    (error "Mutation score threshold must be a real number between 0 and 1, got ~S."
           min-score))
  min-score)

(defun mutation-score-passes-p (results min-score)
  (let* ((min-score (normalized-mutation-score-threshold min-score))
         (summary (mutation-summary results)))
    (values (and (zerop (getf summary :errored))
                 (>= (getf summary :score) min-score))
            summary)))

(defun assert-mutation-score (results min-score)
  (multiple-value-bind (pass-p summary)
      (mutation-score-passes-p results min-score)
    (unless pass-p
      (error 'mutation-score-failure
             :summary summary
             :min-score min-score))
    summary))

