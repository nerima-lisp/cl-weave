(in-package #:cl-weave/test)

(describe "asdf integration"
  (it "reloads systems through ASDF without accumulating registered tests"
  (let ((loaded-systems nil)
        (suite-counts nil)
        (cl-weave::*root-suite* nil)
        (cl-weave::*current-suite* nil)
        (cl-weave::*named-suites* (make-hash-table :test (function equal))))
    (with-mocked-functions
        (((symbol-function (quote asdf:load-system))
          (lambda (system &key force)
            (push (list system force) loaded-systems)
            (cl-weave::register-suite "loaded" (lambda () nil))
            t))
         ((symbol-function (quote cl-weave:run-all))
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (push (length (cl-weave::suite-children
                           (cl-weave::root-suite)))
                  suite-counts)
            t)))
      (expect (cl-weave:run-system "cl-weave/test") :to-be-truthy)
      (expect (cl-weave:run-system "cl-weave/test") :to-be-truthy)
      (expect (nreverse loaded-systems)
              :to-equal (quote (("cl-weave/test" t) ("cl-weave/test" t))))
      (expect (nreverse suite-counts) :to-equal (quote (1 1))))))

  (it "clears registered tests before each watched system reload"
    (let ((suite-counts nil)
          (cl-weave::*root-suite* nil)
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test #'equal)))
      (with-mocked-functions
          (((symbol-function 'asdf:load-system)
            (lambda (system &key force)
              (declare (ignore system force))
              (cl-weave::register-suite "watched" (lambda () nil))
              t))
           ((symbol-function 'cl-weave:run-all)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (push (length (cl-weave::suite-children
                             (cl-weave::root-suite)))
                    suite-counts)
              t)))
        (cl-weave::run-watched-system "watched")
        (cl-weave::run-watched-system "watched"))
      (expect (nreverse suite-counts) :to-equal '(1 1)))))

(describe "asdf test-op"
  (it "fails when no tests are registered"
    (let ((cl-weave::*root-suite* nil)
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test (function equal))))
      (expect
       (lambda ()
         (asdf:perform (asdf:make-operation (quote asdf:test-op))
                       (asdf:find-system "cl-weave/test")))
       :to-throw
       "cl-weave self test suite failed."))))

(describe "watch incremental reload routing"
  (it "routes to incremental reload when only non-definition files changed"
    (let ((calls nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::atomic-incremental-system-reload)
            (lambda (system changed-pathnames)
              (declare (ignore changed-pathnames))
              (push (list :incremental system) calls)
              t))
           ((symbol-function 'cl-weave::atomic-full-system-reload)
            (lambda (system)
              (push (list :full system) calls)
              t))
           ((symbol-function 'cl-weave:run-all)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              t)))
        (let ((cl-weave::*watch-incremental-reload-p* t)
              (cl-weave::*watch-changed-pathnames* (list #P"changed.lisp")))
          (expect (cl-weave:run-system "cl-weave/test") :to-be-truthy)))
      (expect calls :to-equal (list (list :incremental "cl-weave/test")))))
  (it "routes to full reload when a changed pathname is an asd definition"
    (let ((calls nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::atomic-incremental-system-reload)
            (lambda (system changed-pathnames)
              (declare (ignore changed-pathnames))
              (push (list :incremental system) calls)
              t))
           ((symbol-function 'cl-weave::atomic-full-system-reload)
            (lambda (system)
              (push (list :full system) calls)
              t))
           ((symbol-function 'cl-weave:run-all)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              t)))
        (let ((cl-weave::*watch-incremental-reload-p* t)
              (cl-weave::*watch-changed-pathnames* (list #P"changed.asd")))
          (expect (cl-weave:run-system "cl-weave/test") :to-be-truthy)))
      (expect calls :to-equal (list (list :full "cl-weave/test"))))))
