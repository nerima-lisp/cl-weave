(in-package #:cl-weave/test)

(describe "run-all input preflight"
  (it "validates every run-all collection option before coverage and suite access"
    (labels ((exercise ()
               (let* ((root (cl-weave::make-suite :name "root"))
                      (limit cl-weave::+maximum-selection-filter-count+)
                      (location-cycle (list #P"/tmp/cl-weave/cycle.lisp"))

(path-cycle (list (list "suite" "test")))
(tag-limit cl-weave::+maximum-tag-count+)
(include-tag-cycle (list :fast))
(exclude-tag-cycle (list :slow))
(shard-cycle (list 1 2))

                      (coverage-require 0)
                      (coverage-reset 0)
                      (coverage-cleanup 0)
                      (suite-root 0)
                      (suite-snapshot 0)
                      (executed 0)
                      (artifact 0))
                 (setf (cdr location-cycle) location-cycle)

(setf (cdr path-cycle) path-cycle)
(setf (cdr include-tag-cycle) include-tag-cycle)
(setf (cdr exclude-tag-cycle) exclude-tag-cycle)
(setf (cddr shard-cycle) shard-cycle)

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
                         (declare (ignore path
                                          include-pathnames
                                          exclude-pathnames))
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
                             (list :name-filter 42)
                             (list :location-filter location-cycle)
                             (list :location-filter
                                   (cons #P"/tmp/cl-weave/dotted.lisp" :tail))
                             (list :location-filter
                                   (make-list (1+ limit)
                                              :initial-element
                                              #P"/tmp/cl-weave/oversized.lisp"))
                             (list :test-path-filter path-cycle)
                             (list :test-path-filter
                                   (cons (list "suite" "test") :tail))
                             (list :test-path-filter
                                   (make-list (1+ limit)
                                              :initial-element nil))

(list :include-tags (cons :fast :tail))
(list :include-tags include-tag-cycle)
(list :include-tags
      (make-list (1+ tag-limit) :initial-element :fast))
(list :exclude-tags exclude-tag-cycle)
(list :exclude-tags
      (make-list (1+ tag-limit) :initial-element :slow))

                             (list :exclude-tags (cons :slow :tail))

(list :shard shard-cycle)
(list :shard
      (make-list (1+ tag-limit) :initial-element 1))
(list :shard
      (list 1
            (1+ cl-weave::+maximum-shard-count+)))

                             (list :order :defined)
                             (list :seed 1.5)
                             (list :bail
                                   (1+ cl-weave::+maximum-bail-limit+))
                             (list :retry
                                   (1+ cl-weave::+maximum-retry-count+))
                             (list :timeout-ms
                                   (1+ cl-weave::+maximum-timeout-ms+))
                             (list :max-workers
                                   (1+ cl-weave::+maximum-worker-count+))))
                     (expect
                      (lambda ()
                        (apply #'cl-weave:run-all
                               :reporter :sexp
                               :stream (make-broadcast-stream)
                               :coverage t
                               :coverage-output "unused.coverage"
                               :coverage-report-directory "unused-report/"
                               :coverage-minimum-expression 0
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
