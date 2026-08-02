(in-package #:cl-weave/test)

(describe "cli entrypoint"
  (it "normalizes SBCL argument separators from nix run"
    (let ((options (parse-cli '("--" "run" "cl-weave/test" "--filter" "cli"))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :run)
      (expect (cl-weave/cli::cli-options-systems options)
              :to-equal '("cl-weave/test"))
      (expect (cl-weave/cli::cli-options-name-filter options) :to-equal "cli")))

  (it "prints canonical version output without running tests"
    (let ((flag-options (parse-cli '("--version")))
          (command-options (parse-cli '("version")))
          (exit-code nil)
          (version (cl-weave/cli::cli-version)))
      (expect (cl-weave/cli::cli-options-version flag-options) :to-be t)
      (expect (cl-weave/cli::cli-options-version command-options) :to-be t)
      (expect version :not :to-equal "unknown")
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code))))
        (let ((output (with-output-to-string (*standard-output*)
                        (cl-weave/cli:main '("--version")))))
          (expect output :to-equal (format nil "cl-weave ~A~%" version))
          (expect exit-code :to-be 0)))))

  (it "prints help output without dispatching test execution"
    (let ((flag-options (parse-cli '("--help")))
          (command-options (parse-cli '("help")))
          (exit-code nil)
          (run-command-called nil))
      (expect (cl-weave/cli::cli-options-help flag-options) :to-be t)
      (expect (cl-weave/cli::cli-options-help command-options) :to-be t)
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code)))
           ((symbol-function 'cl-weave/cli::run-command)
            (lambda (options)
              (declare (ignore options))
              (setf run-command-called t)
              t)))
        (let ((output (with-output-to-string (*standard-output*)
                        (cl-weave/cli:main '("help")))))
          (expect output :to-contain "cl-weave run [SYSTEM] [options]")
          (expect output :to-contain "cl-weave metadata [SYSTEM] [options]")
          (expect exit-code :to-be 0)
          (expect run-command-called :to-be nil)))))

  (it "dispatches list mode through main with structured arguments"
    (let ((exit-code nil)
          (observed nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code)))
           ((symbol-function 'cl-weave/cli::load-requested-inputs)
            (lambda (options)
              (declare (ignore options))
              nil))
           ((symbol-function 'cl-weave:list-tests)
            (lambda (&key reporter name-filter shard order seed retry timeout-ms stream)
              (declare (ignore stream))
              (setf observed
                    (list :reporter reporter
                          :name-filter name-filter
                          :shard shard
                          :order order
                          :seed seed
                          :retry retry
                          :timeout-ms timeout-ms))
              t)))
        (expect (with-output-to-string (*standard-output*)
                  (cl-weave/cli:main
                   '("list" "cl-weave/test"
                     "--reporter" "json"
                     "--filter" "cli"
                     "--shard" "2/4"
                     "--sequence" "random"
                     "--seed" "42"
                     "--retry" "3"
                     "--test-timeout-ms" "2500")))
                :to-equal "")
        (expect exit-code :to-be 0)
        (expect observed
                :to-equal
                '(:reporter :json
                  :name-filter "cli"
                  :shard (2 4)
                  :order :random
                  :seed 42
                  :retry 3
                  :timeout-ms 2500)))))

  (it "dispatches watch mode through main with system-scoped arguments"
    (let ((exit-code nil)
          (observed-system nil)
          (observed-arguments nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code)))
           ((symbol-function 'cl-weave/cli::load-requested-inputs)
            (lambda (options)
              (declare (ignore options))
              nil))
           ((symbol-function 'cl-weave:watch-system)
            (lambda (system &rest arguments)
              (setf observed-system system
                    observed-arguments arguments)
              t)))
        (expect (with-output-to-string (*standard-output*)
                  (cl-weave/cli:main
                   '("watch" "cl-weave/test"
                     "--reporter" "jsonl"
                     "--filter" "watch"
                     "--coverage"
                     "--coverage-output" "watch.coverage"
                     "--coverage-report-directory" "watch-coverage-report/"
                     "--pass-with-no-tests"
                     "--once"
                     "--watch-interval" "1.5"
                     "--max-workers" "4")))
                :to-equal "")
        (expect exit-code :to-be 0)
        (expect observed-system :to-equal "cl-weave/test")
        (expect (getf observed-arguments :reporter) :to-be :jsonl)
        (expect (getf observed-arguments :name-filter) :to-equal "watch")
        (expect (getf observed-arguments :shard) :to-be nil)
        (expect (getf observed-arguments :order) :to-be nil)
        (expect (getf observed-arguments :seed) :to-be nil)
        (expect (getf observed-arguments :bail) :to-be nil)
        (expect (getf observed-arguments :coverage) :to-be t)
        (expect (getf observed-arguments :coverage-output)
                :to-equal "watch.coverage")
        (expect (getf observed-arguments :coverage-report-directory)
                :to-equal "watch-coverage-report/")
        (expect (getf observed-arguments :pass-with-no-tests) :to-be t)
        (expect (getf observed-arguments :retry) :to-be 0)
        (expect (getf observed-arguments :timeout-ms) :to-be nil)
        (expect (getf observed-arguments :max-workers) :to-be 4)
        (expect (getf observed-arguments :include-dependencies) :to-be t)
        (expect (getf observed-arguments :once) :to-be t)
        (expect (getf observed-arguments :interval) :to-equal 1.5)
        (expect (getf observed-arguments :stream) :to-be-truthy)
        (expect (getf observed-arguments :status-stream) :to-be-truthy))))

  (it "writes watch artifacts to --output while keeping watch status on stderr"
    (let* ((output-file (test-temporary-pathname "cl-weave-watch-once.json"))
           (stdout "")
           (stderr "")
           (exit-code nil))
      (when (probe-file output-file)
        (delete-file output-file))
      (unwind-protect
           (progn
             (with-mocked-functions
                 (((symbol-function 'cl-weave/cli::exit-process)
                   (lambda (code)
                     (setf exit-code code)))
                  ((symbol-function 'cl-weave/cli::load-requested-inputs)
                   (lambda (options)
                     (declare (ignore options))
                     nil))
                  ((symbol-function 'cl-weave:watch-system)
                   (lambda (system &key reporter stream status-stream name-filter
                                         shard order seed bail coverage
                                         coverage-output coverage-report-directory
                                         coverage-include-pathnames
                                         coverage-exclude-pathnames
                                         coverage-minimum-expression
                                         coverage-minimum-branch
                                         pass-with-no-tests retry
                                         timeout-ms max-workers include-dependencies
                                         once interval)
                     (declare (ignore system shard order seed bail coverage
                                      coverage-output coverage-report-directory
                                      coverage-include-pathnames
                                      coverage-exclude-pathnames
                                      coverage-minimum-expression
                                      coverage-minimum-branch
                                      pass-with-no-tests retry
                                      timeout-ms max-workers include-dependencies
                                      interval))
                     (expect reporter :to-be :json)
                     (expect name-filter :to-equal "watch")
                     (expect once :to-be t)
                     (write-string "; cl-weave watch: FULL-SUITE" status-stream)
                     (cl-weave::report-json nil stream)
                     t)))
               (setf stdout
                     (with-output-to-string (*standard-output*)
                       (setf stderr
                             (with-output-to-string (*error-output*)
                               (cl-weave/cli:main
                                (list "watch"
                                      "cl-weave/test"
                                      "--once"
                                      "--reporter" "json"
                                      "--filter" "watch"
                                      "--output" (namestring output-file))))))))
             (expect exit-code :to-be 0)
             (expect stdout :to-equal "")
             (expect stderr :to-contain "cl-weave watch: FULL-SUITE")
             (expect stderr :not :to-contain "\"schemaVersion\":6")
             (let ((output (read-text-file output-file)))
               (expect output :to-contain "\"schemaVersion\":6")
               (expect output :to-contain "\"kind\":\"test-results\"")
               (expect output :not :to-contain "cl-weave watch"))))
        (when (probe-file output-file)
          (delete-file output-file)))))

(it
  "returns CLI error status for watch mode without a target system"
  (let ((exit-code nil)
        (stderr ""))
    (with-mocked-functions
      (((symbol-function 'cl-weave/cli::exit-process)
          (lambda (code)
            (setf exit-code code))))
      (setf stderr (with-output-to-string (*error-output*)
          (cl-weave/cli:main '("watch")))))
    (expect exit-code :to-be 2)
    (expect
      stderr
      :to-contain
      "Watch mode requires SYSTEM as a positional argument or --system SYSTEM.")
    (expect stderr :to-contain "cl-weave watch [SYSTEM] [options]")))

(it
  "returns CLI error status for watch mode with multiple target systems"
  (let ((exit-code nil)
        (stderr "")
        (watch-called-p nil))
    (with-mocked-functions
      (((symbol-function 'cl-weave/cli::exit-process)
          (lambda (code)
            (setf exit-code code)))
        ((symbol-function 'cl-weave/cli::load-requested-inputs)
          (lambda (options)
            (declare (ignore options))
            nil))
        ((symbol-function 'cl-weave:watch-system)
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (setf watch-called-p t)
            t)))
      (setf stderr (with-output-to-string (*error-output*)
          (cl-weave/cli:main
            '("watch" "--system" "cl-weave/test" "--system" "sample-system")))))
    (expect exit-code :to-be 2)
    (expect watch-called-p :to-be nil)
    (expect stderr :to-contain "Watch mode accepts exactly one SYSTEM target.")
    (expect stderr :to-contain "cl-weave watch [SYSTEM] [options]")))

(it
  "rejects CI-incompatible list reporters early"
  (dolist (reporter '("github" "junit"))
    (let ((options (parse-cli (list "list" "cl-weave/test" "--reporter" reporter))))
      (expect
        (lambda ()
          (cl-weave/cli::ensure-valid-reporter-for-command options))
        :to-throw))))

(it
  "rejects unsupported run and watch reporters at the CLI boundary"
  (dolist (command '(:run :watch))
    (let ((options
          (cl-weave/cli::make-cli-options
            :command
            command
            :reporter
            :unknown
            :systems
            '("cl-weave/test")
            :watch
            (eq command :watch))))
      (expect
        (lambda ()
          (cl-weave/cli::ensure-valid-reporter-for-command options))
        :to-throw
        "cl-weave: run mode supports spec, sexp, json, jsonl, tap, github, and junit reporters."))))

(it
  "loads explicit ASD files, requested systems, then explicit Lisp files"
  (let* ((cwd #P"/tmp/cl-weave-bootstrap/")
         (target-asd #P"/tmp/cl-weave-bootstrap/example.asd")
         (explicit-asd #P"/tmp/cl-weave-explicit/custom.asd")
         (source-file #P"/tmp/cl-weave-explicit/setup.lisp")
         (explicit-target-asd #P"/tmp/cl-weave-explicit/example.asd")
         (options
           (cl-weave/cli::make-cli-options
             :systems
             (quote ("example/tests"))
             :load-files
             (list source-file explicit-asd source-file explicit-asd)))
         (bootstrapped nil)
         (probed-pathnames (quote ()))
         (events (quote ())))
    (with-relaxed-package-locks
      (with-mocked-functions
        (((symbol-function (quote uiop:getcwd))
            (lambda ()
              cwd))
          ((symbol-function (quote uiop:file-exists-p))
            (lambda (pathname)
              (push pathname probed-pathnames)
              (and (equal pathname target-asd) pathname)))
          ((symbol-function (quote cl-weave/cli::directory-asd-files))
            (lambda (directory)
              (declare (ignore directory))
              (error "ASD directory enumeration is forbidden")))
          ((symbol-function (quote asdf:load-asd))
            (lambda (pathname)
              (push (list :asd pathname) events)
              (when (equal pathname target-asd)
                (setf bootstrapped t))))
          ((symbol-function (quote cl:load))
            (lambda (pathname &rest arguments)
              (declare (ignore arguments))
              (push (list :source pathname) events)))
          ((symbol-function (quote asdf:find-system))
            (lambda (system &optional errorp)
              (declare (ignore errorp))
              (and bootstrapped (string= system "example/tests") :example/tests)))
          ((symbol-function (quote asdf:load-system))
            (lambda (system)
              (push (list :system system) events)
              :loaded)))
        (expect (cl-weave/cli::load-requested-inputs options) :to-be nil)
        (expect probed-pathnames :to-equal (list explicit-target-asd target-asd))
        (expect
          (reverse events)
          :to-equal
          (list
            (list :asd explicit-asd)
            (list :asd explicit-asd)
            (list :asd target-asd)
            (list :system "example/tests")
            (list :source source-file)
            (list :source source-file)))))))

(it
  "loads requested systems before explicit Lisp readers need their packages"
  (let* ((directory (make-test-temporary-directory "cli-load-order"))
         (system-name
           (string-downcase (symbol-name (gensym "CL-WEAVE-LOAD-ORDER-"))))
         (package-name (string-upcase (format nil "~A/PACKAGE" system-name)))
         (asd-file
           (merge-pathnames
             (make-pathname :name system-name :type "asd")
             directory))
         (package-file (merge-pathnames #P"package.lisp" directory))
         (source-file (merge-pathnames #P"explicit-source.lisp" directory))
         (options
           (cl-weave/cli::make-cli-options
             :systems
             (list system-name)
             :load-files
             (list asd-file source-file))))
    (unwind-protect
        (progn
          (with-open-file
            (stream
              asd-file
              :direction
              :output
              :if-exists
              :supersede
              :if-does-not-exist
              :create)
            (format
              stream
              "(asdf:defsystem ~S :serial t :components ((:file ~S)))~%"
              system-name
              "package"))
          (with-open-file
            (stream
              package-file
              :direction
              :output
              :if-exists
              :supersede
              :if-does-not-exist
              :create)
            (format stream "(defpackage ~S (:use #:cl))~%" package-name))
          (with-open-file
            (stream
              source-file
              :direction
              :output
              :if-exists
              :supersede
              :if-does-not-exist
              :create)
            (format
              stream
              "(in-package ~S)~%(defparameter *loaded-after-system* t)~%"
              package-name))
          (expect (cl-weave/cli::load-requested-inputs options) :to-be nil)
          (let ((loaded-symbol
                  (find-symbol "*LOADED-AFTER-SYSTEM*" package-name)))
            (expect
              (and
               loaded-symbol
               (boundp loaded-symbol)
               (symbol-value loaded-symbol))
              :to-be
              t)))
      (when (asdf:find-system system-name nil)
        (asdf:clear-system system-name))
      (let ((package (find-package package-name)))
        (when package
          (delete-package package)))
      (uiop:delete-directory-tree
        directory
        :validate
        t
        :if-does-not-exist
        :ignore))))

(it
  "loads project systems through ASDF"
  (let* ((options (cl-weave/cli::make-cli-options :systems '("cl-weave/test")))
         (loaded-asdf-systems '()))
    (with-mocked-functions
      (((symbol-function 'asdf:find-system)
          (lambda (&rest args)
            (declare (ignore args))
            :cl-weave/test))
        ((symbol-function 'asdf:load-system)
          (lambda (system)
            (push system loaded-asdf-systems)
            :loaded-asdf)))
      (expect (cl-weave/cli::load-requested-inputs options) :to-be nil)
      (expect loaded-asdf-systems :to-equal '("cl-weave/test")))))

(it
  "recompiles requested systems when coverage is enabled"
  (let* ((options
        (cl-weave/cli::make-cli-options
          :systems
          '("cl-weave/test")
          :coverage-systems
          '("cl-weave")
          :coverage
          t))
         (loaded-asdf-systems '()))
    (with-mocked-functions
      (((symbol-function 'asdf:find-system)
          (lambda (&rest args)
            (declare (ignore args))
            :cl-weave/test))
        ((symbol-function 'asdf:load-system)
          (lambda (system &key force)
            (push (list system force) loaded-asdf-systems)
            :loaded-asdf)))
      (expect (cl-weave/cli::load-requested-inputs options) :to-be nil)
      (expect loaded-asdf-systems :to-equal '(("cl-weave/test" t) ("cl-weave" t))))))

(it
  "reports actionable CLI errors when requested systems remain unavailable"
  (let* ((cwd #P"/tmp/cl-weave-missing/")
         (helper-file #P"/tmp/cl-weave-missing/support/helper.lisp")
         (helper-directory (uiop:pathname-directory-pathname helper-file))
         (cwd-asd #P"/tmp/cl-weave-missing/missing-system.asd")
         (helper-asd #P"/tmp/cl-weave-missing/support/missing-system.asd")
         (options
           (cl-weave/cli::make-cli-options
             :systems
             (quote ("missing-system"))
             :load-files
             (list helper-file)))
         (loaded-files (quote ()))
         (searched-pathnames (quote ()))
         (message nil))
    (with-relaxed-package-locks
      (with-mocked-functions
        (((symbol-function (quote cl-weave/cli::system-bootstrap-directories))
            (lambda (ignored-options)
              (declare (ignore ignored-options))
              (list cwd helper-directory)))
          ((symbol-function (quote uiop:file-exists-p))
            (lambda (pathname)
              (push pathname searched-pathnames)
              nil))
          ((symbol-function (quote cl:load))
            (lambda (pathname &rest arguments)
              (declare (ignore arguments))
              (push pathname loaded-files)))
          ((symbol-function (quote asdf:find-system))
            (lambda (system &optional errorp)
              (declare (ignore system errorp))
              nil)))
        (handler-case (cl-weave/cli::load-requested-inputs options)
          (cl-weave/cli::cli-error (condition)
            (setf message (princ-to-string condition))))
        (expect loaded-files :to-be nil)
        (expect message :to-contain "Unable to locate ASDF system \"missing-system\"")
        (expect message :to-contain "CL_SOURCE_REGISTRY")
        (expect searched-pathnames :to-equal (list helper-asd cwd-asd))))))

(it
  "normalizes metadata reporter spec to JSON output"
  (let* ((options (parse-cli '("metadata" "cl-weave/test" "--reporter" "spec")))
         (output (framework-metadata-output options)))
    (expect (cl-weave/cli::metadata-reporter options) :to-be :json)
    (expect output :to-contain "\"schemaVersion\":23")
    (expect output :to-contain "\"kind\":\"cl-weave-metadata\"")))

(it
  "normalizes spec metadata reporter before writing output"
  (let* ((output-file (test-temporary-pathname "cl-weave-metadata-spec.json"))
         (options
        (parse-cli
          (list "metadata" "--reporter" "spec" "--output" (namestring output-file)))))
    (when (probe-file output-file)
      (delete-file output-file))
    (unwind-protect (progn
        (expect
          (with-output-to-string (*standard-output*)
            (cl-weave/cli::run-command options))
          :to-equal
          "")
        (let ((output (read-text-file output-file)))
          (expect output :to-contain "\"kind\":\"cl-weave-metadata\"")
          (expect output :to-contain "\"schemaVersion\":23")
          (expect output :to-contain "\"qualityGates\"")
          (expect output :not :to-contain ":KIND")))
      (when (probe-file output-file)
        (delete-file output-file)))))

(it
  "reports doctor success so a failing check drives a non-zero exit"
  ;; A healthy run (no unresolved system) succeeds; a bogus requested system
  ;; makes a check fail, and report-doctor must return false so main exits
  ;; non-zero and CI can gate on `cl-weave doctor SYSTEM`.
  (let ((healthy (parse-cli '("doctor")))
        (broken (parse-cli '("doctor" "no-such-system-xyzzy"))))
    (expect (with-output-to-string (stream)
              (expect (cl-weave/cli::report-doctor healthy stream) :to-be-truthy))
            :to-contain "\"status\":\"pass\"")
    (expect (with-output-to-string (stream)
              (expect (cl-weave/cli::report-doctor broken stream) :to-be-falsy))
            :to-contain "\"status\":\"fail\"")))

(it
  "normalizes doctor reporter spec to JSON output"
  (let* ((options (parse-cli '("doctor" "--reporter" "spec")))
         (output
        (with-output-to-string (stream)
          (cl-weave/cli::report-doctor options stream))))
    (expect (cl-weave/cli::doctor-reporter options) :to-be :json)
    (expect output :to-contain "\"schemaVersion\":1")
    (expect output :to-contain "\"kind\":\"doctor-report\"")))

(it
  "rejects unsupported structured reporters early"
  (dolist (contract
      '(("doctor"
          cl-weave/cli::doctor-reporter
          "cl-weave: doctor mode supports json and sexp reporters.")
        ("metadata"
          cl-weave/cli::metadata-reporter
          "cl-weave: metadata mode supports json and sexp reporters.")))
    (destructuring-bind (command reporter-function message) contract
      (dolist (reporter '("tap" "github" "junit" "jsonl"))
        (let ((options (parse-cli (list command "--reporter" reporter))))
          (expect
            (lambda ()
              (funcall reporter-function options))
            :to-throw
            message))))))

(it
  "prints AI-friendly command usage"
  (let ((usage (cl-weave/cli::cli-usage)))
    (expect usage :to-contain "cl-weave run [SYSTEM] [options]")
    (expect usage :to-contain "cl-weave doctor [SYSTEM] [options]")
    (expect usage :to-contain "cl-weave metadata [SYSTEM] [options]")
    (expect usage :to-contain "cl-weave version")
    (expect usage :to-contain "cl-weave help")
    (expect usage :to-contain "--reporter REPORTER")
    (expect usage :to-contain "--shard INDEX/COUNT")
    (expect usage :to-contain "--retry INTEGER")
    (expect usage :to-contain "--test-timeout-ms MS")
    (expect usage :to-contain "--filter TEXT")
    (expect usage :to-contain "--output FILE")
    (expect usage :to-contain "--fail-with-no-tests")
    (expect usage :to-contain "--snapshot-dir DIR")
    (expect usage :to-contain "--snapshot-file FILE")
    (expect usage :to-contain "--update-snapshots")
    (expect usage :to-contain "--version")))

(it
  "keeps command usage synchronized with CLI option metadata"
  (let ((usage (cl-weave/cli::cli-usage)))
    (dolist (entry (getf (cl-weave/metadata:framework-metadata) :options))
      (let ((name (getf entry :name))
            (argument (getf entry :argument)))
        (expect
          usage
          :to-contain
          (if argument (format nil "~A ~A" name argument)
            name))))))
