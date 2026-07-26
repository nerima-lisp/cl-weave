(in-package #:cl-weave/test)

(describe "cli options"
  (it "accepts an inline option value that begins with dashes"
    ;; Regression: `--flag=VALUE` must take VALUE verbatim even when it looks
    ;; like an option token; that inline form exists precisely to pass values
    ;; that begin with dashes.
    (let ((options (parse-cli '("run" "--filter=--foo"))))
      (expect (cl-weave/cli::cli-options-name-filter options) :to-equal "--foo"))
    ;; The separated `--flag VALUE` form still rejects a following option token.
    (expect (lambda () (parse-cli '("run" "--filter" "--foo")))
            :to-throw "requires an argument"))

  (it "parses canonical run options into explicit data"
    (let ((options (parse-cli '("run"
                      "cl-weave/test"
                      "--reporter=json"
                      "--filter"
                      "parser"
                      "--output"
                      "results.json"
                      "--bail=2"
                      "--retry"
                      "3"
                      "--test-timeout-ms"
                      "2500"
                      "--max-workers"
                      "4"
                      "--shard"
                      "2/4"
                      "--sequence"
                      "random"
                      "--seed"
                      "123"
                      "--coverage"
                      "--coverage-output"
                      "coverage.out"
                      "--coverage-report-directory"
                      "coverage-report/"
                      "--coverage-include" "src/"
                      "--coverage-exclude" "src/generated/"
                      "--coverage-system" "cl-weave"
                      "--coverage-min-expression" "80.5"
                      "--coverage-min-branch" "70"
                      "--fail-with-no-tests"
                      "--once"
                      "--snapshot-dir"
                      "tests/__snapshots__/"
                      "--snapshot-file"
                      "cli.snapshots"
                      "--update-snapshots"))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :run)
      (expect (cl-weave/cli::cli-options-systems options)
              :to-equal '("cl-weave/test"))
      (expect (cl-weave/cli::cli-options-reporter options) :to-be :json)
      (expect (cl-weave/cli::parse-reporter "jsonl") :to-be :jsonl)
      (expect (lambda ()
                (cl-weave/cli::parse-reporter "ndjson"))
              :to-throw
              "cl-weave: unknown reporter")
      (expect (cl-weave/cli::parse-reporter "github") :to-be :github)
      (expect (lambda ()
                (cl-weave/cli::parse-reporter "unknown"))
              :to-throw
              "cl-weave: unknown reporter")
      (expect (cl-weave/cli::parse-sequence-order "random") :to-be :random)
      (dolist (removed-order '("defined" "shuffle"))
        (expect (lambda ()
                  (cl-weave/cli::parse-sequence-order removed-order))
                :to-throw
                "Unknown sequence order"))
      (expect (cl-weave/cli::cli-options-name-filter options) :to-equal "parser")
      (expect (cl-weave/cli::cli-options-output-file options)
              :to-equal "results.json")
      (expect (cl-weave/cli::cli-options-bail options) :to-be 2)
      (expect (cl-weave/cli::cli-options-retry options) :to-be 3)
      (expect (cl-weave/cli::cli-options-test-timeout-ms options) :to-be 2500)
      (expect (cl-weave/cli::cli-options-max-workers options) :to-be 4)
      (expect (cl-weave/cli::cli-options-shard options) :to-equal '(2 4))
      (expect (cl-weave/cli::cli-options-order options) :to-be :random)
      (expect (cl-weave/cli::cli-options-seed options) :to-be 123)
      (expect (cl-weave/cli::cli-options-coverage options) :to-be t)
      (expect (cl-weave/cli::cli-options-coverage-output options)
              :to-equal "coverage.out")
      (expect (cl-weave/cli::cli-options-coverage-report-directory options)
              :to-equal "coverage-report/")
      (expect (cl-weave/cli::cli-options-coverage-include-pathnames options)
              :to-equal '("src/"))
      (expect (cl-weave/cli::cli-options-coverage-exclude-pathnames options)
              :to-equal '("src/generated/"))
      (expect (cl-weave/cli::cli-options-coverage-systems options)
              :to-equal '("cl-weave"))
      (expect (cl-weave/cli::cli-options-coverage-minimum-expression options)
              :to-be 80.5)
      (expect (cl-weave/cli::cli-options-coverage-minimum-branch options)
              :to-be 70)
      (expect (cl-weave/cli::cli-options-pass-with-no-tests options) :to-be nil)
      (expect (cl-weave/cli::cli-options-watch-once options) :to-be t)
      (expect (cl-weave/cli::cli-options-snapshot-directory options)
              :to-equal #P"tests/__snapshots__/")
      (expect (cl-weave/cli::cli-options-snapshot-file options)
              :to-equal "cli.snapshots")
      (expect (cl-weave/cli::cli-options-update-snapshots options) :to-be t)))

  (it "rejects removed CLI aliases"
    (dolist (argv '(("run" "--testNamePattern" "cli")
                    ("run" "--outputFile=vitest-results.json")
                    ("run" "--testTimeout=1500")
                    ("run" "--testTimeoutMs" "1750")
                    ("run" "--maxWorkers=5")
                    ("run" "--coverageOutput=coverage.out")
                    ("run" "--passWithNoTests")
                    ("run" "--failWithNoTests")
                    ("run" "--snapshotDir" "tests/__snapshots__/")
                    ("run" "--snapshotFile=vitest.snapshots")
                    ("run" "--update")
                    ("run" "--updateSnapshots")
                    ("watch" "cl-weave/test" "--watchInterval" "2.5")))
      (expect (lambda ()
                (parse-cli argv))
              :to-throw
              "Unknown option")))

  (it "validates coverage thresholds as percentages"
    (dolist (value '("0" "00" "0.0" "00.00"))
      (expect (cl-weave/cli::cli-options-coverage-minimum-expression
               (parse-cli (list "run" "--coverage-min-expression" value)))
              :to-satisfy
              #'zerop))
    (dolist (value '("100" "100.0"))
      (expect (cl-weave/cli::cli-options-coverage-minimum-expression
               (parse-cli (list "run" "--coverage-min-expression" value)))
              :to-satisfy
              (lambda (number)
                (= number 100))))
    (dolist (value '("100.1" "-1" ".5" "1." "." ".0" "0." "1e2"))
      (expect (lambda ()
                (parse-cli (list "run" "--coverage-min-branch" value)))
              :to-throw)))

  (it "bounds numeric CLI tokens before parsing or splitting"
    (let* ((integer-boundary (make-string 128 :initial-element #\1))
           (signed-boundary
             (concatenate 'string
                          "-"
                          (make-string 127 :initial-element #\1)))
           (decimal-boundary
             (concatenate 'string
                          "1."
                          (make-string 126 :initial-element #\0)))
           (percentage-boundary
             (concatenate 'string
                          (make-string 125 :initial-element #\0)
                          "100"))
           (shard-boundary
             (concatenate 'string
                          (make-string 62 :initial-element #\0)
                          "1/"
                          (make-string 63 :initial-element #\0)
                          "1"))
           (digits-over-limit (make-string 129 :initial-element #\1))
           (signed-over-limit
             (concatenate 'string
                          "-"
                          (make-string 128 :initial-element #\1)))
           (decimal-over-limit
             (concatenate 'string
                          "1."
                          (make-string 127 :initial-element #\0)))
           (exponent-over-limit
             (concatenate 'string
                          "1e"
                          (make-string 127 :initial-element #\0)))
           (shard-over-limit
             (concatenate 'string
                          "1/"
                          (make-string 127 :initial-element #\1))))
      (expect (cl-weave/cli::parse-complete-integer
               integer-boundary
               "--integer")
              :to-satisfy
              #'integerp)
      (expect (cl-weave/cli::parse-complete-integer
               signed-boundary
               "--integer")
              :to-satisfy
              #'minusp)
      (expect (cl-weave/cli::parse-positive-number
               decimal-boundary
               "--number")
              :to-be 1.0)
      (expect (cl-weave/cli::parse-percentage
               percentage-boundary
               "--percentage")
              :to-be 100)
      (expect (lambda ()
          (cl-weave/cli::parse-bail integer-boundary))
        :to-throw)
      (expect (cl-weave/cli::parse-shard shard-boundary) :to-equal (quote (1 1)))
      (dolist (value '("-1" "1.5" "1e3"))
        (expect (lambda ()
                  (cl-weave/cli::parse-bail value))
                :to-throw))
      (dolist (value '("0/1" "2/1" "1/0" "-1/2" "1.0/2" "1e1/2"))
        (expect (lambda ()
                  (cl-weave/cli::parse-shard value))
                :to-throw))
      (labels ((failure-message (thunk)
                 (handler-case
                     (funcall thunk)
                   (cl-weave/cli::cli-error (condition)
                     (princ-to-string condition))))
               (expect-length-error (thunk)
                 (let ((message (failure-message thunk)))
                   (expect message
                           :to-contain
                           "must not exceed 128 characters")
                   (expect (< (length message) 128) :to-be t))))
        (dolist (thunk
                 (list
                  (lambda ()
                    (cl-weave/cli::parse-complete-integer
                     digits-over-limit
                     "--integer"))
                  (lambda ()
                    (cl-weave/cli::parse-complete-integer
                     signed-over-limit
                     "--integer"))
                  (lambda ()
                    (cl-weave/cli::parse-positive-number
                     decimal-over-limit
                     "--number"))
                  (lambda ()
                    (cl-weave/cli::parse-positive-number
                     exponent-over-limit
                     "--number"))
                  (lambda ()
                    (cl-weave/cli::parse-percentage
                     decimal-over-limit
                     "--percentage"))
                  (lambda ()
                    (cl-weave/cli::parse-percentage
                     exponent-over-limit
                     "--percentage"))
                  (lambda ()
                    (cl-weave/cli::parse-bail digits-over-limit))
                  (lambda ()
                    (cl-weave/cli::parse-bail signed-over-limit))
                  (lambda ()
                    (cl-weave/cli::parse-bail decimal-over-limit))
                  (lambda ()
                    (cl-weave/cli::parse-bail exponent-over-limit))
                  (lambda ()
                    (cl-weave/cli::parse-shard shard-over-limit))))
          (expect-length-error thunk)))))

  (it "parses watch intervals as explicit CLI text"
    (labels ((watch-interval-from-env (value)
               (with-mocked-functions
                   (((symbol-function 'uiop:getenv)
                     (lambda (name)
                       (when (string= name "CL_WEAVE_WATCH_INTERVAL")
                         value))))
                 (cl-weave/cli::cli-options-watch-interval
                  (cl-weave/cli::options-from-environment)))))
      (expect (cl-weave/cli::cli-options-watch-interval
               (parse-cli '("watch" "--watch-interval" "0.25")))
              :to-be 0.25)
      (expect (watch-interval-from-env "0.25") :to-be 0.25)
      (dolist (value '("0" "-1" "1/2" "1 " ".5" "1." "#.(error \"reader\")"))
        (expect (lambda ()
                  (parse-cli (list "watch" "--watch-interval" value)))
                :to-throw
                "--watch-interval must be a positive number")
        (expect (lambda ()
                  (watch-interval-from-env value))
                :to-throw
                "CL_WEAVE_WATCH_INTERVAL must be a positive number"))))

  (it "parses watch once policy from flags and environment"
    (let ((options (parse-cli '("watch" "--once"))))
      (expect (cl-weave/cli::cli-options-watch-once options) :to-be t))
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (cdr (assoc name
                        '(("CL_WEAVE_WATCH_ONCE" . "1"))
                        :test #'string=)))))
      (let ((options (cl-weave/cli::options-from-environment)))
        (expect (cl-weave/cli::cli-options-watch-once options) :to-be t))))

  (it "parses doctor as a machine-readable command with an optional positional system"
    (let ((options (parse-cli '("doctor" "--reporter" "json"))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :doctor)
      (expect (cl-weave/cli::cli-options-reporter options) :to-be :json)
      (expect (cl-weave/cli::cli-options-systems options) :to-equal '()))
    (let ((options (parse-cli '("doctor" "cl-weave/test"))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :doctor)
      (expect (cl-weave/cli::cli-options-systems options)
              :to-equal '("cl-weave/test"))))

  (it "parses CI snapshot settings from environment variables"
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (cdr (assoc name
                        '(("CL_WEAVE_SNAPSHOT_DIR" . "ci/__snapshots__/")
                          ("CL_WEAVE_SNAPSHOT_FILE" . "ci.snapshots")
                          ("CL_WEAVE_UPDATE_SNAPSHOTS" . "1"))
                        :test #'string=)))))
      (let ((options (cl-weave/cli::options-from-environment)))
        (expect (cl-weave/cli::cli-options-snapshot-directory options)
                :to-equal #P"ci/__snapshots__/")
        (expect (cl-weave/cli::cli-options-snapshot-file options)
                :to-equal "ci.snapshots")
        (expect (cl-weave/cli::cli-options-update-snapshots options) :to-be t))))

  (it "parses no-test policy from flags and environment"
    (let ((options (parse-cli '("run" "--fail-with-no-tests" "--pass-with-no-tests"))))
      (expect (cl-weave/cli::cli-options-pass-with-no-tests options) :to-be t))
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (cdr (assoc name
                        '(("CL_WEAVE_PASS_WITH_NO_TESTS" . "false"))
                        :test #'string=)))))
      (let ((options (cl-weave/cli::options-from-environment)))
        (expect (cl-weave/cli::cli-options-pass-with-no-tests options)
                :to-be nil))))

  (it "rejects inline values for flag-only options"
    (dolist (token '("--help=1"
                 "--version=1"
                 "--coverage=false"
                 "--pass-with-no-tests=false"
                 "--fail-with-no-tests=true"
                 "--update-snapshots=false"))
      (expect (lambda ()
                (parse-cli (list "run" token)))
              :to-throw
              "does not accept an inline value")))
  (it "does not consume a positional system as a bare bail value"
    (let ((bare (parse-cli (list "run" "--bail" "cl-weave/test")))
          (numeric (parse-cli (list "run" "--bail" "2" "cl-weave/test")))
          (disabled (parse-cli (list "run" "--bail=false" "cl-weave/test"))))
      (expect (cl-weave/cli::cli-options-bail bare) :to-be t)
      (expect (cl-weave/cli::cli-options-systems bare)
              :to-equal (list "cl-weave/test"))
      (expect (cl-weave/cli::cli-options-bail numeric) :to-be 2)
      (expect (cl-weave/cli::cli-options-systems numeric)
              :to-equal (list "cl-weave/test"))
      (expect (cl-weave/cli::cli-options-bail disabled) :to-be nil)
      (expect (cl-weave/cli::cli-options-systems disabled)
              :to-equal (list "cl-weave/test")))
    (expect (lambda ()
              (parse-cli (list "run" "--bail=invalid" "cl-weave/test")))
            :to-throw
            "--bail must be true, false, or a positive integer"))

  (it "enforces semantic runner bounds for CLI options"
    (let ((options
            (parse-cli
             (list "run"
                   "--retry"
                   (princ-to-string cl-weave::+maximum-retry-count+)
                   "--test-timeout-ms"
                   (princ-to-string cl-weave::+maximum-timeout-ms+)
                   "--max-workers"
                   (princ-to-string cl-weave::+maximum-worker-count+)
                   "--bail"
                   (princ-to-string cl-weave::+maximum-bail-limit+)
                   "--shard"
                   (format nil "~D/~D"
                           cl-weave::+maximum-shard-count+
                           cl-weave::+maximum-shard-count+)))))
      (expect (cl-weave/cli::cli-options-retry options)
              :to-be cl-weave::+maximum-retry-count+)
      (expect (cl-weave/cli::cli-options-test-timeout-ms options)
              :to-be cl-weave::+maximum-timeout-ms+)
      (expect (cl-weave/cli::cli-options-max-workers options)
              :to-be cl-weave::+maximum-worker-count+)
      (expect (cl-weave/cli::cli-options-bail options)
              :to-be cl-weave::+maximum-bail-limit+)
      (expect (cl-weave/cli::cli-options-shard options)
              :to-equal
              (list cl-weave::+maximum-shard-count+
                    cl-weave::+maximum-shard-count+)))
    (dolist (option-value
             (list
              (list "--retry"
                    (princ-to-string
                     (1+ cl-weave::+maximum-retry-count+)))
              (list "--test-timeout-ms"
                    (princ-to-string
                     (1+ cl-weave::+maximum-timeout-ms+)))
              (list "--max-workers"
                    (princ-to-string
                     (1+ cl-weave::+maximum-worker-count+)))
              (list (format nil "--bail=~D"
                            (1+ cl-weave::+maximum-bail-limit+))
                    "cl-weave/test")
              (list "--shard"
                    (format nil "1/~D"
                            (1+ cl-weave::+maximum-shard-count+)))))
      (expect (lambda ()
                (parse-cli
                 (list "run" (first option-value) (second option-value))))
              :to-throw)))

  (it "treats Lisp nil environment tokens as false"
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (cdr (assoc name
                        '(("CL_WEAVE_COVERAGE" . "nil")
                          ("CL_WEAVE_LIST" . "nil")
                          ("CL_WEAVE_WATCH" . "nil")
                          ("CL_WEAVE_UPDATE_SNAPSHOTS" . "nil")
                          ("CL_WEAVE_PASS_WITH_NO_TESTS" . "nil"))
                        :test #'string=)))))
      (let ((options (cl-weave/cli::options-from-environment)))
        (expect (cl-weave/cli::cli-options-coverage options) :to-be nil)
        (expect (cl-weave/cli::cli-options-list options) :to-be nil)
        (expect (cl-weave/cli::cli-options-watch options) :to-be nil)
        (expect (cl-weave/cli::cli-options-update-snapshots options) :to-be nil)
        (expect (cl-weave/cli::cli-options-pass-with-no-tests options)
                :to-be nil))))

  (it "parses and bounds bail control from CI environment data"
  (labels ((bail-from (value)
             (with-mocked-functions
                 (((symbol-function 'uiop:getenv)
                   (lambda (name)
                     (when (string= name "CL_WEAVE_BAIL")
                       value))))
               (cl-weave/cli::cli-options-bail
                (cl-weave/cli::options-from-environment)))))
    (dolist (value '("0" "false" "no" "off" "nil"))
      (expect (bail-from value) :to-be nil))
    (dolist (value '("true" "yes" "on" "t"))
      (expect (bail-from value) :to-be t))
    (expect (bail-from "3") :to-be 3)
    (expect (bail-from
             (princ-to-string cl-weave::+maximum-bail-limit+))
            :to-be cl-weave::+maximum-bail-limit+)
    (expect (lambda ()
              (bail-from
               (princ-to-string
                (1+ cl-weave::+maximum-bail-limit+))))
            :to-throw)
    (dolist (value '("maybe" "-1" "1.5"))
      (expect (lambda ()
                (bail-from value))
              :to-throw
              "--bail must be true, false, or a positive integer"))))

  (it "parses and bounds retry, timeout, workers, and shard environment data"
  (labels ((options-from (entries)
             (with-mocked-functions
                 (((symbol-function 'uiop:getenv)
                   (lambda (name)
                     (cdr (assoc name entries :test #'string=)))))
               (cl-weave/cli::options-from-environment))))
    (let ((options (options-from '(("CL_WEAVE_RETRY" . "0")
                                   ("CL_WEAVE_TEST_TIMEOUT" . "2500")))))
      (expect (cl-weave/cli::cli-options-retry options) :to-be 0)
      (expect (cl-weave/cli::cli-options-test-timeout-ms options)
              :to-be 2500))
    (let ((options (options-from '(("CL_WEAVE_RETRY" . "3")
                                   ("CL_WEAVE_TEST_TIMEOUT" . "2500")
                                   ("CL_WEAVE_TEST_TIMEOUT_MS" . "125")
                                   ("CL_WEAVE_MAX_WORKERS" . "4")))))
      (expect (cl-weave/cli::cli-options-retry options) :to-be 3)
      (expect (cl-weave/cli::cli-options-test-timeout-ms options)
              :to-be 2500)
      (expect (cl-weave/cli::cli-options-max-workers options)
              :to-be 4))
    (let ((options
            (options-from
             (list
              (cons "CL_WEAVE_RETRY"
                    (princ-to-string cl-weave::+maximum-retry-count+))
              (cons "CL_WEAVE_TEST_TIMEOUT_MS"
                    (princ-to-string cl-weave::+maximum-timeout-ms+))
              (cons "CL_WEAVE_MAX_WORKERS"
                    (princ-to-string cl-weave::+maximum-worker-count+))
              (cons "CL_WEAVE_SHARD"
                    (format nil "~D/~D"
                            cl-weave::+maximum-shard-count+
                            cl-weave::+maximum-shard-count+))))))
      (expect (cl-weave/cli::cli-options-retry options)
              :to-be cl-weave::+maximum-retry-count+)
      (expect (cl-weave/cli::cli-options-test-timeout-ms options)
              :to-be cl-weave::+maximum-timeout-ms+)
      (expect (cl-weave/cli::cli-options-max-workers options)
              :to-be cl-weave::+maximum-worker-count+)
      (expect (cl-weave/cli::cli-options-shard options)
              :to-equal
              (list cl-weave::+maximum-shard-count+
                    cl-weave::+maximum-shard-count+)))
    (dolist (entry
             (list
              (cons "CL_WEAVE_RETRY"
                    (princ-to-string
                     (1+ cl-weave::+maximum-retry-count+)))
              (cons "CL_WEAVE_TEST_TIMEOUT_MS"
                    (princ-to-string
                     (1+ cl-weave::+maximum-timeout-ms+)))
              (cons "CL_WEAVE_MAX_WORKERS"
                    (princ-to-string
                     (1+ cl-weave::+maximum-worker-count+)))
              (cons "CL_WEAVE_SHARD"
                    (format nil "1/~D"
                            (1+ cl-weave::+maximum-shard-count+)))))
      (expect (lambda ()
                (options-from (list entry)))
              :to-throw))
    (expect (lambda ()
              (options-from '(("CL_WEAVE_RETRY" . "-1"))))
            :to-throw
            "CL_WEAVE_RETRY must be a non-negative integer")
    (expect (lambda ()
              (options-from '(("CL_WEAVE_TEST_TIMEOUT_MS" . "0"))))
            :to-throw
            "CL_WEAVE_TEST_TIMEOUT_MS must be positive")
    (expect (lambda ()
              (options-from '(("CL_WEAVE_MAX_WORKERS" . "0"))))
            :to-throw
            "CL_WEAVE_MAX_WORKERS must be positive")))

  (it "requires explicit CI sequence seeds to be positive integers"
    (labels ((seed-from (value)
               (with-mocked-functions
                   (((symbol-function 'uiop:getenv)
                     (lambda (name)
                       (when (string= name "CL_WEAVE_SEQUENCE_SEED")
                         value))))
                 (cl-weave/cli::cli-options-seed
                  (cl-weave/cli::options-from-environment)))))
      (expect (seed-from "42") :to-be 42)
      (dolist (value '("0" "-1" "1.5" "abc"))
        (expect (lambda ()
                  (seed-from value))
                :to-throw
                "CL_WEAVE_SEQUENCE_SEED"))))

  (it "accepts representative values for every environment-backed CLI option"
    (labels ((options-from (entries)
               (with-mocked-functions
                   (((symbol-function 'uiop:getenv)
                     (lambda (name)
                       (cdr (assoc name entries :test #'string=)))))
                 (cl-weave/cli::options-from-environment))))
      (dolist (sample
               '(("--system" . (("CL_WEAVE_SYSTEM" . "sample-system")))
                 ("--reporter" . (("CL_WEAVE_REPORTER" . "json")))
                 ("--filter" . (("CL_WEAVE_TEST_FILTER" . "focus")))
                 ("--output" . (("CL_WEAVE_OUTPUT_FILE" . "results.json")))
                 ("--list" . (("CL_WEAVE_LIST" . "1")))
                 ("--watch" . (("CL_WEAVE_WATCH" . "1")))
                 ("--once" . (("CL_WEAVE_WATCH_ONCE" . "1")))
                 ("--watch-interval" . (("CL_WEAVE_WATCH_INTERVAL" . "0.5")))
                 ("--bail" . (("CL_WEAVE_BAIL" . "2")))
                 ("--retry" . (("CL_WEAVE_RETRY" . "1")))
                 ("--test-timeout-ms" . (("CL_WEAVE_TEST_TIMEOUT" . "250")
                                         ("CL_WEAVE_TEST_TIMEOUT_MS" . "125")))
                 ("--max-workers" . (("CL_WEAVE_MAX_WORKERS" . "3")))
                 ("--shard" . (("CL_WEAVE_SHARD" . "1/2")))
                 ("--sequence" . (("CL_WEAVE_SEQUENCE" . "random")))
                 ("--seed" . (("CL_WEAVE_SEQUENCE_SEED" . "11")))
                 ("--coverage" . (("CL_WEAVE_COVERAGE" . "1")))
                 ("--coverage-output" . (("CL_WEAVE_COVERAGE_FILE" . "coverage.out")))
                 ("--pass-with-no-tests" . (("CL_WEAVE_PASS_WITH_NO_TESTS" . "true")))
                 ("--snapshot-dir" . (("CL_WEAVE_SNAPSHOT_DIR" . "tmp/__snapshots__/")))
                 ("--snapshot-file" . (("CL_WEAVE_SNAPSHOT_FILE" . "suite.snapshots")))
                 ("--update-snapshots" . (("CL_WEAVE_UPDATE_SNAPSHOTS" . "1")))))
        (expect (options-from (cdr sample)) :not :to-be nil))))

  (it "binds snapshot settings during CLI execution"
    (let ((observed nil)
          (options (cl-weave/cli::make-cli-options
                    :snapshot-directory #P"tmp/__snapshots__/"
                    :snapshot-file "cli.snapshots"
                    :update-snapshots t)))
      (with-mocked-functions
          (((symbol-function 'cl-weave:run-all)
            (lambda (&key reporter name-filter shard order seed bail coverage
                     retry timeout-ms max-workers coverage-output
                     coverage-report-directory
                     coverage-include-pathnames coverage-exclude-pathnames
                     coverage-minimum-expression coverage-minimum-branch
                     pass-with-no-tests stream)
              (declare (ignore reporter name-filter shard order seed bail coverage
                               retry timeout-ms max-workers coverage-output
                               coverage-report-directory
                               coverage-include-pathnames coverage-exclude-pathnames
                               coverage-minimum-expression coverage-minimum-branch
                               pass-with-no-tests stream))
              (setf observed
                    (list cl-weave:*snapshot-directory*
                          cl-weave:*snapshot-file-name*
                          cl-weave:*update-snapshots*))
              t)))
        (expect (cl-weave/cli::run-command options) :to-be t))
      (expect observed
              :to-equal (list #P"tmp/__snapshots__/" "cli.snapshots" t))))

  (it "generates CLI data and field operations from one schema"
    (let* ((expansion
             (macroexpand-1
              '(cl-weave/cli::define-cli-options
                 (:fields value (items '() :type list))
                 (:options
                  (:flag "--value" :kind :value :field :value)
                  (:flag "--item" :kind :collection :field :items))
                 (:environment
                  (:flag "--value" :kind :value :field :value)))))
           (definitions (rest expansion)))
      (expect (first expansion) :to-be 'progn)
      (dolist (name '(defstruct defparameter defun))
        (expect (find name definitions :key #'first) :not :to-be nil))
      (expect (count 'defparameter definitions :key #'first) :to-be 2)
      (expect (count 'defun definitions :key #'first) :to-be 2)))

  (it "rejects invalid CLI schemas during macroexpansion"
    (dolist
        (case
         (list
          (list
           '(cl-weave/cli::define-cli-options
              (:fields value)
              (:options
               (:flag "--value" :kind :value :field :value)
               (:flag "--value" :kind :flag :field :value))
              (:environment))
           "Duplicate command-line CLI flag")
          (list
           '(cl-weave/cli::define-cli-options
              (:fields value)
              (:options)
              (:environment
               (:flag "--value" :kind :value :field :value)
               (:flag "--value" :kind :truthy :field :value)))
           "Duplicate environment CLI flag")
          (list
           '(cl-weave/cli::define-cli-options
              (:fields value)
              (:options (:flag "--missing" :kind :value :field :missing))
              (:environment))
           "Unknown CLI option field")
          (list
           '(cl-weave/cli::define-cli-options
              (:fields value)
              (:options (:flag "--value" :kind :stream :field :value))
              (:environment))
           "Unknown command-line CLI option kind")
          (list
           '(cl-weave/cli::define-cli-options
              (:fields value)
              (:options)
              (:environment (:flag "--value" :kind :stream :field :value)))
           "Unknown environment CLI option kind")))
      (expect (lambda () (macroexpand-1 (first case)))
              :to-throw
              (second case))))

)

(describe "cli time-travel options"
  (it "parses --journal and --random-seed"
    (let ((options (parse-cli '("run" "--journal" "--random-seed" "77"
                                "--system" "cl-weave/test"))))
      (expect (cl-weave/cli::cli-options-journal options) :to-be t)
      (expect (cl-weave/cli::cli-options-random-seed options) :to-be 77)))

  (it "defaults the time-travel options to disabled"
    (let ((options (parse-cli '("run" "--system" "cl-weave/test"))))
      (expect (cl-weave/cli::cli-options-journal options) :to-be nil)
      (expect (cl-weave/cli::cli-options-random-seed options) :to-be nil)))

  (it "accepts a zero random seed"
    (let ((options (parse-cli '("run" "--random-seed" "0"))))
      (expect (cl-weave/cli::cli-options-random-seed options) :to-be 0)))

  (it "rejects a non-integer --random-seed"
    (expect (lambda () (parse-cli '("run" "--random-seed" "abc")))
            :to-throw 'cl-weave/cli::cli-error))

  (it "binds the runtime toggles from parsed options"
    (let ((options (cl-weave/cli::make-cli-options :journal t :random-seed 5)))
      (cl-weave/cli::with-cli-journal-settings (options)
        (expect cl-weave:*journal-enabled* :to-be t)
        (expect cl-weave:*test-random-seed* :to-be 5))))

  (it "documents the flags in CLI usage metadata"
    (let ((usage (cl-weave/cli::cli-usage)))
      (expect usage :to-contain "--journal")
      (expect usage :to-contain "--random-seed INTEGER"))))
