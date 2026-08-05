




(in-package #:cl-weave/test)
(defun exercise-coverage-report-failure (finder)
  (let ((directory (make-test-temporary-directory "coverage-report-failure"))
        (cl-weave::*coverage-report-finder* finder))
    (handler-case
        (progn
          (cl-weave::save-coverage-report directory)
          nil)
      (error (condition)
        condition))))

(describe "coverage"
  (it "filters coverage sources with exclusions taking precedence"
    (let* ((root (make-test-temporary-directory "coverage-filter"))
           (included (merge-pathnames #P"src/included.lisp" root))
           (excluded-directory (merge-pathnames #P"src/generated/" root))
           (excluded (merge-pathnames #P"generated.lisp" excluded-directory))
           (matcher (cl-weave::coverage-source-matcher
                     (list (merge-pathnames #P"src/" root))
                     (list excluded-directory))))
      (expect (funcall matcher included) :to-be-truthy)
      (expect (funcall matcher excluded) :to-be nil)))

  (it "accepts zero-item coverage and rejects unmet thresholds"
    (expect (cl-weave::check-coverage-thresholds
             '(:expression-covered 0 :expression-total 0
               :branch-covered 0 :branch-total 0)
             100 100)
            :to-be-truthy)
    (expect (lambda ()
              (cl-weave::check-coverage-thresholds
               '(:expression-covered 7 :expression-total 10
                 :branch-covered 8 :branch-total 10)
               75 80))
            :to-throw "Coverage threshold failed"))

  (it "computes coverage percentage, treating zero-total as fully covered"
    (expect (cl-weave::coverage-percentage 0 0) :to-be 100.0)
    (expect (cl-weave::coverage-percentage 5 10) :to-be 50.0)
    (expect (cl-weave::coverage-percentage 10 10) :to-be 100.0))

  (it "validates coverage thresholds as finite reals between 0 and 100"
    (expect (cl-weave::valid-coverage-threshold-p 0) :to-be-truthy)
    (expect (cl-weave::valid-coverage-threshold-p 100) :to-be-truthy)
    (expect (cl-weave::valid-coverage-threshold-p 57.5) :to-be-truthy)
    (expect (cl-weave::valid-coverage-threshold-p -1) :to-be nil)
    (expect (cl-weave::valid-coverage-threshold-p 101) :to-be nil)
    (expect (cl-weave::valid-coverage-threshold-p "80") :to-be nil)
    (expect (cl-weave::valid-coverage-threshold-p #C(1 1)) :to-be nil))

  (it "normalizes coverage thresholds, passing NIL through and rejecting invalid values"
    (expect (cl-weave::normalize-coverage-threshold nil "minimum") :to-be nil)
    (expect (cl-weave::normalize-coverage-threshold 90 "minimum") :to-be 90)
    (expect (lambda () (cl-weave::normalize-coverage-threshold 101 "minimum"))
            :to-throw "minimum must be a finite real number between 0 and 100"))

  (it "normalizes coverage pathname designators, passing NIL through and copying inputs"
    (expect (cl-weave::normalize-coverage-pathname-designator nil "output")
            :to-be nil)
    (expect (cl-weave::normalize-coverage-pathname-designator "report.html" "output")
            :to-equal "report.html")
    (expect (cl-weave::normalize-coverage-pathname-designator #P"report.html" "output")
            :to-equal #P"report.html")
    (expect (lambda ()
              (cl-weave::normalize-coverage-pathname-designator 42 "output"))
            :to-throw "output must be a pathname designator or NIL"))

  (it "enforces thresholds without requiring an HTML report"
    (with-mocked-functions
        (((symbol-function 'cl-weave::require-coverage-support) (lambda () t))
         ((symbol-function 'cl-weave:reset-coverage) (lambda () t))
         ((symbol-function 'cl-weave:coverage-statistics)
          (lambda (&key include-pathnames exclude-pathnames)
            (declare (ignore include-pathnames exclude-pathnames))
            '(:expression-covered 1 :expression-total 2
              :branch-covered 1 :branch-total 2))))
      (expect (lambda ()
                (cl-weave::call-with-coverage
                 t nil nil t (lambda () t)
                 :minimum-expression 75))
              :to-throw "Coverage threshold failed")))

  (it "reports coverage support as a safe boolean"
    (expect (cl-weave:coverage-support-available-p)
            :to-satisfy (lambda (value)
                          (or (eq value t) (eq value nil)))))

  (it "does not initialize or save coverage when coverage is disabled"
    (let ((calls nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda ()
              (push :require calls)))
           ((symbol-function 'cl-weave::save-coverage-report)
            (lambda (path)
              (push (list :report path) calls)))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls))))
        (expect (multiple-value-list
                 (cl-weave::call-with-coverage
                  nil "coverage.dat" "coverage-report/" t
                  (lambda ()
                    (values :first :second))))
                :to-equal '(:first :second)))
      (expect calls :to-be-null)))

  (it "wraps run-all with coverage reset and save hooks"
    (let ((root (cl-weave::make-suite :name "root"))
          (calls nil))
      (cl-weave::add-child
       root
       (cl-weave::make-test-case
        :name "covered"
        :function (lambda ()
                    (push :test calls))))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda ()
              (push :require calls)
              t))
           ((symbol-function 'cl-weave:reset-coverage)
            (lambda ()
              (push :reset calls)
              t))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls)
              path)))
        (let ((cl-weave::*root-suite* root))
          (expect (with-output-to-string (stream)
                    (expect (cl-weave:run-all
                             :reporter :sexp
                             :stream stream
                             :coverage t
                             :coverage-output "coverage.dat")
                            :to-be-truthy))
                  :to-contain ":CL-WEAVE/RESULTS")))
      (expect (reverse calls)
              :to-equal '(:require :reset :test (:save "coverage.dat")))))

  (it "generates a populated HTML coverage report when requested"
    (let ((root (cl-weave::make-suite :name "root"))
          (calls nil))
      (cl-weave::add-child
       root
       (cl-weave::make-test-case
        :name "covered"
        :function (lambda ()
                    (push :test calls))))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda ()
              (push :require calls)
              t))
           ((symbol-function 'cl-weave:reset-coverage)
            (lambda ()
              (push :reset calls)
              t))
           ((symbol-function 'cl-weave::save-coverage-report)
            (lambda (path)
              (push (list :report path) calls)
              path))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls)
              path)))
        (let ((cl-weave::*root-suite* root))
          (with-output-to-string (stream)
            (expect (cl-weave:run-all
                     :reporter :sexp
                     :stream stream
                     :coverage t
                     :coverage-report-directory "coverage-report/"
                     :coverage-output "coverage.dat")
                    :to-be-truthy))))
      (expect (reverse calls)
              :to-equal '(:require :reset :test
                          (:report "coverage-report/")
                          (:save "coverage.dat")))))

  (it "can preserve existing coverage counters"
    (let ((root (cl-weave::make-suite :name "root"))
          (calls nil))
      (cl-weave::add-child
       root
       (cl-weave::make-test-case
        :name "covered"
        :function (lambda ()
                    (push :test calls))))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda ()
              (push :require calls)
              t))
           ((symbol-function 'cl-weave:reset-coverage)
            (lambda ()
              (push :reset calls)
              t))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls)
              path)))
        (let ((cl-weave::*root-suite* root))
          (with-output-to-string (stream)
            (expect (cl-weave:run-all
                     :reporter :sexp
                     :stream stream
                     :coverage t
                     :coverage-reset nil
                     :coverage-output "coverage.dat")
                    :to-be-truthy))))
      (expect (reverse calls)
              :to-equal '(:require :test (:save "coverage.dat")))))

  (it "saves coverage when the covered run errors"
    (let ((calls nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda ()
              (push :require calls)
              t))
           ((symbol-function 'cl-weave:reset-coverage)
            (lambda ()
              (push :reset calls)
              t))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls)
              path)))
        (expect (lambda ()
                  (cl-weave::call-with-coverage
                   t
                   "coverage.dat"
                   nil
                   t
                   (lambda ()
                     (push :body calls)
                     (error "boom"))))
                :to-throw "boom"))
      (expect (reverse calls)
              :to-equal '(:require :reset :body (:save "coverage.dat")))))

  (it "attempts the sidecar after an HTML report failure"
    (let ((calls nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda () t))
           ((symbol-function 'cl-weave::save-coverage-report)
            (lambda (path)
              (push (list :report path) calls)
              (error "report failed")))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls)
              path)))
        (expect (lambda ()
                  (cl-weave::call-with-coverage
                   t "coverage.dat" "coverage-report/" nil
                   (lambda () :result)))
                :to-throw "Coverage cleanup failed"))
      (expect (reverse calls)
              :to-equal '((:report "coverage-report/")
                          (:save "coverage.dat")))))

  (it "allows callers to explicitly ignore cleanup failures"
    (with-mocked-functions
        (((symbol-function 'cl-weave::require-coverage-support)
          (lambda () t))
         ((symbol-function 'cl-weave:save-coverage)
          (lambda (path)
            (declare (ignore path))
            (error "sidecar failed"))))
      (handler-bind
          ((cl-weave::coverage-cleanup-failure
             (lambda (condition)
               (declare (ignore condition))
               (invoke-restart 'cl-weave::ignore-coverage-cleanup-failure))))
        (expect (cl-weave::call-with-coverage
                 t "coverage.dat" nil nil
                 (lambda () :result))
                :to-equal :result))))

  (it "preserves the primary error while reporting cleanup failures"
    (let ((observed-cleanup nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda () t))
           ((symbol-function 'cl-weave::save-coverage-report)
            (lambda (path)
              (declare (ignore path))
              (error "report failed")))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (declare (ignore path))
              (error "sidecar failed"))))
        (handler-bind
            ((cl-weave::coverage-cleanup-failure
               (lambda (condition)
                 (setf observed-cleanup condition))))
          (expect (lambda ()
                    (cl-weave::call-with-coverage
                     t "coverage.dat" "coverage-report/" nil
                     (lambda ()
                       (error "primary failed"))))
                  :to-throw "primary failed")))
      (expect observed-cleanup :to-be-truthy)
      (expect (mapcar #'car
                      (cl-weave::coverage-cleanup-failures observed-cleanup))
              :to-equal '(:report :data))))

  (it "runs every cleanup without replacing a non-local exit"
    (let ((calls nil)
          (observed-cleanup nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda () t))
           ((symbol-function 'cl-weave::save-coverage-report)
            (lambda (path)
              (push (list :report path) calls)
              (error "report failed")))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls)
              path)))
        (handler-bind
            ((cl-weave::coverage-cleanup-failure
               (lambda (condition)
                 (setf observed-cleanup condition))))
          (expect (catch 'covered-exit
                    (cl-weave::call-with-coverage
                     t "coverage.dat" "coverage-report/" nil
                     (lambda ()
                       (push :body calls)
                       (throw 'covered-exit :escaped))))
                  :to-equal :escaped)))
      (expect (reverse calls)
              :to-equal '(:body
                          (:report "coverage-report/")
                          (:save "coverage.dat")))
      (expect observed-cleanup :to-be-truthy)))

  (it "defines report failures from data"
    (loop for (name finder expected-type message)
            in `((:report-unavailable
                  ,(lambda (name)
                     (declare (ignore name))
                     nil)
                  cl-weave:coverage-unavailable
                  "SB-COVER:REPORT is not available")
                 (:index-missing
                  ,(lambda (name)
                     (declare (ignore name))
                     (lambda (directory)
                       (declare (ignore directory))))
                  error
                  "did not produce")
                 (:report-error
                  ,(lambda (name)
                     (declare (ignore name))
                     (lambda (directory)
                       (declare (ignore directory))
                       (error "report generation failed")))
                  error
                  "report generation failed"))
          for condition = (exercise-coverage-report-failure finder)
          do (expect condition :to-satisfy
                     (lambda (value)
                       (typep value expected-type)))
             (expect (princ-to-string condition) :to-contain message)))

  (it "rejects empty HTML coverage reports"
    (let ((directory (make-test-temporary-directory "coverage-report")))
      (let ((cl-weave::*coverage-report-finder*
              (lambda (name)
                (expect name :to-equal "REPORT")
                (lambda (pathname)
                  (ensure-directories-exist (merge-pathnames #P"cover-index.html"
                                                             pathname))
                  (with-open-file (stream (merge-pathnames #P"cover-index.html"
                                                           pathname)
                                          :direction :output
                                          :if-exists :supersede
                                          :if-does-not-exist :create)
                    (write-line "<h3>No code coverage data found.</h3>" stream))
                  pathname))))
        (expect (lambda ()
                  (cl-weave::save-coverage-report directory))
                :to-throw "Coverage report at"))))

  (it "resets coverage data through the SB-COVER reset hook without touching real coverage state"
    (let ((calls 0)
          (probe (gensym "RESET-COVERAGE-STUB")))
      (setf (symbol-function probe) (lambda () (incf calls)))
      (unwind-protect
           (with-mocked-functions
               (((symbol-function 'cl-weave::require-coverage-support) (lambda () t))
                ((symbol-function 'cl-weave::coverage-fbound-symbol)
                 (lambda (name &optional required-p)
                   (declare (ignore required-p))
                   (expect name :to-equal "RESET-COVERAGE")
                   probe)))
             (expect (cl-weave:reset-coverage) :to-be-truthy)
             (expect calls :to-be 1))
        (fmakunbound probe))))

  (it "saves and reports coverage data through the real SB-COVER hooks when available"
    (when (cl-weave:coverage-support-available-p)
      (let ((output (test-temporary-pathname "coverage-save-real.out"))
            (stats (cl-weave:coverage-statistics)))
        (unwind-protect
             (progn
               (expect (cl-weave:save-coverage output) :to-equal output)
               (expect (probe-file output) :to-be-truthy))
          (ignore-errors (delete-file output)))
        (expect (getf stats :expression-total) :to-satisfy (lambda (value) (>= value 0)))
        (expect (getf stats :expression-covered) :to-satisfy (lambda (value) (>= value 0)))
        (expect (getf stats :branch-total) :to-satisfy (lambda (value) (>= value 0)))
        (expect (getf stats :branch-covered) :to-satisfy (lambda (value) (>= value 0)))))))

(describe "coverage internal SB-COVER interop gaps"
  (it "resolves or rejects SB-COVER symbols by name without a global mock"
    (expect (cl-weave::coverage-fbound-symbol "RESET-COVERAGE" t) :to-be-truthy)
    (expect (cl-weave::coverage-fbound-symbol "NO-SUCH-CL-WEAVE-PROBE-FUNCTION" nil)
            :to-be nil)
    (expect (lambda ()
              (cl-weave::coverage-fbound-symbol "NO-SUCH-CL-WEAVE-PROBE-FUNCTION" t))
            :to-throw
            "SB-COVER:NO-SUCH-CL-WEAVE-PROBE-FUNCTION is not available"))

  (it "resolves or rejects SB-COVER internal symbols by name without a global mock"
    (expect (cl-weave::coverage-internal-symbol "REFRESH-COVERAGE-BITS" t) :to-be-truthy)
    (expect (cl-weave::coverage-internal-symbol "NO-SUCH-CL-WEAVE-PROBE-INTERNAL" nil)
            :to-be nil)
    (expect (lambda ()
              (cl-weave::coverage-internal-symbol "NO-SUCH-CL-WEAVE-PROBE-INTERNAL" t))
            :to-throw
            "SB-COVER internal NO-SUCH-CL-WEAVE-PROBE-INTERNAL is not available"))

  (it "wraps and re-signals require-coverage-support failures as coverage-unavailable"
    (with-mocked-functions
        (((symbol-function 'cl-weave::coverage-fbound-symbol)
          (lambda (name &optional required-p)
            (declare (ignore name required-p))
            (error "boom from stub"))))
      (expect (lambda () (cl-weave::require-coverage-support))
              :to-throw
              "boom from stub"))
    (with-mocked-functions
        (((symbol-function 'cl-weave::coverage-fbound-symbol)
          (lambda (name &optional required-p)
            (declare (ignore name required-p))
            (error 'cl-weave:coverage-unavailable :reason "already-typed"))))
      (expect (lambda () (cl-weave::require-coverage-support))
              :to-throw
              "already-typed")))

  (it "treats any condition during availability probing as unsupported"
    (with-mocked-functions
        (((symbol-function 'cl-weave::require-coverage-support)
          (lambda () (error "simulated probe failure"))))
      (expect (cl-weave:coverage-support-available-p) :to-be nil)))

  (it "rejects coverage data in an unsupported SB-COVER representation"
    (let ((original (symbol-function (quote cl-weave::coverage-internal-symbol)))
          (fake-info-symbol (make-symbol "FAKE-CODE-COVERAGE-INFO")))
      (setf (symbol-value fake-info-symbol) (list 42))
      (with-mocked-functions
          (((symbol-function (quote cl-weave::coverage-internal-symbol))
            (lambda (name &optional required-p)
              (if (string= name "*CODE-COVERAGE-INFO*")
                  fake-info-symbol
                  (funcall original name required-p)))))
        (expect (lambda () (cl-weave:coverage-statistics))
                :to-throw
                "unsupported representation")))))
