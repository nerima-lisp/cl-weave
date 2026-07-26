(in-package #:cl-weave/test)

(describe "collection snapshot before coverage"
  (it "uses one copied collection preflight across coverage setup"
    (let* ((root (cl-weave::make-suite :name "root"))
           (target #P"/tmp/cl-weave/collection-snapshot.lisp")
           (other #P"/tmp/cl-weave/collection-mutated.lisp")
           (name-filter (copy-seq "runs"))
           (location-filter (list target))
           (path-component (copy-seq "runs"))
           (test-path-filter (list (list path-component)))
           (include-tag (copy-seq "fast"))
           (exclude-tag (copy-seq "slow"))
           (include-tags (list include-tag))
           (exclude-tags (list exclude-tag))
           (coverage-require 0)
           (coverage-reset 0)
           (suite-root 0)
           (suite-snapshot 0)
           (executed 0))
      (cl-weave::add-child
       root
       (cl-weave::make-test-case
        :name "runs"
        :location (list :file (namestring target))
        :tags '("FAST")
        :function (lambda () (incf executed))))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda ()
              (incf coverage-require)
              (setf (char name-filter 0) #\x
                    (car location-filter) other
                    (char path-component 0) #\x
                    (char include-tag 0) #\x
                    (car exclude-tags) "fast")))
           ((symbol-function 'cl-weave:reset-coverage)
            (lambda () (incf coverage-reset)))
           ((symbol-function 'cl-weave:root-suite)
            (lambda ()
              (incf suite-root)
              root))
           ((symbol-function 'cl-weave::snapshot-suite)
            (lambda (suite)
              (incf suite-snapshot)
              suite)))
        (expect
         (cl-weave:run-all
          :reporter :sexp
          :stream (make-broadcast-stream)
          :coverage t
          :name-filter name-filter
          :location-filter location-filter
          :test-path-filter test-path-filter
          :include-tags include-tags
          :exclude-tags exclude-tags)
         :to-be-truthy))
      (expect coverage-require :to-be 1)
      (expect coverage-reset :to-be 1)
      (expect suite-root :to-be 1)
      (expect suite-snapshot :to-be 1)
      (expect executed :to-be 1))))

(describe "unconsumed coverage filters"
  (it "ignores source filters when no coverage artifact consumes them"
    (labels ((exercise ()
               (let ((root (cl-weave::make-suite :name "root"))
                     (include-cycle (list #P"/tmp/cl-weave/include-cycle/"))
                     (coverage-require 0)
                     (coverage-reset 0)
                     (coverage-cleanup 0)
                     (suite-root 0)
                     (suite-snapshot 0)
                     (executed 0)
                     (artifact 0))
                 (setf (cdr include-cycle) include-cycle)
                 (cl-weave::add-child
                  root
                  (cl-weave::make-test-case
                   :name "runs"
                   :function (lambda () (incf executed))))
                 (with-mocked-functions
                     (((symbol-function 'cl-weave::require-coverage-support)
                       (lambda () (incf coverage-require)))
                      ((symbol-function 'cl-weave:reset-coverage)
                       (lambda () (incf coverage-reset)))
                      ((symbol-function 'cl-weave:coverage-statistics)
                       (lambda (&key include-pathnames exclude-pathnames)
                         (declare (ignore include-pathnames exclude-pathnames))
                         (incf coverage-cleanup)))
                      ((symbol-function 'cl-weave::save-coverage-report)
                       (lambda (path &key include-pathnames exclude-pathnames)
                         (declare (ignore path include-pathnames exclude-pathnames))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:save-coverage)
                       (lambda (path)
                         (declare (ignore path))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:root-suite)
                       (lambda ()
                         (incf suite-root)
                         root))
                      ((symbol-function 'cl-weave::snapshot-suite)
                       (lambda (suite)
                         (incf suite-snapshot)
                         suite)))
                   (expect
                    (cl-weave:run-all
                     :reporter :sexp
                     :stream (make-broadcast-stream)
                     :coverage t
                     :coverage-reset :enabled
                     :coverage-include-pathnames include-cycle
                     :coverage-exclude-pathnames
                     (cons #P"/tmp/cl-weave/exclude/" :tail))
                    :to-be-truthy))
                 (expect coverage-require :to-be 1)
                 (expect coverage-reset :to-be 1)
                 (expect coverage-cleanup :to-be 0)
                 (expect suite-root :to-be 1)
                 (expect suite-snapshot :to-be 1)
                 (expect executed :to-be 1)
                 (expect artifact :to-be 0))))
      #+sbcl
      (sb-ext:with-timeout 10
        (exercise))
      #-sbcl
      (exercise))))

(describe "coverage boundary controls"
  (it "accepts threshold boundaries and generalized coverage controls"
  (let* ((root (cl-weave::make-suite :name "root"))
         (source-pathnames (list "src/"))
         (expected-source
           (make-pathname
            :defaults
            (uiop:ensure-absolute-pathname #P"src/" (uiop:getcwd))))
         (coverage-require 0)
         (coverage-reset 0)
         (coverage-cleanup 0)
         (suite-root 0)
         (suite-snapshot 0)
         (executed 0)
         (observed-source-pathnames nil))
    (cl-weave::add-child
     root
     (cl-weave::make-test-case
      :name "runs"
      :function (lambda () (incf executed))))
    (with-mocked-functions
        (((symbol-function 'cl-weave::require-coverage-support)
          (lambda ()
            (incf coverage-require)
            (setf (car source-pathnames) 42)))
         ((symbol-function 'cl-weave:reset-coverage)
          (lambda () (incf coverage-reset)))
         ((symbol-function 'cl-weave:coverage-statistics)
          (lambda (&key include-pathnames exclude-pathnames)
            (declare (ignore exclude-pathnames))
            (incf coverage-cleanup)
            (setf observed-source-pathnames include-pathnames)
            '(:expression-covered 0 :expression-total 0
              :branch-covered 0 :branch-total 0)))
         ((symbol-function 'cl-weave:root-suite)
          (lambda ()
            (incf suite-root)
            root))
         ((symbol-function 'cl-weave::snapshot-suite)
          (lambda (suite)
            (incf suite-snapshot)
            suite)))
      (expect
       (cl-weave:run-all
        :reporter :sexp
        :stream (make-broadcast-stream)
        :coverage :enabled
        :coverage-reset :enabled
        :coverage-include-pathnames source-pathnames
        :coverage-minimum-expression 0
        :coverage-minimum-branch 100)
       :to-be-truthy))
    (expect coverage-require :to-be 1)
    (expect coverage-reset :to-be 1)
    (expect coverage-cleanup :to-be 1)
    (expect suite-root :to-be 1)
    (expect suite-snapshot :to-be 1)
    (expect executed :to-be 1)
    (expect observed-source-pathnames
            :to-satisfy
            (lambda (pathnames)
              (and (= (length pathnames) 1)
                   (pathnamep (first pathnames))
                   (uiop:absolute-pathname-p (first pathnames))
                   (equal (first pathnames) expected-source)))))))

(describe "coverage disabled preflight"
  (it "ignores invalid coverage-only options when coverage is disabled"
    (labels ((exercise ()
               (let ((root (cl-weave::make-suite :name "root"))
                     (include-cycle (list #P"/tmp/cl-weave/include-cycle/"))
                     (coverage-require 0)
                     (coverage-reset 0)
                     (coverage-cleanup 0)
                     (suite-root 0)
                     (suite-snapshot 0)
                     (executed 0)
                     (artifact 0))
                 (setf (cdr include-cycle) include-cycle)
                 (cl-weave::add-child
                  root
                  (cl-weave::make-test-case
                   :name "runs"
                   :function (lambda () (incf executed))))
                 (with-mocked-functions
                     (((symbol-function 'cl-weave::require-coverage-support)
                       (lambda () (incf coverage-require)))
                      ((symbol-function 'cl-weave:reset-coverage)
                       (lambda () (incf coverage-reset)))
                      ((symbol-function 'cl-weave:coverage-statistics)
                       (lambda (&key include-pathnames exclude-pathnames)
                         (declare (ignore include-pathnames exclude-pathnames))
                         (incf coverage-cleanup)))
                      ((symbol-function 'cl-weave::save-coverage-report)
                       (lambda (path &key include-pathnames exclude-pathnames)
                         (declare (ignore path include-pathnames exclude-pathnames))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:save-coverage)
                       (lambda (path)
                         (declare (ignore path))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:root-suite)
                       (lambda ()
                         (incf suite-root)
                         root))
                      ((symbol-function 'cl-weave::snapshot-suite)
                       (lambda (suite)
                         (incf suite-snapshot)
                         suite)))
                   (expect
                    (cl-weave:run-all
                     :reporter :sexp
                     :stream (make-broadcast-stream)
                     :coverage nil
                     :coverage-output 42
                     :coverage-report-directory 42
                     :coverage-reset :arbitrary
                     :coverage-include-pathnames include-cycle
                     :coverage-exclude-pathnames
                     (cons #P"/tmp/cl-weave/exclude/" :tail)
                     :coverage-minimum-expression #C(1 1)
                     :coverage-minimum-branch 101)
                    :to-be-truthy))
                 (expect coverage-require :to-be 0)
                 (expect coverage-reset :to-be 0)
                 (expect coverage-cleanup :to-be 0)
                 (expect suite-root :to-be 1)
                 (expect suite-snapshot :to-be 1)
                 (expect executed :to-be 1)
                 (expect artifact :to-be 0))))
      #+sbcl
      (sb-ext:with-timeout 10
        (exercise))
      #-sbcl
      (exercise))))

(describe "coverage input preflight"
  (it "validates coverage options before lifecycle suite and artifacts"
    (labels ((exercise ()
               (let* ((root (cl-weave::make-suite :name "root"))
                      (limit cl-weave::+maximum-selection-filter-count+)
                      (include-cycle (list #P"/tmp/cl-weave/include-cycle/"))
                      (coverage-require 0)
                      (coverage-reset 0)
                      (coverage-cleanup 0)
                      (suite-root 0)
                      (suite-snapshot 0)
                      (executed 0)
                      (artifact 0))
                 (setf (cdr include-cycle) include-cycle)
                 (add-tripwire-test-case root (lambda () (incf executed)))
                 (with-mocked-functions
                     (((symbol-function 'cl-weave::require-coverage-support)
                       (lambda () (incf coverage-require)))
                      ((symbol-function 'cl-weave:reset-coverage)
                       (lambda () (incf coverage-reset)))
                      ((symbol-function 'cl-weave:coverage-statistics)
                       (lambda (&key include-pathnames exclude-pathnames)
                         (declare (ignore include-pathnames exclude-pathnames))
                         (incf coverage-cleanup)
                         '(:expression-covered 0 :expression-total 0
                           :branch-covered 0 :branch-total 0)))
                      ((symbol-function 'cl-weave::save-coverage-report)
                       (lambda (path &key include-pathnames exclude-pathnames)
                         (declare (ignore path include-pathnames exclude-pathnames))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:save-coverage)
                       (lambda (path)
                         (declare (ignore path))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:root-suite)
                       (lambda ()
                         (incf suite-root)
                         root))
                      ((symbol-function 'cl-weave::snapshot-suite)
                       (lambda (suite)
                         (incf suite-snapshot)
                         suite)))
                   (dolist (arguments
                            (list
                             (list :coverage-output 42)
                             (list :coverage-report-directory 42)
                             (list :coverage-minimum-expression -1)
                             (list :coverage-minimum-branch 101)
                             (list :coverage-minimum-expression #C(1 1))
                             #+sbcl
                             (list :coverage-minimum-expression
                                   (sb-kernel:make-double-float #x7ff00000 0))
                             (list :coverage-report-directory "unused-report/"
                                   :coverage-include-pathnames include-cycle)
                             (list :coverage-minimum-expression 0
                                   :coverage-exclude-pathnames
                                   (cons #P"/tmp/cl-weave/exclude/" :tail))
                             (list :coverage-report-directory "unused-report/"
                                   :coverage-include-pathnames
                                   (make-list (1+ limit)
                                              :initial-element
                                              #P"/tmp/cl-weave/include/"))
                             (list :coverage-minimum-branch 100
                                   :coverage-exclude-pathnames (list 42))))
                     (expect
                      (lambda ()
                        (apply #'cl-weave:run-all
                               :reporter :sexp
                               :stream (make-broadcast-stream)
                               :coverage :enabled
                               arguments))
                      :to-throw)))
                 (expect coverage-require :to-be 0)
                 (expect coverage-reset :to-be 0)
                 (expect coverage-cleanup :to-be 0)
                 (expect suite-root :to-be 0)
                 (expect suite-snapshot :to-be 0)
                 (expect executed :to-be 0)
                 (expect artifact :to-be 0))))
      #+sbcl
      (sb-ext:with-timeout 10
        (exercise))
      #-sbcl
      (exercise))))
