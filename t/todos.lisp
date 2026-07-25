(in-package #:cl-weave/test)

(describe "todos"
  (it "registers todo tests with a stable reason"
    (let ((cl-weave::*root-suite* (cl-weave::make-suite :name "root"))
          (cl-weave::*current-suite* nil))
      (it-todo "documents pending work" "intentional")
      (let ((events (cl-weave::collect-events cl-weave::*root-suite*)))
        (expect (mapcar #'cl-weave::test-event-status events) :to-equal '(:todo))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("intentional")))))

  (it "registers todo.each cases without running bodies"
    (let ((root (cl-weave::make-suite :name "root")))
      (let ((cl-weave::*root-suite* root)
            (cl-weave::*current-suite* nil))
        (it-todo-each ((1 2 3) (2 3 5))
            "adds ~A and ~A"
            (left right total)
          "awaiting implementation"))
      (let ((events (cl-weave::collect-events root)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:todo :todo))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("awaiting implementation" "awaiting implementation"))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("adds 1 and 2") ("adds 2 and 3"))))))

  (it "reports todo tests without running their body"
    (let* ((called nil)
           (test (cl-weave::make-test-case
                  :name "todo case"
                  :function (lambda () (setf called t))
                  :todo-reason "pending"))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect called :to-be nil)
      (expect (cl-weave::test-event-status event) :to-be :todo)
      (expect (cl-weave::test-event-reason event) :to-equal "pending")
      (expect (cl-weave::passed-event-p event) :to-be-truthy)))

  (it "reports todo suite descendants without running hooks or bodies"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "pending"
                    :parent root
                    :todo-reason "suite pending"
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
        (expect (mapcar #'cl-weave::test-event-status events) :to-equal '(:todo))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("suite pending"))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("pending" "case"))))))

  (it "registers todo.each suites with suppressed descendants"
    (let ((root (cl-weave::make-suite :name "root"))
          (ran nil))
      (let ((cl-weave::*root-suite* root)
            (cl-weave::*current-suite* nil))
        (describe-todo-each ((1 2 3) (2 3 5))
            "pending ~A and ~A"
            (left right total)
          "suite pending"
          (it "case"
            (setf ran (list left right total)))))
      (let ((events (cl-weave::collect-events root)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:todo :todo))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("suite pending" "suite pending"))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("pending 1 and 2" "case")
                            ("pending 2 and 3" "case")))
        (expect ran :to-be nil)))))

