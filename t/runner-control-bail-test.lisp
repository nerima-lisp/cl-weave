(in-package #:cl-weave/test)

(describe "bail"
  (it "stops after the first failing event"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "bail" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "first"
        :function (lambda ()
                    (setf events-log (append events-log '(:first)))
                    (expect nil :to-be-truthy))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "second"
        :function (lambda ()
                    (setf events-log (append events-log '(:second))))))
      (let ((events (cl-weave::collect-events root :bail t)))
        (expect (mapcar #'cl-weave::test-event-status events) :to-equal '(:fail))
        (expect events-log :to-equal '(:first)))))

  (it "accepts an integer failure limit"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "bail" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "first"
        :function (lambda ()
                    (setf events-log (append events-log '(:first)))
                    (expect nil :to-be-truthy))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "second"
        :function (lambda ()
                    (setf events-log (append events-log '(:second))))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "third"
        :function (lambda ()
                    (setf events-log (append events-log '(:third)))
                    (error "boom"))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "fourth"
        :function (lambda ()
                    (setf events-log (append events-log '(:fourth))))))
      (let ((events (cl-weave::collect-events root :bail 2)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:fail :pass :error))
        (expect events-log :to-equal '(:first :second :third)))))

  (it "bounds bail before executing tests"
  (expect (cl-weave::collect-events
           (cl-weave::make-suite :name "empty")
           :bail cl-weave::+maximum-bail-limit+)
          :to-be-null)
  (dolist (bail `(,(1+ cl-weave::+maximum-bail-limit+)
                   -1 :yes "1"))
    (let ((executed nil)
          (root (cl-weave::make-suite :name "root")))
      (add-tripwire-test-case root (lambda () (setf executed t)))
      (expect (lambda ()
                (cl-weave::collect-events root :bail bail))
              :to-throw
              "Bail must be")
      (expect executed :to-be nil)))))

