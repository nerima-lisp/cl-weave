(in-package #:cl-weave/test)

#+sb-thread
(describe "concurrent tests"
  (it "runs adjacent concurrent tests before either one completes"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "concurrent" :parent root)))
           (mutex (sb-thread:make-mutex :name "cl-weave concurrent test log"))
           (events-log nil))
      (labels ((record (event)
                 (sb-thread:with-mutex (mutex)
                   (push event events-log)))
               (recorded-p (event)
                 (sb-thread:with-mutex (mutex)
                   (member event events-log)))
               (wait-until-recorded (event timeout-seconds)
                 (let ((deadline (+ (get-internal-real-time)
                                    (* timeout-seconds internal-time-units-per-second))))
                   (loop until (or (recorded-p event)
                                   (> (get-internal-real-time) deadline))
                         do (sleep 0.01))
                   (recorded-p event))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "first"
          :execution-mode :concurrent
          :function (lambda ()
                      (record :first-start)
                      (unless (wait-until-recorded :second-start 1)
                        (error "second concurrent test did not start before first completed"))
                      (record :first-end))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "second"
          :execution-mode :concurrent
          :function (lambda ()
                      (record :second-start)
                      (sleep 0.02)
                      (record :second-end))))
        (let* ((events (cl-weave::collect-events root))
               (ordered-log (reverse events-log)))
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass :pass))
          (expect (member :second-start ordered-log) :not :to-be nil)
          (expect (member :first-end ordered-log) :not :to-be nil)
          (expect (mapcar #'cl-weave::test-event-path events)
                  :to-equal '(("concurrent" "first")
                              ("concurrent" "second")))))))

  (it
      "executes one-worker batches on the calling thread"
      (let* ((root (cl-weave::make-suite :name "root"))
             (suite
            (cl-weave::add-child
              root
              (cl-weave::make-suite :name "worker limit" :parent root)))
             (mutex (sb-thread:make-mutex :name "cl-weave max worker test log"))
             (events-log nil)
             (thread-count 0)
             (make-thread (symbol-function 'cl-weave::make-runner-worker-thread)))
        (labels ((record (event)
                   (sb-thread:with-mutex (mutex) (push event events-log))))
          (cl-weave::add-child
            suite
            (cl-weave::make-test-case
              :name
              "first"
              :execution-mode
              :concurrent
              :function
              (lambda ()
                (record :first-start)
                (sleep 0.02)
                (record :first-end))))
          (cl-weave::add-child
            suite
            (cl-weave::make-test-case
              :name
              "second"
              :execution-mode
              :concurrent
              :function
              (lambda ()
                (record :second-start)
                (record :second-end))))
          (with-mocked-functions
            (((symbol-function 'cl-weave::make-runner-worker-thread)
                (lambda (function name)
                  (incf thread-count)
                  (funcall make-thread function name))))
            (dolist (tests
                       (list (cl-weave::suite-children suite)
                             (coerce (cl-weave::suite-children suite) 'vector)))
              (setf events-log nil)
              (let ((events
                      (let ((cl-weave::*max-workers* 1))
                        (cl-weave::run-concurrent-test-cases suite tests))))
                (expect (mapcar #'cl-weave::test-event-status events) :to-equal '(:pass :pass))
                (expect
                  (mapcar #'cl-weave::test-event-path events)
                  :to-equal
                  '(("worker limit" "first") ("worker limit" "second")))
                (expect
                  (reverse events-log)
                  :to-equal
                  '(:first-start :first-end :second-start :second-end))))
            (expect thread-count :to-be 0)))))

  (progn
  (it
    "bounds implicit worker batches and preserves explicit limits"
    (let ((tests (make-list 5 :initial-element :test))
          (cl-weave::*max-workers* nil)
          (cl-weave::*default-max-workers* 2))
      (expect (cl-weave::worker-batch-size tests) :to-be 2)
      (expect (cl-weave::worker-batch-size (list :test)) :to-be 1)
      (let ((cl-weave::*max-workers* 4))
        (expect (cl-weave::worker-batch-size tests) :to-be 4)))
    (let ((cl-weave::*max-workers* cl-weave::+maximum-worker-count+))
      (expect
        (cl-weave::worker-batch-size
          (make-list cl-weave::+maximum-worker-count+
                     :initial-element
                     :test))
        :to-be
        cl-weave::+maximum-physical-worker-count+)))

  (it
    "normalizes in-process processor detection to the default worker range"
    (dolist (sample '((16 16) (-1 2) (nil 2) (64 32)))
      (destructuring-bind (processor-count expected) sample
        (with-mocked-functions
          (((symbol-function 'cl-weave::online-processor-count)
              (lambda () processor-count)))
          (expect (cl-weave::detect-default-max-workers) :to-be expected))))
    (with-mocked-functions
      (((symbol-function 'cl-weave::online-processor-count)
          (lambda ()
            (error "processor probe failed"))))
      (expect (cl-weave::detect-default-max-workers) :to-be 2))
    (expect
      (cl-weave::detect-default-max-workers)
      :to-satisfy
      (lambda (count)
        (<= 2 count cl-weave::+default-max-workers-cap+))))

  (it
    "bounds max workers before executing tests"
    (expect
      (cl-weave::collect-events
        (cl-weave::make-suite :name "empty")
        :max-workers
        cl-weave::+maximum-worker-count+)
      :to-be-null)
    (dolist (workers `(,(1+ cl-weave::+maximum-worker-count+) 0 -1 :many "2"))
      (let ((executed nil)
            (root (cl-weave::make-suite :name "root")))
        (add-tripwire-test-case root (lambda () (setf executed t)))
        (expect
          (lambda ()
            (cl-weave::collect-events root :max-workers workers))
          :to-throw
          "Max workers must be")
        (expect executed :to-be nil)))))

  (it "returns no events for an empty concurrent test list"
    (let ((suite (cl-weave::make-suite :name "empty")))
      (expect
        (cl-weave::run-concurrent-test-cases suite nil)
        :to-be-null)))

  (it "inherits concurrent execution mode from suites"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "concurrent suite"
                    :parent root
                    :execution-mode :concurrent)))
           (mutex (sb-thread:make-mutex :name "cl-weave suite concurrent test log"))
           (events-log nil))
      (labels ((record (event)
                 (sb-thread:with-mutex (mutex)
                   (push event events-log)))
               (recorded-p (event)
                 (sb-thread:with-mutex (mutex)
                   (member event events-log)))
               (wait-until-recorded (event timeout-seconds)
                 (let ((deadline (+ (get-internal-real-time)
                                    (* timeout-seconds internal-time-units-per-second))))
                   (loop until (or (recorded-p event)
                                   (> (get-internal-real-time) deadline))
                         do (sleep 0.01))
                   (recorded-p event))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "first"
          :function (lambda ()
                      (record :first-start)
                      (unless (wait-until-recorded :second-start 1)
                        (error "suite concurrent test did not start beside its sibling"))
                      (record :first-end))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "second"
          :function (lambda ()
                      (record :second-start)
                      (sleep 0.02)
                      (record :second-end))))
        (let ((events (cl-weave::collect-events root)))
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass :pass))
          (expect (mapcar #'cl-weave::test-event-path events)
                  :to-equal '(("concurrent suite" "first")
                              ("concurrent suite" "second")))))))

  (progn
      (it
        "joins partially created workers once and preserves the first condition"
        (dolist (join-inside-wrapper-p (list nil t))
          (let* ((root (cl-weave::make-suite :name "root"))
                 (suite
                (cl-weave::add-child
                  root
                  (cl-weave::make-suite :name "worker cleanup" :parent root)))
                 (executed nil)
                 (created-threads nil)
                 (join-attempts (make-hash-table :test #'eq))
                 (worker-entered (sb-thread:make-semaphore :count 0))
                 (release-worker (sb-thread:make-semaphore :count 0))
                 (make-call-count 0)
                 (returned-condition (make-condition 'simple-error :format-control "injected worker creation failure" :format-arguments nil))
                 (make-thread-function (symbol-function 'cl-weave::make-runner-worker-thread))
                 (tests
                (list
                  (cl-weave::add-child
                    suite
                    (cl-weave::make-test-case
                      :name
                      "first"
                      :function
                      (lambda ()
                        (setf executed t))))
                  (cl-weave::add-child
                    suite
                    (cl-weave::make-test-case
                      :name
                      "second"
                      :function
                      (lambda ()
                        (setf executed t)))))))
            (unwind-protect (progn
                (with-mocked-functions
                  (((symbol-function 'cl-weave::make-runner-worker-thread)
                      (lambda (function name)
                        (incf make-call-count)
                        (if (= make-call-count 1) (let ((thread
                                (funcall
                                  make-thread-function
                                  (lambda ()
                                    (sb-thread:signal-semaphore worker-entered)
                                    (sb-thread:wait-on-semaphore release-worker)
                                    (funcall function))
                                  name)))
                            (push thread created-threads)
                            thread)
                          (progn
                            (sb-thread:wait-on-semaphore worker-entered)
                            (error returned-condition)))))
                    ((symbol-function 'cl-weave::join-runner-worker-thread)
                      (lambda (thread)
                        (incf (gethash thread join-attempts 0))
                        (sb-thread:signal-semaphore release-worker)
                        (when join-inside-wrapper-p
                          (sb-thread:join-thread thread))
                        (error
                          (if join-inside-wrapper-p "injected cleanup join failure after join"
                            "injected cleanup join failure before join")))))
                  (handler-case (let ((cl-weave::*max-workers* 2))
                      (cl-weave::run-concurrent-test-cases suite tests))
                    (serious-condition (condition)
                      (progn (expect condition :to-be returned-condition) (setf returned-condition condition)))))
                (expect
                  (princ-to-string returned-condition)
                  :to-equal
                  "injected worker creation failure")
                (expect executed :to-be nil)
                (expect (length created-threads) :to-be 1)
                (expect
                  (every
                    (lambda (thread)
                      (not (sb-thread:thread-alive-p thread)))
                    created-threads)
                  :to-be
                  t)
                (expect
                  (mapcar
                    (lambda (thread)
                      (gethash thread join-attempts))
                    (reverse created-threads))
                  :to-equal
                  '(1)))
              (dolist (thread created-threads)
                (when (sb-thread:thread-alive-p thread)
                  (ignore-errors (sb-thread:terminate-thread thread)))
                (ignore-errors (sb-thread:join-thread thread)))))))
      (it
        "inherits runner dynamic bindings in worker threads"
        (let* ((root (cl-weave::make-suite :name "root"))
               (suite
              (cl-weave::add-child
                root
                (cl-weave::make-suite :name "dynamic binding" :parent root)))
               (observed nil)
               (test
              (cl-weave::add-child
                suite
                (cl-weave::make-test-case
                  :name
                  "observes binding"
                  :function
                  (lambda ()
                    (setf observed cl-weave::*property-test-count*))))))
          (let ((cl-weave::*property-test-count* 37))
            (expect
              (mapcar
                (function cl-weave::test-event-status)
                (cl-weave::run-concurrent-test-cases suite (list test)))
              :to-equal
              (quote (:pass))))
          (expect observed :to-be 37)))
      (it "keeps bail semantics sequential for concurrent tests"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "concurrent bail" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "fails"
        :execution-mode :concurrent
        :function (lambda ()
                    (push :first events-log)
                    (expect :actual :to-be :expected))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "must not run"
        :execution-mode :concurrent
        :function (lambda ()
                    (push :second events-log))))
      (let ((events (cl-weave::collect-events root :bail t)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:fail))
        (expect events-log :to-equal '(:first)))))))

#+sb-thread
(describe
    "concurrent registration"
    (progn
      (it
        "serializes children owners generation and tail as one transaction"
        (flet ((exercise ()
                 (let* ((worker-count 16)
                     (registrations-per-worker 500)
                     (expected-count (* worker-count registrations-per-worker))
                     (suite (cl-weave::make-suite :name "registration"))
                     (owners (make-hash-table :test #'eq))
                     (pathname #P"/tmp/cl-weave-concurrent-registration.lisp")
                     (start-generation cl-weave::*test-registry-generation*)
                     (start (sb-thread:make-semaphore :count 0))
                     (threads
                    (loop for worker below worker-count
                          collect (let ((worker-id worker))
                        (sb-thread:make-thread
                          (lambda ()
                            (let ((cl-weave::*current-suite* suite)
                                  (cl-weave::*registration-owners* owners))
                              (sb-thread:wait-on-semaphore start)
                              (dotimes (index registrations-per-worker)
                                (cl-weave::register-test
                                  (format nil "~D/~D" worker-id index)
                                  (lambda ()
                                    nil)
                                  :location
                                  (list :file pathname))))))))))
                (dotimes (index worker-count)
                  (declare (ignorable index))
                  (sb-thread:signal-semaphore start))
                (mapc #'sb-thread:join-thread threads)
                (let ((children (cl-weave::suite-children suite)))
                  (expect (length children) :to-be expected-count)
                  (expect
                    (- cl-weave::*test-registry-generation* start-generation)
                    :to-be
                    expected-count)
                  (expect (hash-table-count owners) :to-be expected-count)
                  (expect
                    (every
                      (lambda (child)
                        (equal (gethash child owners) pathname))
                      children)
                    :to-be
                    t)
                  (expect (cl-weave::suite-children-tail suite) :to-be (last children))
                  (expect (cdr (cl-weave::suite-children-tail suite)) :to-be nil)))))
          #+
          sbcl
          (sb-ext:with-timeout 20 (exercise))
          #-
          sbcl
          (exercise)))
      (progn
        (it
          "runs callbacks outside the registry lock on a stable snapshot"
          (flet ((exercise ()
                   (let ((root (cl-weave::make-suite :name "snapshot"))
                      (added nil))
                  (cl-weave::add-child
                    root
                    (cl-weave::make-test-case
                      :name
                      "first"
                      :function
                      (lambda ()
                        (unless added
                          (setf added t)
                          (cl-weave::add-child
                            root
                            (cl-weave::make-test-case
                              :name
                              "late"
                              :function
                              (lambda ()
                                nil)))))))
                  (let ((events (cl-weave::collect-events root)))
                    (expect
                      (mapcar (function cl-weave::test-event-path) events)
                      :to-equal
                      (quote (("first"))))
                    (expect
                      (mapcar (function cl-weave::test-event-status) events)
                      :to-equal
                      (quote (:pass))))
                  (expect (length (cl-weave::suite-children root)) :to-be 2)
                  (expect
                    (mapcar
                      (function cl-weave:test-plan-entry-path)
                      (cl-weave:collect-test-plan root))
                    :to-equal
                    (quote (("first") ("late")))))))
            (sb-ext:with-timeout 5 (exercise))))
        (progn
          (it
            "keeps concurrent run and list snapshots structurally consistent"
            (flet ((exercise ()
                     (let* ((worker-count 4)
                         (registrations-per-worker 100)
                         (expected-count (* worker-count registrations-per-worker))
                         (root (cl-weave::make-suite :name "snapshot stress"))
                         (owners (make-hash-table :test (function eq)))
                         (pathname #P"/tmp/cl-weave-snapshot-stress.lisp")
                         (start-generation cl-weave::*test-registry-generation*)
                         (start (sb-thread:make-semaphore :count 0))
                         (error-lock (sb-thread:make-mutex :name "cl-weave snapshot stress errors"))
                         (errors nil))
                    (labels ((record-condition (condition)
                               (sb-thread:with-mutex (error-lock) (push (princ-to-string condition) errors)))
                             (validate-rows (rows path-accessor)
                               (let ((seen (make-hash-table :test (function equal))))
                            (dolist (row rows)
                              (let ((path (funcall path-accessor row)))
                                (when (gethash path seen)
                                  (error "duplicate snapshot path ~S" path))
                                (setf (gethash path seen) t)))))
                             (make-writer (worker-id)
                               (sb-thread:make-thread
                            (lambda ()
                              (handler-case (let ((cl-weave::*current-suite* root)
                                      (cl-weave::*registration-owners* owners))
                                  (sb-thread:wait-on-semaphore start)
                                  (dotimes (index registrations-per-worker)
                                    (cl-weave::register-test
                                      (format nil "~D/~D" worker-id index)
                                      (lambda ()
                                        nil)
                                      :location
                                      (list :file pathname))
                                    (when (zerop (mod index 10))
                                      (sleep 0.001))))
                                (condition (condition)
                                  (record-condition condition))))))
                             (make-reader ()
                               (sb-thread:make-thread
                            (lambda ()
                              (handler-case (progn
                                  (sb-thread:wait-on-semaphore start)
                                  (dotimes (index 30)
                                    (validate-rows
                                      (cl-weave:collect-test-plan root)
                                      (function cl-weave:test-plan-entry-path))
                                    (let ((events (cl-weave::collect-events root)))
                                      (validate-rows events (function cl-weave::test-event-path))
                                      (unless (every
                                          (lambda (event)
                                            (eq (cl-weave::test-event-status event) :pass))
                                          events)
                                        (error "non-pass snapshot event")))))
                                (condition (condition)
                                  (record-condition condition)))))))
                      (let ((threads
                            (append
                              (loop for worker-id below worker-count
                                    collect (make-writer worker-id))
                              (loop repeat 2
                                    collect (make-reader)))))
                        (dotimes (index (length threads))
                          (declare)
                          (sb-thread:signal-semaphore start))
                        (mapc (function sb-thread:join-thread) threads))
                      (let ((children (cl-weave::suite-children root)))
                        (expect errors :to-equal nil)
                        (expect (length children) :to-be expected-count)
                        (expect
                          (- cl-weave::*test-registry-generation* start-generation)
                          :to-be
                          expected-count)
                        (expect (hash-table-count owners) :to-be expected-count)
                        (expect (cl-weave::suite-children-tail root) :to-be (last children))
                        (expect (cdr (cl-weave::suite-children-tail root)) :to-be nil))))))
              (sb-ext:with-timeout 20 (exercise))))
          (progn
            (it
              "bumps only when public root creation mutates the registry"
              (let ((cl-weave::*root-suite* nil)
                    (cl-weave::*current-suite* nil)
                    (cl-weave::*test-registry-generation* 10))
                (let ((root (cl-weave::root-suite)))
                  (expect cl-weave::*root-suite* :to-be root)
                  (expect cl-weave::*test-registry-generation* :to-be 11)
                  (expect (cl-weave::root-suite) :to-be root)
                  (expect cl-weave::*test-registry-generation* :to-be 11))))
            (it
              "bumps once for root-absent and root-present registration transactions"
              (labels ((exercise (register)
                         (let* ((owners (make-hash-table :test (function eq)))
                           (pathname #P"/tmp/cl-weave-generation-matrix.lisp")
                           (cl-weave::*root-suite* nil)
                           (cl-weave::*current-suite* nil)
                           (cl-weave::*named-suites* (make-hash-table :test (function equal)))
                           (cl-weave::*registration-owners* owners)
                           (cl-weave::*test-registry-generation* 100))
                      (funcall register pathname)
                      (expect cl-weave::*test-registry-generation* :to-be 101)
                      (expect (hash-table-count owners) :to-be 1)
                      (let ((root cl-weave::*root-suite*))
                        (funcall register pathname)
                        (expect cl-weave::*root-suite* :to-be root)
                        (expect cl-weave::*test-registry-generation* :to-be 102)))))
                (exercise
                  (lambda (pathname)
                    (cl-weave::register-suite
                      "registered suite"
                      (lambda ()
                        nil)
                      :location
                      (list :file pathname))))
                (exercise
                  (lambda (pathname)
                    (cl-weave::register-test
                      "registered test"
                      (lambda ()
                        nil)
                      :location
                      (list :file pathname))))
                (dolist (register-hook
                    (list
                      (function cl-weave::register-before-all)
                      (function cl-weave::register-after-all)
                      (function cl-weave::register-before-each)
                      (function cl-weave::register-around-each)
                      (function cl-weave::register-after-each)))
                  (exercise
                    (lambda (pathname)
                      (funcall
                        register-hook
                        (lambda ()
                          nil)
                        :location
                        (list :file pathname)))))))
            (it
              "bumps generation once for direct owner updates without creating roots"
              (let* ((owners (make-hash-table :test (function eq)))
                     (cl-weave::*root-suite* nil)
                     (cl-weave::*registration-owners* owners)
                     (cl-weave::*test-registry-generation* 41)
                     (first
                    (cl-weave::make-test-case
                      :name
                      "first owned"
                      :function
                      (lambda ()
                        nil)))
                     (second
                    (cl-weave::make-test-case
                      :name
                      "second owned"
                      :function
                      (lambda ()
                        nil)))
                     (pathname #P"/tmp/cl-weave-direct-owner.lisp"))
                (expect
                  (cl-weave::record-registration-owner first (list :file pathname))
                  :to-be
                  first)
                (expect cl-weave::*root-suite* :to-be nil)
                (expect cl-weave::*test-registry-generation* :to-be 42)
                (let ((root (cl-weave::make-suite :name "existing")))
                  (setf cl-weave::*root-suite* root)
                  (expect
                    (cl-weave::record-registration-owner second (list :file pathname))
                    :to-be
                    second)
                  (expect cl-weave::*root-suite* :to-be root)
                  (expect cl-weave::*test-registry-generation* :to-be 43))
                (expect (gethash first owners) :to-equal pathname)
                (expect (gethash second owners) :to-equal pathname)))
            (it
              "does not publish no-op reads or failed registration validation"
              (let ((cl-weave::*root-suite* nil)
                    (cl-weave::*current-suite* nil)
                    (cl-weave::*named-suites* (make-hash-table :test (function equal)))
                    (cl-weave::*registration-owners* (make-hash-table :test (function eq)))
                    (cl-weave::*test-registry-generation* 71))
                (expect (cl-weave::find-suite-by-designator "missing") :to-be nil)
                (expect cl-weave::*root-suite* :to-be nil)
                (expect cl-weave::*test-registry-generation* :to-be 71)
                (let ((signaled nil))
                  (handler-case (cl-weave::register-test
                      "invalid"
                      (lambda ()
                        nil)
                      :execution-mode
                      :invalid)
                    (error ()
                      (setf signaled t)))
                  (expect signaled :to-be t))
                (expect cl-weave::*root-suite* :to-be nil)
                (expect cl-weave::*test-registry-generation* :to-be 71)
                (let ((root (cl-weave::make-suite :name "existing")))
                  (setf cl-weave::*root-suite* root)
                  (expect (cl-weave::find-suite-by-designator "missing") :to-be nil)
                  (let ((signaled nil))
                    (handler-case (cl-weave::register-test
                        "invalid"
                        (lambda ()
                          nil)
                        :execution-mode
                        :invalid)
                      (error ()
                        (setf signaled t)))
                    (expect signaled :to-be t))
                  (expect cl-weave::*root-suite* :to-be root)
                  (expect (cl-weave::suite-children root) :to-equal nil)
                  (expect cl-weave::*test-registry-generation* :to-be 71))))
            (it
              "rejects non-string public names before mutation or suite thunk execution"
              (let* ((root (cl-weave::make-suite :name "root"))
                     (current (cl-weave::make-suite :name "current"))
                     (named-suites (make-hash-table :test (function equal)))
                     (owners (make-hash-table :test (function eq)))
                     (cl-weave::*root-suite* root)
                     (cl-weave::*current-suite* current)
                     (cl-weave::*named-suites* named-suites)
                     (cl-weave::*registration-owners* owners)
                     (cl-weave::*test-registry-generation* 71)
                     (suite-thunk-ran nil))
                (let ((signaled nil))
                  (handler-case
                      (cl-weave::register-suite
                        (list "invalid-suite")
                        (lambda ()
                          (setf suite-thunk-ran t)))
                    (error ()
                      (setf signaled t)))
                  (expect signaled :to-be t))
                (let ((signaled nil))
                  (handler-case
                      (cl-weave::register-test
                        (vector "invalid-test")
                        (lambda ()
                          nil))
                    (error ()
                      (setf signaled t)))
                  (expect signaled :to-be t))
                (expect suite-thunk-ran :to-be nil)
                (expect cl-weave::*root-suite* :to-be root)
                (expect cl-weave::*current-suite* :to-be current)
                (expect (cl-weave::suite-children root) :to-equal nil)
                (expect (cl-weave::suite-children current) :to-equal nil)
                (expect (hash-table-count named-suites) :to-be 0)
                (expect (hash-table-count owners) :to-be 0)
                (expect cl-weave::*test-registry-generation* :to-be 71)))
            (it
              "rejects stale registry publication without losing registrations"
              (let ((root (cl-weave::make-suite :name "conflict"))
                    (start (sb-thread:make-semaphore :count 0)))
                (multiple-value-bind (cloned-root cloned-named cloned-owners expected-generation) (cl-weave::clone-test-registry-state)
                  (let ((thread
                        (sb-thread:make-thread
                          (lambda ()
                            (sb-thread:wait-on-semaphore start)
                            (cl-weave::add-child
                              root
                              (cl-weave::make-test-case
                                :name
                                "new"
                                :function
                                (lambda ()
                                  nil)))))))
                    (sb-thread:signal-semaphore start)
                    (sb-thread:join-thread thread))
                  (expect
                    (cl-weave::publish-test-registry-state
                      expected-generation
                      cloned-root
                      cloned-named
                      cloned-owners
                      (1+ expected-generation))
                    :to-be
                    nil)
                  (expect
                    (mapcar (function cl-weave::test-case-name) (cl-weave::suite-children root))
                    :to-equal
                    (quote ("new")))
                  (expect cl-weave::*test-registry-generation* :to-be (1+ expected-generation))))))))))
