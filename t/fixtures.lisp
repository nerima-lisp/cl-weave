(in-package #:cl-weave/test)

(describe "fixtures"
  (before-all
    (setf *fixture-events* (list :before-all)))

  (before-each
    (setf *fixture-value* 41)
    (push :before-each *fixture-events*)
    (setf (gethash :trace *test-context*) '(:before)))

  (after-each
    (push :after-each *fixture-events*)
    (setf *fixture-value* nil))

  (after-all
    (setf *fixture-events* nil))

  (it "runs before-each with dynamic context"
    (expect *fixture-events* :to-equal '(:before-each :before-all))
    (expect *fixture-value* :to-be 41)
    (expect (gethash :trace *test-context*) :to-equal '(:before))
    (incf *fixture-value*)
    (expect *fixture-value* :to-be 42))

  (it "keeps before-all state across cases"
    (expect *fixture-events* :to-equal '(:before-each :after-each :before-each :before-all)))

  (it "keeps camelCase fixture aliases out of the public package"
    (dolist (name '("BEFOREALL" "AFTERALL" "BEFOREEACH" "AFTEREACH"))
      (multiple-value-bind (symbol status) (find-symbol name "CL-WEAVE")
        (declare (ignore symbol))
        (expect-not status :to-be :external))))

  (it "keeps FiveAM-style aliases out of the public package"
    (dolist (name '("DEF-SUITE" "IN-SUITE" "TEST" "IS"))
      (multiple-value-bind (symbol status) (find-symbol name "CL-WEAVE")
        (declare (ignore symbol))
        (expect-not status :to-be :external))))

  (it "represents suite and test metadata as readable structures"
    (let* ((test (cl-weave::make-test-case
                  :name "works"
                  :function (lambda () t)
                  :focus t
                  :location '(:file "example.lisp" :line 12)))
           (suite (cl-weave::make-suite
                   :name "model"
                   :children (list test))))
      (expect suite :to-satisfy #'cl-weave::suite-p)
      (expect test :to-satisfy #'cl-weave::test-case-p)
      (expect (cl-weave::suite-children suite) :to-equal (list test))
      (expect (princ-to-string suite) :to-contain "model")
      (expect (princ-to-string suite) :to-contain ":children 1")
      (expect (princ-to-string test) :to-contain "works")
      (expect (princ-to-string test) :to-contain ":focus T")))

  (it "reports model conditions with actionable context"
    (loop for (condition fragment)
            in (list
                (list (make-condition
                       'cl-weave::assertion-failure
                       :detail (cl-weave::make-assertion-detail
                                :form '(expect value :to-be 42)))
                      "EXPECT VALUE :TO-BE 42")
                (list (make-condition 'cl-weave:test-timeout :timeout-ms 250)
                      "250 ms timeout")
                (list (make-condition
                       'cl-weave:expected-failure-missed
                       :reason "known defect")
                      "known defect"))
          do (let ((*package* (find-package '#:cl-weave/test)))
               ;; The pretty printer may wrap long assertion forms.
               (expect (normalize-command-document-text
                        (princ-to-string condition))
                       :to-contain fragment))))

  (it "wraps each test body with around-each continuations"
    (let ((root (cl-weave::make-suite :name "root"))
          (events nil))
      (let ((*fixture-value* :outer)
            (cl-weave::*current-suite* root)
            (cl-weave::*root-suite* root))
        (cl-weave::register-suite
         "around"
         (lambda ()
           (before-each
             (push :before events))
           (around-each (next)
             (push (list :enter *fixture-value*) events)
             (let ((*fixture-value* :inner))
               (funcall next))
             (push (list :exit *fixture-value*) events))
           (after-each
             (push :after events))
           (it "case"
             (push (list :body *fixture-value*) events)))))
      (cl-weave::collect-events root)
      (expect (reverse events)
              :to-equal '(:before (:enter 41) (:body :inner) (:exit 41) :after))))

  (progn
  (it "runs around-each cleanup before after-each when body fails"
    (let ((root (cl-weave::make-suite :name "root"))
          (events nil))
      (let ((cl-weave::*current-suite* root)
            (cl-weave::*root-suite* root))
        (cl-weave::register-suite
         "around cleanup"
         (lambda ()
           (around-each (next)
             (unwind-protect
                  (funcall next)
               (push :around-cleanup events)))
           (after-each
             (push :after events))
           (it "case"
             (error "boom")))))
      (let ((result (cl-weave::collect-events root)))
        (expect (mapcar (function cl-weave::test-event-status) result) :to-equal (quote (:error))))
      (expect (reverse events) :to-equal (quote (:around-cleanup :after)))))

  (it "resolves dynamically added hooks at their execution phase"
    (let ((events nil)
          (suite (cl-weave::make-suite :name "dynamic hooks")))
      (setf (cl-weave::suite-before-each suite)
            (list
             (lambda ()
               (push :before events)
               (setf (cl-weave::suite-around-each suite)
                     (list
                      (lambda (next)
                        (push :around-enter events)
                        (funcall next)
                        (push :around-exit events)))))))
      (let ((test
              (cl-weave::make-test-case
               :name "case"
               :function
               (lambda ()
                 (push :body events)
                 (setf (cl-weave::suite-after-each suite)
                       (list (lambda () (push :after events))))))))
        (cl-weave::run-test-case suite test))
      (expect (reverse events)
              :to-equal
              (quote (:before :around-enter :body :around-exit :after)))))))

  (it "runs after-all exactly once without replacing a non-local exit"
  (let* ((after-count 0)
         (suite (cl-weave::make-suite
                 :name "non-local suite exit"
                 :after-all (list (lambda () (incf after-count)))))
         (test (cl-weave::make-test-case
                :name "escape"
                :function (lambda () (throw (quote suite-exit) :escaped)))))
    (cl-weave::add-child suite test)
    (expect (catch (quote suite-exit)
              (cl-weave::collect-events suite))
            :to-equal :escaped)
    (expect after-count :to-be 1)))

(it "normalizes an around-each wrapper error as a hook failure"
    (let* ((cause (make-condition 'simple-error :format-control "wrapper failed"))
           (suite
             (cl-weave::make-suite
              :name "around wrapper"
              :around-each
              (list (lambda (next)
                      (declare (ignore next))
                      (error cause)))))
           (test (cl-weave::make-test-case :name "case" :function (lambda () t)))
           (event (cl-weave::run-test-case suite test))
           (condition (cl-weave::test-event-condition event)))
      (expect (cl-weave::test-event-status event) :to-be :error)
      (expect condition :to-be-instance-of 'cl-weave:hook-failure)
      (expect (cl-weave:hook-failure-phase condition) :to-be :around-each)
      (expect (cl-weave:hook-failure-causes condition) :to-equal (list cause))))

  (it "does not wrap a test error propagated through around-each"
    (let* ((cause (make-condition 'simple-error :format-control "test failed"))
           (suite
             (cl-weave::make-suite
              :name "around continuation"
              :around-each (list (lambda (next) (funcall next)))))
           (test
             (cl-weave::make-test-case
              :name "case"
              :function (lambda () (error cause))))
           (event (cl-weave::run-test-case suite test)))
      (expect (cl-weave::test-event-status event) :to-be :error)
      (expect (cl-weave::test-event-condition event) :to-be cause)))

  (progn
  (it "runs inherited hooks in parent-child order"
    (let* ((events nil)
           (root (cl-weave::make-suite :name "root"))
           (parent
             (cl-weave::add-child
              root
              (cl-weave::make-suite
               :name "parent"
               :parent root
               :before-each (list (lambda () (push :parent-before events)))
               :around-each (list (lambda (next)
                                       (push :parent-around-enter events)
                                       (funcall next)
                                       (push :parent-around-exit events)))
               :after-each (list (lambda () (push :parent-after events))))))
           (child
             (cl-weave::add-child
              parent
              (cl-weave::make-suite
               :name "child"
               :parent parent
               :before-each (list (lambda () (push :child-before events)))
               :around-each (list (lambda (next)
                                       (push :child-around-enter events)
                                       (funcall next)
                                       (push :child-around-exit events)))
               :after-each (list (lambda () (push :child-after events))))))
           (test (cl-weave::make-test-case
                  :name "case"
                  :function (lambda () (push :body events)))))
      (cl-weave::add-child child test)
      (cl-weave::collect-events root)
      (expect (reverse events)
              :to-equal '(:parent-before
                          :child-before
                          :parent-around-enter
                          :child-around-enter
                          :body
                          :child-around-exit
                          :parent-around-exit
                          :child-after
                          :parent-after))))
  (it "resolves around-each after before-each mutations"
  (let ((events nil)
        (suite nil))
    (setf suite
          (cl-weave::make-suite
           :name "mutated around hook"
           :before-each
           (list (lambda ()
                   (setf (cl-weave::suite-around-each suite)
                         (list (lambda (next)
                                 (push :around events)
                                 (funcall next))))))))
    (let* ((test
             (cl-weave::make-test-case
              :name "case"
              :function (lambda () (push :body events))))
           (event (cl-weave::run-test-case suite test)))
      (expect (cl-weave::test-event-status event) :to-be :pass)
      (expect (reverse events) :to-equal '(:around :body)))))
  (it "resolves after-each after test body mutations"
    (let* ((events nil)
           (suite
             (cl-weave::make-suite
              :name "mutated after hook"
              :after-each (list (lambda () (push :original-after events)))))
           (test
             (cl-weave::make-test-case
              :name "case"
              :function
              (lambda ()
                (push :body events)
                (setf (cl-weave::suite-after-each suite)
                      (list (lambda () (push :updated-after events))))))))
      (let ((event (cl-weave::run-test-case suite test)))
        (expect (cl-weave::test-event-status event) :to-be :pass)
        (expect (reverse events) :to-equal '(:body :updated-after))))))

(describe "fixture failures"
  (it "aggregates before-each failures without running the body"
    (let ((log nil))
      (let* ((suite
               (cl-weave::make-suite
                :name "setup"
                :before-each
                (list (lambda ()
                        (push :first log)
                        (error "first setup"))
                      (lambda ()
                        (push :second log)
                        (error "second setup")))))
             (test
               (cl-weave::make-test-case
                :name "case"
                :function (lambda () (push :body log))))
             (event (cl-weave::run-test-case suite test))
             (condition (cl-weave::test-event-condition event)))
        (expect (cl-weave::test-event-status event) :to-be :error)
        (expect (cl-weave:hook-failure-phase condition) :to-be :before-each)
        (expect (length (cl-weave:hook-failure-causes condition)) :to-be 2)
        (expect log :to-equal '(:second :first)))))

  (it "preserves a primary assertion failure and records every cleanup failure"
    (let* ((cleanup-log nil)
           (suite
             (cl-weave::make-suite
              :name "cleanup"
              :after-each
              (list (lambda ()
                      (push :first cleanup-log)
                      (error "first cleanup"))
                    (lambda ()
                      (push :second cleanup-log)
                      (error "second cleanup")))))
           (test
             (cl-weave::make-test-case
              :name "primary"
              :function
              (lambda ()
                (error 'cl-weave:assertion-failure
                       :detail (cl-weave::make-assertion-detail
                                :form '(expect nil :to-be t))))))
           (event (cl-weave::run-test-case suite test)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-condition event)
              :to-satisfy (lambda (condition)
                            (typep condition 'cl-weave:assertion-failure)))
      (expect cleanup-log :to-equal '(:first :second))
      (expect (length (cl-weave::test-event-secondary-conditions event))
              :to-be 2)))

  (it "collects bare serious conditions from after-each and continues cleanup"
  (let* ((log nil)
         (bare-condition (make-condition (quote serious-condition)))
         (suite
           (cl-weave::make-suite
            :name "cleanup"
            :after-each
            (list (lambda () (push :after-serious log))
                  (lambda ()
                    (push :serious log)
                    (error bare-condition))
                  (lambda ()
                    (push :before-serious log)
                    (error "ordinary cleanup")))))
         (test (cl-weave::make-test-case :name "case" :function (lambda () t)))
         (event (cl-weave::run-test-case suite test))
         (condition (cl-weave::test-event-condition event))
         (causes (cl-weave:hook-failure-causes condition)))
    (expect (cl-weave::test-event-status event) :to-be :error)
    (expect condition
            :to-satisfy (lambda (value)
                          (typep value (quote cl-weave:hook-failure))))
    (expect (cl-weave:hook-failure-phase condition) :to-be :after-each)
    (expect (length causes) :to-be 2)
    (expect (second causes) :to-be bare-condition)
    (expect log :to-equal (quote (:after-serious :serious :before-serious)))))

  (it "turns suite hook failures into events and continues after bare serious conditions"
  (let ((root (cl-weave::make-suite :name "root"))
        (log nil)
        (bare-condition (make-condition (quote serious-condition))))
    (let ((cl-weave::*current-suite* root)
          (cl-weave::*root-suite* root))
      (cl-weave::register-suite
       "broken suite"
       (lambda ()
         (before-all
           (push :before log)
           (error "setup"))
         (after-all
           (push :after-serious log))
         (after-all
           (push :serious log)
           (error bare-condition))
         (after-all
           (push :before-serious log)
           (error "ordinary teardown"))
         (it "must not run" (push :body log)))))
    (let* ((events (cl-weave::collect-events root))
           (conditions (mapcar (function cl-weave::test-event-condition) events))
           (after-all-causes
             (cl-weave:hook-failure-causes (second conditions))))
      (expect (mapcar (function cl-weave::test-event-status) events)
              :to-equal (quote (:error :error)))
      (expect (mapcar (function cl-weave:hook-failure-phase) conditions)
              :to-equal (quote (:before-all :after-all)))
      (expect (length after-all-causes) :to-be 2)
      (expect (second after-all-causes) :to-be bare-condition)
      (expect log
              :to-equal
              (quote (:after-serious :serious :before-serious :before)))))))
