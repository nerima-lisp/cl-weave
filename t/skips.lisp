(in-package #:cl-weave/test)

(describe "skips"
  (it "does not run skipped tests"
    (let* ((called nil)
           (test (cl-weave::make-test-case
                  :name "skipped case"
                  :function (lambda () (setf called t))
                  :skip-reason "not implemented"))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect called :to-be nil)
      (expect (cl-weave::test-event-status event) :to-be :skip)
      (expect (cl-weave::test-event-reason event) :to-equal "not implemented")
      (expect (cl-weave::passed-event-p event) :to-be-truthy)))

  (it "reports skipped tests without failing the suite"
    (let* ((test (cl-weave::make-test-case
                  :name "skipped case"
                  :function (lambda () (error "should not run"))
                  :skip-reason "not implemented"))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :skip)
      (expect (cl-weave::test-event-reason event) :to-equal "not implemented")
      (expect (cl-weave::passed-event-p event) :to-be-truthy)))

  (it "reports skipped suite descendants without running hooks or bodies"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "blocked"
                    :parent root
                    :skip-reason "suite blocked"
                    :before-all (list (lambda () (error "before-all should not run")))
                    :after-all (list (lambda () (error "after-all should not run")))
                    :before-each (list (lambda () (error "before-each should not run")))
                    :after-each (list (lambda () (error "after-each should not run")))))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "case"
        :function (lambda () (error "test body should not run"))))
      (let ((events (cl-weave::collect-events root)))
        (expect (mapcar #'cl-weave::test-event-status events) :to-equal '(:skip))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("suite blocked"))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("blocked" "case"))))))

  (it "registers conditional tests as skipped or runnable cases"
    (let ((root (cl-weave::make-suite :name "root"))
          (ran nil))
      (let ((cl-weave::*root-suite* root)
            (cl-weave::*current-suite* nil))
        (it-skip-if t "skip-if true"
          (setf ran :skip-if-true))
        (it-run-if nil "run-if false"
          (setf ran :run-if-false))
        (it-skip-if nil "skip-if false"
          (setf ran :skip-if-false)))
      (let ((events (cl-weave::collect-events root)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:skip :skip :pass))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("conditional skip" "conditional run-if" nil))
        (expect ran :to-be :skip-if-false))))

  (it "registers conditional suites as skipped or runnable groups"
    (let ((root (cl-weave::make-suite :name "root"))
          (ran nil))
      (let ((cl-weave::*root-suite* root)
            (cl-weave::*current-suite* nil))
        (describe-skip-if t "skip-if suite"
          (before-all (setf ran :skip-before-all))
          (it "case" (setf ran :skip-body)))
        (describe-run-if nil "run-if suite"
          (it "case" (setf ran :run-if-body)))
        (describe-run-if t "enabled suite"
          (it "case" (setf ran :enabled-body))))
      (let ((events (cl-weave::collect-events root)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:skip :skip :pass))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("conditional skip" "conditional run-if" nil))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("skip-if suite" "case")
                            ("run-if suite" "case")
                            ("enabled suite" "case")))
        (expect ran :to-be :enabled-body)))))
