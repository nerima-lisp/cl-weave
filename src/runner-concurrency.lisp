(in-package #:cl-weave)

(defconstant +maximum-physical-worker-count+ 64)

(defun worker-batch-size (tests &optional test-count)
  (let* ((requested-limit (normalize-max-workers *max-workers*))
         (limit (or requested-limit *default-max-workers*)))
    (min limit
         +maximum-physical-worker-count+
         (or test-count (length tests)))))

#+sb-thread
(progn
  (defun make-runner-worker-thread (function name)
    (sb-thread:make-thread function :name name))

  (defun join-runner-worker-thread (thread)
    (sb-thread:join-thread thread)))

(defun capture-runner-dynamic-environment ()
  (mapcar #'symbol-value *runner-dynamic-environment-variables*))

(defmacro with-runner-dynamic-environment (values-form &body body)
  `(progv *runner-dynamic-environment-variables*
          ,values-form
     ,@body))

(defun run-concurrent-test-cases (suite tests)
  #+sb-thread
  (let* ((test-count (length tests))
         (worker-count (worker-batch-size tests test-count)))
    (if (<= worker-count 1)
        (map (quote list)
             (lambda (test)
               (run-test-case/internal suite test))
             tests)
        (let* ((test-vector (coerce tests (quote vector)))
               (captured-environment
                 (capture-runner-dynamic-environment))
               (results (make-array test-count))
               (cancel-mask (ash 1 (integer-length most-positive-fixnum)))
               (index-mask (1- cancel-mask))
               (work-state (make-array 1
                                       :element-type (quote sb-ext:word)
                                       :initial-element 0))
               (start-gate (sb-thread:make-semaphore :count 0))
               (threads (make-array worker-count :fill-pointer 0))
               (join-attempts (make-hash-table :test (function eq)))
               (created-worker-count 0)
               (released-worker-count 0)
               (first-condition nil))
          (assert (< test-count cancel-mask))
          (labels ((claim-job ()
                     (loop
                       (let* ((state (aref work-state 0))
                              (index (logand state index-mask)))
                         (when (or (logtest cancel-mask state)
                                   (>= index test-count))
                           (return (values nil nil nil)))
                         (when (= state
                                  (sb-ext:compare-and-swap
                                    (aref work-state 0)
                                    state
                                    (1+ state)))
                           (return
                             (values index (aref test-vector index) t))))))
                   (run-worker ()
                     (sb-thread:wait-on-semaphore start-gate)
                     (with-runner-dynamic-environment captured-environment
                       (loop
                         (multiple-value-bind (index test presentp) (claim-job)
                           (unless presentp
                             (return))
                           (setf (aref results index)
                                 (run-test-case/internal suite test))))))
                   (record-first-condition (condition)
                     (unless first-condition
                       (setf first-condition condition)))
                   (release-workers ()
                     (loop while (< released-worker-count created-worker-count)
                           do (sb-thread:signal-semaphore start-gate)
                              (incf released-worker-count)))
                   (cancel-workers ()
                     (loop
                       (let ((state (aref work-state 0)))
                         (when (or (logtest cancel-mask state)
                                   (= state
                                      (sb-ext:compare-and-swap
                                        (aref work-state 0)
                                        state
                                        (logior state cancel-mask))))
                           (return))))
                     (release-workers))
                   (join-thread-once (thread)
                     (unless (gethash thread join-attempts)
                       (setf (gethash thread join-attempts) t)
                       (handler-case
                           (join-runner-worker-thread thread)
                         (serious-condition (condition)
                           (record-first-condition condition)
                           (handler-case
                               (cancel-workers)
                             (serious-condition (cleanup-condition)
                               (record-first-condition cleanup-condition)))
                           (handler-case
                               (sb-thread:join-thread thread)
                             (serious-condition (cleanup-condition)
                               (record-first-condition cleanup-condition)))))))
                   (join-created-threads ()
                     (loop for thread across threads
                           do (join-thread-once thread))))
            (unwind-protect
                 (handler-case
                     (progn
                       (loop for worker-number from 1 to worker-count
                             do (vector-push
                                 (make-runner-worker-thread
                                  (function run-worker)
                                  (format nil "cl-weave worker ~D" worker-number))
                                 threads)
                                (incf created-worker-count))
                       (release-workers)
                       (join-created-threads))
                   (serious-condition (condition)
                     (record-first-condition condition)))
              (unless (= released-worker-count created-worker-count)
                (handler-case
                    (cancel-workers)
                  (serious-condition (condition)
                    (record-first-condition condition))))
              (join-created-threads))
            (when first-condition
              (error first-condition))
            (coerce results (quote list))))))
  #-sb-thread
  (declare (ignore suite tests))
  #-sb-thread
  (error "cl-weave: concurrent execution requires an implementation with SB-THREAD."))

(declaim (ftype (function (suite list execution-control function
                           selection-filter &optional t t t t)
                          *)
                collect-children/k))
