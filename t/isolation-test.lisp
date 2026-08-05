(in-package #:cl-weave/test)

(describe "isolation"
  (it "expands it-isolated into structured isolated execution"
    (expect (macroexpand-1
             '(it-isolated "child process"
                  (:systems ("cl-weave/test") :timeout 5)
                (expect 1 :to-be 1)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::run-isolated)
                   (tree-contains-p form 'cl-weave::signal-isolated-failure)))))

  (it-isolated "runs assertions in a child SBCL process"
      (:systems ("cl-weave/test") :timeout 180)
    (expect (+ 2 3) :to-be 5))

  (it "reports child process failures without failing the parent process"
    (let ((result (run-isolated
                   '(error "child boom")
                   :systems '("cl-weave/test")
                   :package "CL-WEAVE/TEST"
                   :timeout 180)))
      (expect (isolated-result-status result) :to-be :fail)
      (expect (cl-weave:isolated-result-elapsed-ms result) :to-be-greater-than-or-equal 0)
      (expect (isolated-result-exit-code result) :to-be 1)
      (expect (isolated-result-stderr result) :to-contain "child boom")
      (expect (isolated-result-script-path result) :to-be nil)
      (expect (isolated-result-stdout-path result) :to-be nil)
      (expect (isolated-result-stderr-path result) :to-be nil)
      (expect (isolated-result-home-path result) :to-be nil)))

  (it "terminates isolated tests on timeout"
    (let ((result (run-isolated
                   '(sleep 2)
                   :systems '("cl-weave/test")
                   :package "CL-WEAVE/TEST"
                   :timeout 0.1)))
      (expect (isolated-result-status result) :to-be :timeout)
      (expect (isolated-result-timed-out-p result) :to-be-truthy)))

  (it "cleans allocated temp files when a later allocation fails"
  (let ((original (symbol-function 'cl-weave::isolated-temp-pathname))
        (calls 0)
        allocated)
    (unwind-protect
         (with-mocked-functions
             (((symbol-function 'cl-weave::isolated-temp-pathname)
               (lambda (prefix type)
                 (incf calls)
                 (when (= calls 2)
                   (error "second allocation failed"))
                 (setf allocated (funcall original prefix type)))))
           (expect (lambda ()
                     (run-isolated '(values)
                                   :systems '("cl-weave/test")
                                   :package "CL-WEAVE/TEST"
                                   :timeout 180))
                   :to-throw
                   "second allocation failed")
           (expect allocated :to-satisfy #'pathnamep)
           (expect (probe-file allocated) :to-be nil))
      (when allocated
        (ignore-errors (delete-file allocated))))))

(it "retries temp directory allocation after a collision"
    (let* ((temporary-directory (uiop:temporary-directory))
           (collision-name "cl-weave-isolated-home-collision")
           (fresh-name "cl-weave-isolated-home-fresh")
           (collision-path (merge-pathnames
                            (make-pathname :directory (list :relative collision-name))
                            temporary-directory))
           (fresh-path (merge-pathnames
                        (make-pathname :directory (list :relative fresh-name))
                        temporary-directory))
           (names (list collision-name fresh-name)))
      (ensure-directories-exist collision-path)
      (when (probe-file fresh-path)
        (uiop:delete-directory-tree fresh-path
                                    :validate t
                                    :if-does-not-exist :ignore))
      (unwind-protect
           (with-mocked-functions
               (((symbol-function 'cl-weave::isolated-temp-name)
                 (lambda (prefix)
                   (declare (ignore prefix))
                   (pop names))))
             (let ((allocated (cl-weave::isolated-temp-directory "ignored")))
               (expect (namestring allocated) :to-be (namestring fresh-path))
               (expect (probe-file allocated) :to-be-truthy)))
        (uiop:delete-directory-tree collision-path
                                    :validate t
                                    :if-does-not-exist :ignore)
        (uiop:delete-directory-tree fresh-path
                                    :validate t
                                    :if-does-not-exist :ignore))))

  (it "preserves Unicode isolated output without trailing NUL characters"
    (let ((result (run-isolated
                   (quote (progn
                            (format t "雪😀")
                            (format *error-output* "警告")))
                   :systems (quote ("cl-weave/test"))
                   :package "CL-WEAVE/TEST"
                   :timeout 180
                   :keep-files t)))
      (unwind-protect
           (progn
             (expect (isolated-result-status result) :to-be :pass)
             (expect (cl-weave:isolated-result-stdout result) :to-equal "雪😀")
             (expect (isolated-result-stderr result) :to-equal "警告")
             (expect (probe-file (isolated-result-script-path result)) :to-be-truthy)
             (expect (probe-file (isolated-result-stdout-path result)) :to-be-truthy)
             (expect (probe-file (isolated-result-stderr-path result)) :to-be-truthy)
             (expect (probe-file (isolated-result-home-path result)) :to-be-truthy))
        (when (isolated-result-script-path result)
          (ignore-errors (delete-file (isolated-result-script-path result))))
        (when (isolated-result-stdout-path result)
          (ignore-errors (delete-file (isolated-result-stdout-path result))))
        (when (isolated-result-stderr-path result)
          (ignore-errors (delete-file (isolated-result-stderr-path result))))
        (when (isolated-result-home-path result)
          (ignore-errors
            (uiop:delete-directory-tree (isolated-result-home-path result)
                                        :validate t
                                        :if-does-not-exist :ignore))))))

  (it "keeps isolated artifacts only on failure when requested"
    (let ((pass-result (run-isolated
                        '(expect 1 :to-be 1)
                        :systems '("cl-weave/test")
                        :package "CL-WEAVE/TEST"
                        :timeout 180
                        :keep-files :on-failure))
          (fail-result (run-isolated
                        '(error "keep failure artifacts")
                        :systems '("cl-weave/test")
                        :package "CL-WEAVE/TEST"
                        :timeout 180
                        :keep-files :on-failure)))
      (unwind-protect
           (progn
             (expect (isolated-result-status pass-result) :to-be :pass)
             (expect (isolated-result-script-path pass-result) :to-be nil)
             (expect (isolated-result-status fail-result) :to-be :fail)
             (expect (probe-file (isolated-result-script-path fail-result)) :to-be-truthy)
             (expect (probe-file (isolated-result-stdout-path fail-result)) :to-be-truthy)
             (expect (probe-file (isolated-result-stderr-path fail-result)) :to-be-truthy)
             (expect (probe-file (isolated-result-home-path fail-result)) :to-be-truthy))
        (when (isolated-result-script-path fail-result)
          (ignore-errors (delete-file (isolated-result-script-path fail-result))))
        (when (isolated-result-stdout-path fail-result)
          (ignore-errors (delete-file (isolated-result-stdout-path fail-result))))
        (when (isolated-result-stderr-path fail-result)
          (ignore-errors (delete-file (isolated-result-stderr-path fail-result))))
        (when (isolated-result-home-path fail-result)
          (ignore-errors
            (uiop:delete-directory-tree (isolated-result-home-path fail-result)
                                        :validate t
                                        :if-does-not-exist :ignore))))))

  (it "passes keep-files through it-isolated"
    (expect (macroexpand-1
             '(it-isolated "child process"
                  (:systems ("cl-weave/test") :timeout 5 :keep-files :on-failure)
                (expect 1 :to-be 1)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form :keep-files)
                   (tree-contains-p form :on-failure)))))

  (it "starts a child from the SBCL running the suite"
    (call-with-image-anchors
     #P"/opt/sbcl/bin/sbcl"
     #P"/opt/sbcl/lib/sbcl/sbcl.core"
     (lambda ()
       (expect (cl-weave::isolated-sbcl-program) :to-equal "/opt/sbcl/bin/sbcl"))))

  (it "starts a child from PATH when the suite runs inside a delivered binary"
    ;; In a standalone executable image the runtime and the core are the same
    ;; file, and that file is cl-weave, which does not accept --script.
    (call-with-image-anchors
     #P"/opt/cl-weave/bin/cl-weave"
     #P"/opt/cl-weave/bin/cl-weave"
     (lambda ()
       (expect (cl-weave::isolated-sbcl-program) :to-equal "sbcl")))))

(describe "isolation internal normalization and failure-signaling gaps"
  (it "normalizes isolated systems across NIL, string, symbol, and list forms"
    (expect (cl-weave::normalize-isolated-systems nil) :to-be nil)
    (expect (cl-weave::normalize-isolated-systems "cl-weave") :to-equal '("cl-weave"))
    (expect (cl-weave::normalize-isolated-systems 'cl-weave) :to-equal '("cl-weave"))
    (expect (cl-weave::normalize-isolated-systems '(cl-weave "cl-weave/test"))
            :to-equal
            '("cl-weave" "cl-weave/test")))

  (it "rejects an unsupported isolated systems designator"
    (expect (lambda () (cl-weave::normalize-isolated-systems 42))
            :to-throw
            "isolated systems must be a string, symbol, or list"))

  (it "rejects an unsupported isolated keep-files value"
    (expect (lambda () (cl-weave::normalize-isolated-keep-files :always))
            :to-throw
            "isolated keep-files must be NIL, T, or :ON-FAILURE"))

  (it "reads an absent isolated artifact file as an empty string"
    (expect (cl-weave::read-file-string-or-empty
             (merge-pathnames "no-such-isolated-artifact.txt"
                              (uiop:temporary-directory)))
            :to-equal
            ""))

  (it "reports temp directory exhaustion when every candidate collides"
    (with-mocked-functions
        (((symbol-function 'cl-weave::isolated-create-temp-directory)
          (lambda (pathname) (declare (ignore pathname)) nil)))
      (expect (lambda () (cl-weave::isolated-temp-directory "cl-weave-isolated-exhaustion"))
              :to-throw
              "failed to allocate isolated temp directory")))

  (it "signals a structured assertion failure for a failed isolated result"
    (let ((result (cl-weave::make-isolated-result
                   :status :fail
                   :exit-code 1
                   :stdout "child stdout"
                   :stderr "child stderr"
                   :timed-out-p nil
                   :elapsed-ms 12
                   :script-path nil
                   :stdout-path nil
                   :stderr-path nil
                   :home-path nil)))
      (handler-case
          (progn
            (cl-weave::signal-isolated-failure result '(it-isolated "child"))
            (expect nil :to-be-truthy))
        (cl-weave:assertion-failure (condition)
          (with-assertion-detail (detail condition actual expected)
            (expect (cl-weave::assertion-detail-matcher detail) :to-be :isolated)
            (expect (cl-weave::assertion-detail-negated detail) :to-be nil)
            (expect (cl-weave::assertion-detail-pass detail) :to-be nil)
            (expect (getf actual :status) :to-be :fail)
            (expect (getf actual :exit-code) :to-be 1)
            (expect (getf actual :stdout) :to-equal "child stdout")
            (expect (getf actual :stderr) :to-equal "child stderr")
            (expect expected :to-equal '(:status :pass :exit-code 0))))))))
