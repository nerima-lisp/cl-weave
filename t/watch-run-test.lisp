(in-package #:cl-weave/test)

(describe "watch run"
  (it "returns failure in once mode when the watched run fails"
    (multiple-value-bind (next-state continuep)
        (with-mocked-functions
            (((symbol-function 'cl-weave::run-watched-system)
              (lambda (&rest arguments)
                (declare (ignore arguments))
                nil)))
          (cl-weave::run-watch-cycle
           "cl-weave"
           (list :changed (list #P"/tmp/cl-weave/failed-watch.lisp")
                 :location-filter nil
                 :scope :full-suite
                 :new-state '((#P"/tmp/cl-weave/failed-watch.lisp" . 2)))
           :reporter :json
           :stream *standard-output*
           :status-stream (make-string-output-stream)
           :once t))
      (expect next-state :to-be nil)
      (expect continuep :to-be nil)))

  (it "runs watch mode once without reloading the active test suite"
    (let ((calls nil)
          (output nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave:run-system)
            (lambda (system &key reporter stream name-filter shard order seed
                                  location-filter
                                  bail coverage coverage-output
                                  coverage-report-directory
                                  coverage-include-pathnames coverage-exclude-pathnames
                                  coverage-minimum-expression coverage-minimum-branch
                                  pass-with-no-tests retry timeout-ms
                                  max-workers)
              (declare (ignore stream))
              (declare (ignore coverage-report-directory))
              (declare (ignore coverage-include-pathnames coverage-exclude-pathnames
                               coverage-minimum-expression coverage-minimum-branch))
              (push (list system reporter name-filter shard order seed bail
                          location-filter coverage coverage-output
                          pass-with-no-tests retry timeout-ms max-workers)
                    calls)
              t)))
        (with-captured-output (output stream)
          (expect (cl-weave:watch-system
                   "cl-weave"
                   :reporter :json
                   :stream stream
                   :status-stream stream
                   :name-filter "expect"
                   :shard '(1 2)
                   :order :random
                   :seed 123
                   :bail 1
                   :coverage t
                   :coverage-output "watch.coverage.sexp"
                   :pass-with-no-tests t
                   :retry 2
                   :timeout-ms 250
                   :max-workers 3
                  :once t)
                  :to-be-truthy)))
      (expect calls
              :to-equal '(("cl-weave" :json "expect" (1 2) :random 123 1 nil t
                           "watch.coverage.sexp" t 2 250 3)))
      (expect output :to-contain "FULL-SUITE")
      (expect output :to-contain "cl-weave watch")))

  (it "reruns only changed registered test files in watch mode"
    (let* ((test-file #P"/tmp/cl-weave/watch-target.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root)))
           (states (list (list (cons test-file 1))
                          (list (cons test-file 1))
                          (list (cons test-file 2))))
           (calls nil)
           (output nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "target"
        :location (list :file (namestring test-file))
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (with-mocked-functions
            (((symbol-function 'cl-weave::watched-system-files)
              (lambda (system &key include-dependencies)
                (declare (ignore system include-dependencies))
                (list test-file)))
             ((symbol-function 'cl-weave::file-state)
              (lambda (files)
                (declare (ignore files))
                (or (pop states)
                    (error "missing mocked file state"))))
             ((symbol-function 'cl-weave:run-system)
              (lambda (system &key reporter stream name-filter location-filter shard
                                    order seed bail coverage coverage-output
                                    coverage-report-directory
                                    coverage-include-pathnames coverage-exclude-pathnames
                                    coverage-minimum-expression coverage-minimum-branch
                                    pass-with-no-tests retry timeout-ms
                                    max-workers)
                (declare (ignore stream))
                (declare (ignore coverage-report-directory))
                (declare (ignore coverage-include-pathnames coverage-exclude-pathnames
                                 coverage-minimum-expression coverage-minimum-branch))
                (push (list system reporter name-filter location-filter shard order
                            seed bail coverage coverage-output
                            pass-with-no-tests retry timeout-ms max-workers)
                      calls)
                ;; A real reload re-registers the suite; restore it after
                ;; RUN-WATCHED-SYSTEM's CLEAR-TESTS so the next cycle can
                ;; narrow reruns to registered test files.
                (setf cl-weave::*root-suite* root)
                (when (= (length calls) 2)
                  (throw 'watch-stop t))
                t))
             ((symbol-function 'cl-weave::watch-sleep)
              (lambda (seconds)
                (declare (ignore seconds))
                nil)))
          (with-captured-output (output stream :stop-tag 'watch-stop)
            (cl-weave:watch-system
             "cl-weave"
             :reporter :json
             :stream stream
             :status-stream stream
             :name-filter "watch"
             :once nil))))
      (expect (reverse calls)
              :to-satisfy
              (lambda (value)
                (equal value
                       (list (list "cl-weave" :json "watch" nil nil nil nil nil
                                   nil nil nil nil nil nil)
                             (list "cl-weave" :json "watch" (list test-file)
                                   nil nil nil nil nil nil nil nil nil nil)))))
      (expect output :to-contain "CHANGED-TESTS")))

  (it
  "refreshes the cached ASDF graph after a definition file changes"
  (let* ((definition-file #P"/tmp/cl-weave/cl-weave.asd")
         (test-file #P"/tmp/cl-weave/watch-target.lisp")
         (new-file #P"/tmp/cl-weave/new-target.lisp")
         (root (cl-weave::make-suite :name "root"))
         (suite
        (cl-weave::add-child root (cl-weave::make-suite :name "watch" :parent root)))
         (states
        (list
          (list (cons definition-file 1) (cons test-file 1))
          (list (cons definition-file 1) (cons test-file 1))
          (list (cons definition-file 1) (cons test-file 1))
          (list (cons definition-file 2) (cons test-file 1))
          (list (cons definition-file 2) (cons test-file 1) (cons new-file 1))
          (list (cons definition-file 2) (cons test-file 1) (cons new-file 1))))
         (calls nil)
         (graph-count 0)
         (graph-count-at-change nil)
         (include-dependencies-calls nil)
         (file-state-files nil)
         (file-state-count 0)
         (sleep-count 0)
         (output nil))
    (cl-weave::add-child
      suite
      (cl-weave::make-test-case
        :name
        "target"
        :location
        (list :file (namestring test-file))
        :function
        (lambda ()
          t)))
    (let ((cl-weave::*root-suite* root))
      (with-mocked-functions
        (((symbol-function 'cl-weave::watched-system-files)
            (lambda (system &key include-dependencies)
              (declare (ignore system))
              (incf graph-count)
              (push include-dependencies include-dependencies-calls)
              (if (= graph-count 3) (list definition-file test-file new-file)
                (list definition-file test-file))))
          ((symbol-function 'cl-weave::file-state)
            (lambda (files)
              (incf file-state-count)
              (push files file-state-files)
              (when (= file-state-count 4)
                (setf graph-count-at-change graph-count))
              (or (pop states) (error "missing mocked file state"))))
          ((symbol-function 'cl-weave:run-system)
            (lambda (system
                &key
                reporter
                stream
                name-filter
                location-filter
                shard
                order
                seed
                bail
                coverage
                coverage-output
                coverage-report-directory
                coverage-include-pathnames
                coverage-exclude-pathnames
                coverage-minimum-expression
                coverage-minimum-branch
                pass-with-no-tests
                retry
                timeout-ms
                max-workers)
              (declare (ignore stream))
              (declare (ignore coverage-report-directory))
              (declare (ignore
                  coverage-include-pathnames
                  coverage-exclude-pathnames
                  coverage-minimum-expression
                  coverage-minimum-branch))
              (push
                (list
                  system
                  reporter
                  name-filter
                  location-filter
                  shard
                  order
                  seed
                  bail
                  coverage
                  coverage-output
                  pass-with-no-tests
                  retry
                  timeout-ms
                  max-workers)
                calls)
              (setf cl-weave::*root-suite* root)
              t))
          ((symbol-function 'cl-weave::watch-sleep)
            (lambda (seconds)
              (declare (ignore seconds))
              (incf sleep-count)
              (when (= sleep-count 4)
                (throw 'watch-stop t)))))
        (with-captured-output
          (output stream :stop-tag 'watch-stop)
          (cl-weave:watch-system
            "cl-weave"
            :reporter
            :json
            :stream
            stream
            :status-stream
            stream
            :name-filter
            "watch"
            :include-dependencies
            t
            :once
            nil))))
    (expect graph-count-at-change :to-be 2)
    (expect graph-count :to-be 3)
    (expect (reverse include-dependencies-calls) :to-equal '(t t t))
    (expect
      (reverse calls)
      :to-satisfy
      (lambda (value)
        (equal
          value
          (list
            (list "cl-weave" :json "watch" nil nil nil nil nil nil nil nil nil nil nil)
            (list "cl-weave" :json "watch" nil nil nil nil nil nil nil nil nil nil nil)))))
    (expect
      (car file-state-files)
      :to-equal
      (list definition-file test-file new-file))
    (expect
      (second file-state-files)
      :to-equal
      (list definition-file test-file new-file))
    (expect output :to-contain "FULL")))

  (it "falls back to the full suite when non-test files change in watch mode"
    (let* ((test-file #P"/tmp/cl-weave/watch-suite-test.lisp")
           (impl-file #P"/tmp/cl-weave/watch-impl.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root)))
           (states (list (list (cons test-file 1)
                               (cons impl-file 1))
                         (list (cons test-file 1)
                               (cons impl-file 1))
                         (list (cons test-file 1)
                               (cons impl-file 2))))
           (calls nil)
           (output nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "target"
        :location (list :file (namestring test-file))
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (with-mocked-functions
            (((symbol-function 'cl-weave::watched-system-files)
              (lambda (system &key include-dependencies)
                (declare (ignore system include-dependencies))
                (list test-file impl-file)))
             ((symbol-function 'cl-weave::file-state)
              (lambda (files)
                (declare (ignore files))
                (or (pop states)
                    (error "missing mocked file state"))))
             ((symbol-function 'cl-weave:run-system)
              (lambda (system &key reporter stream name-filter location-filter shard
                                    order seed bail coverage coverage-output
                                    coverage-report-directory
                                    coverage-include-pathnames coverage-exclude-pathnames
                                    coverage-minimum-expression coverage-minimum-branch
                                    pass-with-no-tests retry timeout-ms
                                    max-workers)
                (declare (ignore stream))
                (declare (ignore coverage-report-directory))
                (declare (ignore coverage-include-pathnames coverage-exclude-pathnames
                                 coverage-minimum-expression coverage-minimum-branch))
                (push (list system reporter name-filter location-filter shard order
                            seed bail coverage coverage-output
                            pass-with-no-tests retry timeout-ms max-workers)
                      calls)
                ;; A real reload re-registers the suite; restore it after
                ;; RUN-WATCHED-SYSTEM's CLEAR-TESTS so the next cycle can
                ;; narrow reruns to registered test files.
                (setf cl-weave::*root-suite* root)
                (when (= (length calls) 2)
                  (throw 'watch-stop t))
                t))
             ((symbol-function 'cl-weave::watch-sleep)
              (lambda (seconds)
                (declare (ignore seconds))
                nil)))
          (with-captured-output (output stream :stop-tag 'watch-stop)
            (cl-weave:watch-system
             "cl-weave"
             :reporter :json
             :stream stream
             :status-stream stream
             :name-filter "watch"
             :once nil))))
      (expect (reverse calls)
              :to-satisfy
              (lambda (value)
                (equal value
                       (list (list "cl-weave" :json "watch" nil nil nil nil nil
                                   nil nil nil nil nil nil)
                             (list "cl-weave" :json "watch" nil nil nil nil nil
                                   nil nil nil nil nil nil)))))
      (expect output :to-contain "FULL-SUITE"))))
