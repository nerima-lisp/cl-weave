(in-package #:cl-weave/test)

(let ((cl-weave::*snapshot-session* nil)) #+sb-thread
(describe "snapshot concurrency"
  (matcher-pass-cases
    ("snapshot APIs preserve concurrent mixed updates"
     (let* ((snapshot-root (make-test-temporary-directory "snapshot-concurrency"))
            (cl-weave::*snapshot-directory* snapshot-root)
            (cl-weave::*snapshot-file-name* "concurrent.snapshots")
            (lock-registry (make-hash-table :test #'equal))
            (cl-weave::*snapshot-file-locks* lock-registry)
            (thread-count 64)
            (ready (sb-thread:make-semaphore :count 0))
            (release (sb-thread:make-semaphore :count 0))
            (error-lock (sb-thread:make-mutex :name "snapshot test errors"))
            (errors nil)
            (threads nil))
       (unwind-protect
            (progn
              (expect (cl-weave::write-snapshot-file
                       (list (cons "direct-entry" "direct-value")))
                      :to-be-null)
              (expect (cl-weave::read-snapshot-file)
                      :to-equal
                      (list (cons "direct-entry" "direct-value")))
              (setf threads
                    (loop for index below thread-count
                          collect
                          (let ((worker-index index))
                            (sb-thread:make-thread
                             (lambda ()
                               (let ((cl-weave::*snapshot-directory* snapshot-root)
                                     (cl-weave::*snapshot-file-name*
                                       "concurrent.snapshots")
                                     (cl-weave::*snapshot-file-locks* lock-registry)
                                     (cl-weave::*update-snapshots* t))
                                 (handler-case
                                     (progn
                                       (sb-thread:signal-semaphore ready)
                                       (sb-thread:wait-on-semaphore release)
                                       (if (evenp worker-index)
                                           (cl-weave::snapshot-match-or-update-p
                                            (list :single worker-index)
                                            (list
                                             (format nil "single/~D"
                                                     worker-index)))
                                           (cl-weave::snapshot-sequence-match-or-update-p
                                            (vector
                                             (list :sequence worker-index :step 0)
                                             (list :sequence worker-index :step 1))
                                            (list
                                             (format nil "sequence/~D"
                                                     worker-index)))))
                                   (error (condition)
                                     (sb-thread:with-mutex (error-lock)
                                       (push condition errors))))))
                             :name (format nil "snapshot-worker-~D"
                                           worker-index)))))
              (loop repeat thread-count
                    do (sb-thread:wait-on-semaphore ready))
              (loop repeat thread-count
                    do (sb-thread:signal-semaphore release))
              (mapc #'sb-thread:join-thread threads)
              (expect errors :to-be-null)
              (let ((entries (cl-weave::read-snapshot-file)))
                (expect (length entries) :to-be (1+ (* 3 (/ thread-count 2))))
                (expect (cl-weave:snapshot-entries) :to-equal entries))
              (multiple-value-bind (value present-p)
                  (cl-weave:snapshot-value "direct-entry")
                (expect value :to-equal "direct-value")
                (expect present-p :to-be-truthy))
              (dotimes (index thread-count)
                (if (evenp index)
                    (multiple-value-bind (value present-p)
                        (cl-weave:snapshot-value
                         (format nil "single/~D" index))
                      (expect value
                              :to-equal
                              (cl-weave::snapshot-string
                               (list :single index)))
                      (expect present-p :to-be-truthy))
                    (dotimes (step 2)
                      (multiple-value-bind (value present-p)
                          (cl-weave:snapshot-value
                           (format nil "sequence/~D[~D]" index step))
                        (expect value
                                :to-equal
                                (cl-weave::snapshot-string
                                 (list :sequence index :step step)))
                        (expect present-p :to-be-truthy)))))
              (multiple-value-bind (value present-p)
                  (cl-weave:snapshot-value "missing-snapshot-key")
                (expect value :to-be-null)
                (expect present-p :to-be-falsy))
              (expect (lambda () (cl-weave:snapshot-value :not-a-string))
                      :to-throw)
              (expect (hash-table-count lock-registry) :to-be 0))
         (when threads
           (loop repeat thread-count
                 do (sb-thread:signal-semaphore release))
           (dolist (thread threads)
             (when (sb-thread:thread-alive-p thread)
               (sb-thread:terminate-thread thread))))
         (uiop:delete-directory-tree snapshot-root
                                     :validate t
                                     :if-does-not-exist :ignore))))

    ("snapshot file locks serialize the same path"
     (let* ((snapshot-root (make-test-temporary-directory "snapshot-file-lock"))
            (file (merge-pathnames "missing/same.snapshots" snapshot-root))
            (lock-registry (make-hash-table :test #'equal))
            (cl-weave::*snapshot-file-locks* lock-registry)
            (thread-count 16)
            (ready (sb-thread:make-semaphore :count 0))
            (release (sb-thread:make-semaphore :count 0))
            (counter-lock (sb-thread:make-mutex :name "snapshot test counter"))
            (error-lock (sb-thread:make-mutex :name "snapshot lock test errors"))
            (inside 0)
            (peak 0)
            (errors nil)
            (threads nil))
       (unwind-protect
            (progn
              (setf threads
                    (loop for index below thread-count
                          collect
                          (let ((worker-index index))
                            (sb-thread:make-thread
                             (lambda ()
                               (let ((cl-weave::*snapshot-file-locks* lock-registry))
                                 (handler-case
                                     (progn
                                       (sb-thread:signal-semaphore ready)
                                       (sb-thread:wait-on-semaphore release)
                                       (cl-weave::call-with-snapshot-file-lock
                                        file
                                        (lambda ()
                                          (sb-thread:with-mutex (counter-lock)
                                            (incf inside)
                                            (setf peak (max peak inside)))
                                          (sleep 0.005)
                                          (sb-thread:with-mutex (counter-lock)
                                            (decf inside)))))
                                   (error (condition)
                                     (sb-thread:with-mutex (error-lock)
                                       (push condition errors))))))
                             :name (format nil "snapshot-lock-worker-~D"
                                           worker-index)))))
              (loop repeat thread-count
                    do (sb-thread:wait-on-semaphore ready))
              (loop repeat thread-count
                    do (sb-thread:signal-semaphore release))
              (mapc #'sb-thread:join-thread threads)
              (expect errors :to-be-null)
              (expect peak :to-be 1)
              (expect (hash-table-count lock-registry) :to-be 0))
         (when threads
           (loop repeat thread-count
                 do (sb-thread:signal-semaphore release))
           (dolist (thread threads)
             (when (sb-thread:thread-alive-p thread)
               (sb-thread:terminate-thread thread))))
         (uiop:delete-directory-tree snapshot-root
                                     :validate t
                                     :if-does-not-exist :ignore))))

    ("snapshot file lock registry releases unique paths"
     (let* ((snapshot-root (make-test-temporary-directory "snapshot-lock-registry"))
            (lock-registry (make-hash-table :test #'equal))
            (cl-weave::*snapshot-file-locks* lock-registry))
       (unwind-protect
            (progn
              (dotimes (index 4096)
                (cl-weave::call-with-snapshot-file-lock
                 (merge-pathnames
                  (format nil "missing/path-~D.snapshots" index)
                  snapshot-root)
                 (lambda () nil)))
              (expect (hash-table-count lock-registry) :to-be 0))
         (uiop:delete-directory-tree snapshot-root
                                     :validate t
                                     :if-does-not-exist :ignore)))))))

(let ((cl-weave::*snapshot-session* nil)) #+sbcl
(describe "snapshot file permissions"
  (it "creates a 0600 snapshot under umask 022"
    (let* ((snapshot-root
             (make-test-temporary-directory "snapshot-permissions-new"))
           (cl-weave::*snapshot-directory* snapshot-root)
           (cl-weave::*snapshot-file-name* "permissions.snapshots")
           (file (cl-weave::snapshot-file-pathname))
           old-umask)
      (unwind-protect
           (progn
             (setf old-umask (sb-posix:umask #o022))
             (unwind-protect
                  (cl-weave::write-snapshot-file
                   (list (cons "permission" "new")))
               (sb-posix:umask old-umask)
               (setf old-umask nil))
             (expect
              (logand #o777
                      (sb-posix:stat-mode
                       (sb-posix:stat (namestring file))))
              :to-be
              #o600))
        (when old-umask
          (sb-posix:umask old-umask))
        (uiop:delete-directory-tree snapshot-root
                                    :validate t
                                    :if-does-not-exist :ignore))))

  (it "does not broaden existing 0600 or 0400 snapshots"
  (dolist (mode (list #o600 #o400))
    (let* ((snapshot-root
             (make-test-temporary-directory
              (format nil "snapshot-permissions-existing-~O" mode)))
           (cl-weave::*snapshot-directory* snapshot-root)
           (cl-weave::*snapshot-file-name* "permissions.snapshots")
           (file (cl-weave::snapshot-file-pathname))
           old-umask)
      (unwind-protect
           (progn
             (ensure-directories-exist file)
             (with-open-file (stream file
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (write-line "old snapshot" stream))
             (sb-posix:chmod (namestring file) mode)
             (setf old-umask (sb-posix:umask #o022))
             (unwind-protect
                  (cl-weave::write-snapshot-file
                   (list (cons "permission" "replacement")))
               (sb-posix:umask old-umask)
               (setf old-umask nil))
             (expect
              (logand #o777
                      (sb-posix:stat-mode
                       (sb-posix:stat (namestring file))))
              :to-be
              mode))
        (when old-umask
          (sb-posix:umask old-umask))
        (uiop:delete-directory-tree snapshot-root
                                    :validate t
                                    :if-does-not-exist :ignore)))))))

(describe "snapshot sessions"
  (it "makes staged updates visible and flushes them on scope exit"
    (with-test-snapshot-directory
        (:prefix "snapshot-session" :file-name "session.snapshots" :update-snapshots t)
      (let ((cl-weave::*snapshot-session* nil))
        (cl-weave::call-with-snapshot-session
         (lambda ()
           (expect (cl-weave::snapshot-match-or-update-p (list :value 1) (list "session/first"))
                   :to-be-truthy)
           (expect (cl-weave::snapshot-match-or-update-p (list :value 2) (list "session/second"))
                   :to-be-truthy)
           (multiple-value-bind (value present-p)
               (cl-weave:snapshot-value "session/first")
             (expect value :to-equal (cl-weave::snapshot-string (list :value 1)))
             (expect present-p :to-be-truthy)))))
      (expect (cl-weave:snapshot-entries)
              :to-equal
              (list (cons "session/first" (cl-weave::snapshot-string (list :value 1)))
                    (cons "session/second" (cl-weave::snapshot-string (list :value 2))))))))

(it "flushes staged updates when execution exits with an error"
  (with-test-snapshot-directory
      (:prefix "snapshot-session-unwind" :file-name "unwind.snapshots" :update-snapshots t)
    (handler-case
        (let ((cl-weave::*snapshot-session* nil))
          (cl-weave::call-with-snapshot-session
           (lambda ()
             (cl-weave::snapshot-match-or-update-p (list :value :unwind) (list "session/unwind"))
             (error "expected test error"))))
      (error () nil))
    (multiple-value-bind (value present-p)
        (cl-weave:snapshot-value "session/unwind")
      (expect value :to-equal (cl-weave::snapshot-string (list :value :unwind)))
      (expect present-p :to-be-truthy))))
