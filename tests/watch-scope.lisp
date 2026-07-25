(in-package #:cl-weave/tests)

(progn
  (describe "watch scope"
  (it "rejects invalid watch intervals before enumerating watched files"
    (let ((enumeration-count 0))
      (with-mocked-functions
          (((symbol-function (quote cl-weave::watched-system-files))
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (incf enumeration-count)
              (error "watched files must not be enumerated"))))
        (dolist (interval
                 (append (list 0 -1 "0.5")
                         #+sbcl
                         (list (quiet-nan)
                               sb-ext:double-float-positive-infinity)
                         #-sbcl
                         nil))
          (let ((message
                  (handler-case
                      (progn
                        (cl-weave:watch-system "cl-weave"
                                               :interval interval
                                               :once t)
                        nil)
                    (error (condition)
                      (princ-to-string condition)))))
            (expect message
                    :to-equal
                    "cl-weave: watch interval must be a positive finite real number."))))
      (expect enumeration-count :to-be 0)))

  (it "selects changed registered test files for watch reruns even when they were deleted"
    (let* ((test-file #P"/tmp/cl-weave/watch-deleted-test.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "deleted-target"
        :location (list :file (namestring test-file))
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (expect (cl-weave::selective-watch-location-filter (list test-file))
                :to-equal (list test-file)))))

  (it "falls back to the full suite when watch sees new unregistered files"
    (let* ((test-file #P"/tmp/cl-weave/watch-registered-test.lisp")
           (new-file #P"/tmp/cl-weave/watch-new-helper.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "registered-target"
        :location (list :file (namestring test-file))
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (expect (cl-weave::selective-watch-location-filter (list new-file))
                :to-be nil)
        (expect (cl-weave::selective-watch-location-filter (list test-file new-file))
                :to-be nil))))

  (it "selects only tests that declare a changed watch dependency"
    (let* ((test-file #P"/tmp/cl-weave/tests/watch-dependencies.lisp")
           (helper-a #P"/tmp/cl-weave/src/helper-a.lisp")
           (helper-b #P"/tmp/cl-weave/src/helper-b.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "helper-a test"
        :location (list :file (namestring test-file))
        :watch-dependencies (list helper-a)
        :function (lambda () t)))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "helper-b test"
        :location (list :file (namestring test-file))
        :watch-dependencies (list helper-b)
        :function (lambda () t)))
      (multiple-value-bind (paths selectivep)
          (cl-weave::watch-test-path-selection root (list helper-a))
        (expect selectivep :to-be-truthy)
        (expect paths :to-equal '(("watch" "helper-a test"))))
      (multiple-value-bind (paths selectivep)
          (cl-weave::watch-test-path-selection
           root
           (list helper-a #P"/tmp/cl-weave/src/unknown.lisp"))
        (expect paths :to-be nil)
        (expect selectivep :to-be nil))))

  (it "normalizes relative watch dependencies against the test definition file"
    (let ((dependencies
            (cl-weave::normalize-watch-dependencies
             '("../src/parser.lisp")
             '(:file "/tmp/cl-weave/tests/parser-test.lisp"))))
      (expect dependencies
              :to-equal (list #P"/tmp/cl-weave/src/parser.lisp"))))

  (it "builds the watch index from a private snapshot outside the registry lock"
  (let ((cl-weave::*test-registry-generation* 0)
        (cl-weave::*watch-test-dependency-index* nil)
        (cl-weave::*watch-registered-test-files* nil)
        (cl-weave::*watch-index-suite* nil)
        (cl-weave::*watch-index-generation* -1))
    (let* ((suite-name (copy-seq "watch"))
           (test-name (copy-seq "snapshot target"))
           (source-name
             (copy-seq "/tmp/cl-weave/tests/watch-snapshot.lisp"))
           (replacement-source
             #P"/tmp/cl-weave/tests/watch-mutated.lisp")
           (dependency
             #P"/tmp/cl-weave/src/watch-snapshot-helper.lisp")
           (replacement-dependency
             #P"/tmp/cl-weave/src/watch-mutated-helper.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite
             (cl-weave::make-suite :name suite-name :parent root))
           (test
             (cl-weave::make-test-case
              :name test-name
              :location (list :file source-name)
              :watch-dependencies (list dependency)
              :function (lambda () t)))
           (original-test-path
             (symbol-function 'cl-weave::test-path))
           (original-location-pathname
             (symbol-function 'cl-weave::test-location-pathname))
           (original-effective-dependencies
             (symbol-function
              'cl-weave::test-effective-watch-dependencies))
           (snapshot-suite-name nil)
           (snapshot-test-name nil)
           (mutated nil)
           (watch-paths nil))
      (cl-weave::add-child root suite)
      (cl-weave::add-child suite test)
      (labels ((registry-lock-available-p ()
                 #+sb-thread
                 (let ((acquired
                         (handler-case
                             (sb-thread:grab-mutex
                              cl-weave::*test-registry-lock*
                              :waitp nil)
                           (error () nil))))
                   (when acquired
                     (sb-thread:release-mutex
                      cl-weave::*test-registry-lock*))
                   acquired)
                 #-sb-thread
                 t)
               (check-snapshot-object (snapshot live)
                 (expect (registry-lock-available-p) :to-be-truthy)
                 (expect (eq snapshot live) :to-be nil)))
        (with-mocked-functions
            (((symbol-function 'cl-weave::test-path)
              (lambda (snapshot-suite snapshot-test)
                (check-snapshot-object snapshot-suite suite)
                (check-snapshot-object snapshot-test test)
                (setf snapshot-suite-name
                      (cl-weave::suite-name snapshot-suite)
                      snapshot-test-name
                      (cl-weave::test-case-name snapshot-test))
                (unless mutated
                  (setf mutated t
                        (char suite-name 0) #\X
                        (char test-name 0) #\X
                        (getf (cl-weave::test-case-location test) :file)
                        replacement-source
                        (first
                         (cl-weave::test-case-watch-dependencies test))
                        replacement-dependency))
                (funcall original-test-path
                         snapshot-suite snapshot-test)))
             ((symbol-function 'cl-weave::test-location-pathname)
              (lambda (snapshot-test)
                (check-snapshot-object snapshot-test test)
                (funcall original-location-pathname snapshot-test)))
             ((symbol-function
               'cl-weave::test-effective-watch-dependencies)
              (lambda (snapshot-test)
                (check-snapshot-object snapshot-test test)
                (funcall original-effective-dependencies snapshot-test))))
          (multiple-value-bind (index registered-files)
              (cl-weave::ensure-watch-test-index root)
            (expect mutated :to-be-truthy)
            (expect (eq snapshot-suite-name suite-name) :to-be nil)
            (expect (eq snapshot-test-name test-name) :to-be nil)
            (expect snapshot-suite-name :to-equal "watch")
            (expect snapshot-test-name :to-equal "snapshot target")
            (expect suite-name :to-equal "Xatch")
            (expect test-name :to-equal "Xnapshot target")
            (expect registered-files
                    :to-equal
                    (list #P"/tmp/cl-weave/tests/watch-snapshot.lisp"))
            (let ((paths (gethash dependency index)))
              (expect (length paths) :to-be 1)
              (expect (length (first paths)) :to-be 2)
              (expect (first (first paths)) :to-equal "watch")
              (expect (second (first paths))
                      :to-equal "snapshot target")
              (setf (char suite-name 0) #\w
                    (char test-name 0) #\s)
              (setf watch-paths paths))
            (expect (gethash replacement-dependency index)
                    :to-be nil)
            (expect (gethash replacement-source index)
                    :to-be nil)))
        (expect
         (length
          (cl-weave:collect-test-plan
           root :test-path-filter watch-paths))
         :to-be 1)))))

  (it "retries a generation conflict without publishing its stale watch index"
    (let ((cl-weave::*test-registry-generation* 0)
          (cl-weave::*watch-test-dependency-index* nil)
          (cl-weave::*watch-registered-test-files* nil)
          (cl-weave::*watch-index-suite* nil)
          (cl-weave::*watch-index-generation* -1))
      (let* ((source-a #P"/tmp/cl-weave/tests/watch-conflict-a.lisp")
             (source-b #P"/tmp/cl-weave/tests/watch-conflict-b.lisp")
             (dependency-a #P"/tmp/cl-weave/src/watch-conflict-a.lisp")
             (dependency-b #P"/tmp/cl-weave/src/watch-conflict-b.lisp")
             (root (cl-weave::make-suite :name "root"))
             (suite
               (cl-weave::make-suite :name "watch" :parent root))
             (first-test
               (cl-weave::make-test-case
                :name "first"
                :location (list :file source-a)
                :watch-dependencies (list dependency-a)
                :function (lambda () t)))
             (second-test
               (cl-weave::make-test-case
                :name "second"
                :location (list :file source-b)
                :watch-dependencies (list dependency-b)
                :function (lambda () t)))
             (sentinel-suite
               (cl-weave::make-suite :name "sentinel"))
             (sentinel-index
               (make-hash-table :test (function equal)))
             (sentinel-files (list #P"/tmp/cl-weave/sentinel.lisp"))
             (build-count 0)
             (original-build
               (symbol-function
                'cl-weave::build-watch-test-index-unlocked)))
        (cl-weave::add-child root suite)
        (cl-weave::add-child suite first-test)
        (with-mocked-functions
            (((symbol-function
               'cl-weave::build-watch-test-index-unlocked)
              (lambda (snapshot)
                (incf build-count)
                (when (= build-count 2)
                  (expect cl-weave::*watch-index-suite*
                          :to-be sentinel-suite)
                  (expect cl-weave::*watch-test-dependency-index*
                          :to-be sentinel-index)
                  (expect cl-weave::*watch-registered-test-files*
                          :to-be sentinel-files))
                (multiple-value-bind (index registered-files)
                    (funcall original-build snapshot)
                  (when (= build-count 1)
                    (cl-weave::add-child suite second-test)
                    (cl-weave::with-test-registry-lock
                      (setf cl-weave::*watch-index-suite* sentinel-suite
                            cl-weave::*watch-test-dependency-index*
                            sentinel-index
                            cl-weave::*watch-registered-test-files*
                            sentinel-files
                            cl-weave::*watch-index-generation*
                            cl-weave::*test-registry-generation*)))
                  (values index registered-files)))))
          (multiple-value-bind (index registered-files)
              (cl-weave::ensure-watch-test-index root)
            (expect build-count :to-be 2)
            (expect registered-files :to-equal (list source-b source-a))
            (expect (gethash dependency-a index)
                    :to-equal '(("watch" "first")))
            (expect (gethash dependency-b index)
                    :to-equal '(("watch" "second")))
            (expect cl-weave::*watch-index-suite* :to-be root)
            (expect cl-weave::*watch-index-generation*
                    :to-be cl-weave::*test-registry-generation*))))))

  (it "reuses a valid watch index and invalidates it by generation"
    (let ((cl-weave::*test-registry-generation* 0)
          (cl-weave::*watch-test-dependency-index* nil)
          (cl-weave::*watch-registered-test-files* nil)
          (cl-weave::*watch-index-suite* nil)
          (cl-weave::*watch-index-generation* -1))
      (let* ((source-a #P"/tmp/cl-weave/tests/watch-cache-a.lisp")
             (source-b #P"/tmp/cl-weave/tests/watch-cache-b.lisp")
             (dependency #P"/tmp/cl-weave/src/watch-cache-helper.lisp")
             (root (cl-weave::make-suite :name "root"))
             (suite
               (cl-weave::make-suite :name "watch" :parent root))
             (first-test
               (cl-weave::make-test-case
                :name "first"
                :location (list :file source-a)
                :watch-dependencies (list dependency)
                :function (lambda () t)))
             (second-test
               (cl-weave::make-test-case
                :name "second"
                :location (list :file source-b)
                :watch-dependencies (list dependency)
                :function (lambda () t)))
             (build-count 0)
             (original-build
               (symbol-function
                'cl-weave::build-watch-test-index-unlocked)))
        (cl-weave::add-child root suite)
        (cl-weave::add-child suite first-test)
        (cl-weave::add-child suite second-test)
        (with-mocked-functions
            (((symbol-function
               'cl-weave::build-watch-test-index-unlocked)
              (lambda (snapshot)
                (incf build-count)
                (funcall original-build snapshot))))
          (multiple-value-bind (first-index first-files)
              (cl-weave::ensure-watch-test-index root)
            (multiple-value-bind (cached-index cached-files)
                (cl-weave::ensure-watch-test-index root)
              (expect cached-index :to-be first-index)
              (expect cached-files :to-be first-files)
              (expect cached-files :to-equal (list source-b source-a)))
            (multiple-value-bind (paths selectivep)
                (cl-weave::watch-test-path-selection
                 root (list dependency))
              (expect selectivep :to-be-truthy)
              (expect paths
                      :to-equal
                      '(("watch" "second")
                        ("watch" "first"))))
            (expect build-count :to-be 1)
            (cl-weave::note-test-registry-change)
            (multiple-value-bind (rebuilt-index rebuilt-files)
                (cl-weave::ensure-watch-test-index root)
              (expect (eq rebuilt-index first-index) :to-be nil)
              (expect rebuilt-files :to-equal first-files)
              (expect build-count :to-be 2)))))))

  #+sb-thread
  (it "returns the winning cache object when a concurrent build loses publication"
    (let* ((source #P"/tmp/cl-weave/tests/watch-cas-race.lisp")
           (dependency #P"/tmp/cl-weave/src/watch-cas-race-helper.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::make-suite :name "watch" :parent root))
           (test (cl-weave::make-test-case
                  :name "target"
                  :location (list :file source)
                  :watch-dependencies (list dependency)
                  :function (lambda () t)))
           (original-build
             (symbol-function
              'cl-weave::build-watch-test-index-unlocked))
           (first-build-ready
             (sb-thread:make-semaphore :count 0))
           (release-loser
             (sb-thread:make-semaphore :count 0))
           (build-lock
             (sb-thread:make-mutex
              :name "watch index CAS test build lock"))
           (build-count 0)
           (expected-generation nil)
           (old-index nil)
           (old-files nil)
           (old-suite nil)
           (old-generation nil)
           (loser-built-index nil)
           (loser-built-files nil)
           (loser-index nil)
           (loser-files nil)
           (winner-index nil)
           (winner-files nil)
           (loser-error nil)
           (winner-error nil)
           (loser-thread nil)
           (winner-thread nil))
      (cl-weave::add-child root suite)
      (cl-weave::add-child suite test)
      (cl-weave::with-test-registry-lock
        (setf expected-generation
              cl-weave::*test-registry-generation*
              old-index
              cl-weave::*watch-test-dependency-index*
              old-files
              cl-weave::*watch-registered-test-files*
              old-suite
              cl-weave::*watch-index-suite*
              old-generation
              cl-weave::*watch-index-generation*
              cl-weave::*watch-test-dependency-index* nil
              cl-weave::*watch-registered-test-files* nil
              cl-weave::*watch-index-suite* nil
              cl-weave::*watch-index-generation* -1))
      (unwind-protect
          (sb-ext:with-timeout 10
            (with-mocked-functions
                (((symbol-function
                   'cl-weave::build-watch-test-index-unlocked)
                  (lambda (snapshot)
                    (multiple-value-bind (index registered-files)
                        (funcall original-build snapshot)
                      (let ((pausep nil))
                        (sb-thread:with-mutex (build-lock)
                          (incf build-count)
                          (when (= build-count 1)
                            (setf loser-built-index index
                                  loser-built-files registered-files
                                  pausep t)
                            (sb-thread:signal-semaphore
                             first-build-ready)))
                        (when pausep
                          (sb-thread:wait-on-semaphore release-loser))
                        (values index registered-files))))))
              (setf loser-thread
                    (sb-thread:make-thread
                     (lambda ()
                       (handler-case
                           (multiple-value-setq
                               (loser-index loser-files)
                             (cl-weave::ensure-watch-test-index root))
                         (error (condition)
                           (setf loser-error condition))))
                     :name "watch index CAS loser"))
              (sb-thread:wait-on-semaphore first-build-ready)
              (setf winner-thread
                    (sb-thread:make-thread
                     (lambda ()
                       (handler-case
                           (multiple-value-setq
                               (winner-index winner-files)
                             (cl-weave::ensure-watch-test-index root))
                         (error (condition)
                           (setf winner-error condition))))
                     :name "watch index CAS winner"))
              (sb-thread:join-thread winner-thread)
              (sb-thread:signal-semaphore release-loser)
              (sb-thread:join-thread loser-thread)
              (expect loser-error :to-be nil)
              (expect winner-error :to-be nil)
              (expect build-count :to-be 2)
              (expect (eq loser-built-index winner-index) :to-be nil)
              (expect (eq loser-built-files winner-files) :to-be nil)
              (expect loser-index :to-be winner-index)
              (expect loser-files :to-be winner-files)
              (expect cl-weave::*watch-test-dependency-index*
                      :to-be winner-index)
              (expect cl-weave::*watch-registered-test-files*
                      :to-be winner-files)
              (expect cl-weave::*watch-index-suite* :to-be root)
              (expect cl-weave::*watch-index-generation*
                      :to-be expected-generation)
              (expect cl-weave::*test-registry-generation*
                      :to-be expected-generation)))
        (sb-thread:signal-semaphore release-loser)
        (when (and loser-thread
                   (sb-thread:thread-alive-p loser-thread))
          (ignore-errors
            (sb-thread:join-thread loser-thread)))
        (when (and winner-thread
                   (sb-thread:thread-alive-p winner-thread))
          (ignore-errors
            (sb-thread:join-thread winner-thread)))
        (cl-weave::with-test-registry-lock
          (setf cl-weave::*watch-test-dependency-index* old-index
                cl-weave::*watch-registered-test-files* old-files
                cl-weave::*watch-index-suite* old-suite
                cl-weave::*watch-index-generation* old-generation)))))

  (it "bounds watch index rebuilds under repeated generation conflicts"
  (let ((cl-weave::*test-registry-generation* 0)
        (cl-weave::*watch-test-dependency-index* nil)
        (cl-weave::*watch-registered-test-files* nil)
        (cl-weave::*watch-index-suite* nil)
        (cl-weave::*watch-index-generation* -1))
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::make-suite :name "watch" :parent root))
           (test (cl-weave::make-test-case
                  :name "target"
                  :location (list :file #P"/tmp/cl-weave/tests/watch-bounded.lisp")
                  :watch-dependencies
                  (list #P"/tmp/cl-weave/src/watch-bounded-helper.lisp")
                  :function (lambda () t)))
           (build-count 0)
           (original-build
            (symbol-function 'cl-weave::build-watch-test-index-unlocked)))
      (cl-weave::add-child root suite)
      (cl-weave::add-child suite test)
      (with-mocked-functions
          (((symbol-function 'cl-weave::build-watch-test-index-unlocked)
            (lambda (snapshot)
              (incf build-count)
              (multiple-value-prog1
                  (funcall original-build snapshot)
                (cl-weave::note-test-registry-change)))))
        (expect (lambda () (cl-weave::ensure-watch-test-index root))
                :to-throw
                "Test registry changed during 3 watch index build attempts.")
        (expect build-count
                :to-be cl-weave::+watch-test-index-build-attempts+)
        (expect cl-weave::*watch-test-dependency-index* :to-be nil)
        (expect cl-weave::*watch-registered-test-files* :to-be nil)))))

  (it "indexes deeply nested watch suites without recursive traversal"
    (let ((cl-weave::*test-registry-generation* 0)
          (cl-weave::*watch-test-dependency-index* nil)
          (cl-weave::*watch-registered-test-files* nil)
          (cl-weave::*watch-index-suite* nil)
          (cl-weave::*watch-index-generation* -1))
      (let* ((depth 1024)
             (source #P"/tmp/cl-weave/tests/watch-deep.lisp")
             (dependency #P"/tmp/cl-weave/src/watch-deep-helper.lisp")
             (root (cl-weave::make-suite :name "root"))
             (current root))
        (dotimes (index depth)
          (let ((nested
                  (cl-weave::make-suite
                   :name (format nil "level-~D" index)
                   :parent current)))
            (cl-weave::add-child current nested)
            (setf current nested)))
        (cl-weave::add-child
         current
         (cl-weave::make-test-case
          :name "leaf"
          :location (list :file source)
          :watch-dependencies (list dependency)
          :function (lambda () t)))
        (multiple-value-bind (index registered-files)
            (cl-weave::ensure-watch-test-index root)
          (let ((paths (gethash dependency index)))
            (expect registered-files :to-equal (list source))
            (expect (length paths) :to-be 1)
            (expect (length (first paths)) :to-be (1+ depth))
            (expect (first (first paths)) :to-equal "level-0")
            (expect (car (last (first paths))) :to-equal "leaf"))))))

  (it "rejects malformed watch dependency lists without rendering circular input"
  (let* ((limit cl-weave::+maximum-watch-dependency-count+)
         (location '(:file "/tmp/cl-weave/tests/watch-boundary.lisp"))
         (circular (list "circular-secret.lisp"))
         (dotted (cons "dotted.lisp" "tail"))
         (oversized
           (make-list (1+ limit)
                      :initial-element #P"/tmp/cl-weave/src/helper.lisp")))
    (setf (cdr circular) circular)
    (labels ((normalize (dependencies)
               (cl-weave::normalize-watch-dependencies dependencies location)))
      #+sbcl
      (sb-ext:with-timeout 10
        (let ((condition
                (handler-case
                    (progn (normalize circular) nil)
                  (error (caught) caught))))
          (expect condition :to-be-truthy)
          (expect (princ-to-string condition)
                  :to-contain "finite proper list")
          (expect (princ-to-string condition)
                  :to-satisfy
                  (lambda (message)
                    (null (search "circular-secret" message)))))
        (expect (lambda () (normalize dotted))
                :to-throw "finite proper list")
        (expect (lambda () (normalize oversized))
                :to-throw "finite proper list")))))

  (it "accepts the watch dependency limit and preserves canonical first order"
    (let* ((limit cl-weave::+maximum-watch-dependency-count+)
           (helper-a #P"/tmp/cl-weave/src/helper-a.lisp")
           (helper-b #P"/tmp/cl-weave/src/helper-b.lisp")
           (dependencies (make-list limit :initial-element helper-a)))
      (setf (first dependencies) "../src/helper-a.lisp"
            (second dependencies) helper-b
            (third dependencies) "/tmp/cl-weave/src/helper-a.lisp")
      #+sbcl
      (sb-ext:with-timeout 10
        (expect
         (cl-weave::normalize-watch-dependencies
          dependencies
          '(:file "/tmp/cl-weave/tests/watch-boundary.lisp"))
         :to-equal
         (list helper-a helper-b)))))

  (it "selects the maximum registered change set in linear input order"
    (let* ((limit cl-weave::+maximum-watch-dependency-count+)
           (registered-files
             (loop for index below limit
                   collect
                   (make-pathname
                    :name (write-to-string index)
                    :type "lisp"
                    :defaults #P"/tmp/cl-weave/tests/watch.lisp")))
           (changed (reverse (copy-list registered-files)))
           (root (cl-weave::make-suite :name "root")))
      (with-mocked-functions
          (((symbol-function 'cl-weave:root-suite)
            (lambda () root))
           ((symbol-function 'cl-weave::ensure-watch-test-index)
            (lambda (suite)
              (expect suite :to-be root)
              (values (make-hash-table :test #'equal)
                      registered-files))))
        #+sbcl
        (sb-ext:with-timeout 10
          (let ((selected
                  (cl-weave::selective-watch-location-filter changed)))
            (expect selected :to-be changed)
            (expect (first selected) :to-equal (first changed))
            (expect (car (last selected)) :to-equal
                    (car (last changed))))))))

  (it "deduplicates the maximum effective dependency set in source-first order"
    (let* ((limit cl-weave::+maximum-watch-dependency-count+)
           (source #P"/tmp/cl-weave/tests/watch-boundary.lisp")
           (dependencies
             (loop for index below (1- limit)
                   collect
                   (make-pathname
                    :name (write-to-string index)
                    :type "lisp"
                    :defaults #P"/tmp/cl-weave/src/watch.lisp")))
           (test
             (cl-weave::make-test-case
              :name "watch boundary"
              :location (list :file (namestring source))
              :watch-dependencies (cons source dependencies)
              :function (lambda () t))))
      #+sbcl
      (sb-ext:with-timeout 10
        (let ((effective
                (cl-weave::test-effective-watch-dependencies test)))
          (expect (length effective) :to-be limit)
          (expect (first effective) :to-equal source)
          (expect (second effective) :to-equal (first dependencies))
          (expect (car (last effective)) :to-equal
                  (car (last dependencies)))))))

  (it "builds a dependency-filtered watch plan"
    (let* ((test-file #P"/tmp/cl-weave/tests/watch-plan.lisp")
           (helper #P"/tmp/cl-weave/src/watch-helper.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root)))
           (old-state (list (cons helper 1)))
           (new-state (list (cons helper 2))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "dependent"
        :location (list :file (namestring test-file))
        :watch-dependencies (list helper)
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (expect (cl-weave::watch-cycle-plan old-state new-state)
                :to-equal
                (list :changed (list helper)
      :location-filter nil
      :test-path-filter '(("watch" "dependent"))
      :scope :changed-tests
      :initialp nil
      :new-state new-state)))))

  (it "derives a changed-tests watch plan from registered file changes"
    (let* ((test-file #P"/tmp/cl-weave/watch-plan-target.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root)))
           (old-state (list (cons test-file 1)))
           (new-state (list (cons test-file 2))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "plan-target"
        :location (list :file (namestring test-file))
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (expect (cl-weave::watch-cycle-plan old-state new-state)
                :to-equal
                (list :changed (list test-file)
      :location-filter (list test-file)
      :scope :changed-tests
      :initialp nil
      :new-state new-state)))))

  (it "derives a full-suite watch plan for the initial run"
    (let* ((test-file #P"/tmp/cl-weave/watch-plan-initial.lisp")
           (new-state (list (cons test-file 1))))
      (expect (cl-weave::watch-cycle-plan nil new-state)
              :to-equal
              (list :changed (list test-file)
      :location-filter nil
      :scope :full-suite
      :initialp t
      :new-state new-state))))

  (it "skips reruns when watch sees no changed files"
    (let ((calls nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::run-watched-system)
            (lambda (&rest arguments)
              (push arguments calls)
              (error "run-system should not be called when nothing changed"))))
        (multiple-value-bind (next-state continuep)
            (cl-weave::run-watch-cycle
             "cl-weave"
             (list :changed nil
                   :location-filter nil
                   :scope :full-suite
                   :new-state '((#P"/tmp/cl-weave/unchanged.lisp" . 1)))
             :reporter :json
             :stream *standard-output*
             :status-stream *error-output*
             :once nil)
          (expect next-state :to-be nil)
          (expect continuep :to-be-truthy)
          (expect calls :to-equal nil))))))
  (describe "watch dependency NIL fast path"
  (it "returns NIL for an empty dependency list"
    (expect
     (cl-weave::normalize-watch-dependencies
      nil
      '(:file "/tmp/cl-weave/tests/watch-empty.lisp"))
     :to-be nil))))
