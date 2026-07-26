(in-package #:cl-weave/test)

(describe "cli execution"
  (it "writes JSON result artifacts through the CLI output option"
    (let* ((output-file (test-temporary-pathname "cl-weave-cli-results.json"))
           (options (cl-weave/cli::make-cli-options
                     :reporter :json
                     :output-file (namestring output-file))))
      (when (probe-file output-file)
        (delete-file output-file))
      (unwind-protect
           (progn
             (with-mocked-functions
                 (((symbol-function 'cl-weave:run-all)
                   (lambda (&key reporter name-filter shard order seed bail coverage
                            retry timeout-ms max-workers coverage-output
                            coverage-report-directory
                            coverage-include-pathnames coverage-exclude-pathnames
                            coverage-minimum-expression coverage-minimum-branch
                            pass-with-no-tests stream)
                     (declare (ignore name-filter shard order seed bail coverage
                                      retry timeout-ms max-workers coverage-output
                                      coverage-report-directory
                                      coverage-include-pathnames coverage-exclude-pathnames
                                      coverage-minimum-expression coverage-minimum-branch
                                      pass-with-no-tests))
                     (expect reporter :to-be :json)
                     (cl-weave::report-json nil stream)
                     t)))
               (expect (with-output-to-string (*standard-output*)
                         (cl-weave/cli::run-command options))
                       :to-equal ""))
             (let ((output (read-text-file output-file)))
               (expect output :to-contain "\"schemaVersion\":6")
               (expect output :to-contain "\"kind\":\"test-results\"")
               (expect output :to-contain "\"events\":[]")))
        (when (probe-file output-file)
          (delete-file output-file)))))

  (it "parses list and watch commands without executing tests"
    (let ((list-options (parse-cli '("list" "cl-weave/test" "--reporter" "sexp")))
          (watch-options (parse-cli '("watch" "cl-weave/test" "--watch-interval" "1.5"))))
      (expect (cl-weave/cli::cli-options-command list-options) :to-be :list)
      (expect (cl-weave/cli::cli-options-list list-options) :to-be t)
      (expect (cl-weave/cli::cli-options-reporter list-options) :to-be :sexp)
      (expect (cl-weave/cli::cli-options-command watch-options) :to-be :watch)
      (expect (cl-weave/cli::cli-options-watch watch-options) :to-be t)
      (expect (cl-weave/cli::cli-options-watch-once watch-options) :to-be nil)
      (expect (cl-weave/cli::cli-options-watch-interval watch-options)
              :to-be 1.5)))

  (it "forwards coverage settings through CLI watch mode"
    (let ((options (cl-weave/cli::make-cli-options
                    :command :watch
                    :watch t
                    :systems '("cl-weave")
                    :reporter :json
                    :name-filter "watch"
                    :coverage t
                    :coverage-output "watch.coverage.sexp"
                    :coverage-report-directory "watch-coverage-report/"
                    :coverage-include-pathnames '("src/")
                    :coverage-exclude-pathnames '("src/generated/")
                    :coverage-minimum-expression 80
                    :coverage-minimum-branch 70
                    :pass-with-no-tests t
                    :watch-once t
                    :watch-interval 1.25
                    :max-workers 4)))
      (multiple-value-bind (system arguments)
          (cl-weave/cli::watch-command-call-arguments options)
        (expect system
                :to-satisfy
                (lambda (value)
                  (string= value "cl-weave")))
        (expect arguments
                :to-equal
                '(:reporter :json
                  :name-filter "watch"
                  :shard nil
                  :order nil
                  :seed nil
                  :bail nil
                  :coverage t
                  :coverage-output "watch.coverage.sexp"
                  :coverage-report-directory "watch-coverage-report/"
                  :coverage-include-pathnames ("src/")
                  :coverage-exclude-pathnames ("src/generated/")
                  :coverage-minimum-expression 80
                  :coverage-minimum-branch 70
                  :pass-with-no-tests t
                  :retry 0
                  :timeout-ms nil
                  :max-workers 4
                  :include-dependencies t
                  :once t
                  :interval 1.25))))))
