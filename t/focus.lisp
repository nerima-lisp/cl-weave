(in-package #:cl-weave/test)

(describe "focus"
  (it "runs only focused tests when any focus exists"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "focus" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       root
       (cl-weave::make-test-case
        :name "outside"
        :function (lambda () (push :outside events-log))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "inside"
        :function (lambda () (push :inside events-log))
        :focus t))
      (let ((events (cl-weave::collect-events root)))
        (expect events-log :to-equal '(:inside))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("focus" "inside")))))))

  (it "runs only it-only-each cases when they introduce focus"
    (let ((root (cl-weave::make-suite :name "root"))
          (events-log nil))
      (let ((cl-weave::*root-suite* root)
            (cl-weave::*current-suite* nil))
        (it "outside"
          (setf events-log (append events-log '(:outside))))
        (it-only-each ((1 2 3) (2 3 5))
            "adds ~A and ~A"
            (left right total)
          (setf events-log
                (append events-log (list (list left right total)))))
        (it "after"
          (setf events-log (append events-log '(:after)))))
      (let ((events (cl-weave::collect-events root)))
        (expect events-log :to-equal '((1 2 3) (2 3 5)))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("adds 1 and 2")
                            ("adds 2 and 3"))))))
