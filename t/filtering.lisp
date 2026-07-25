(in-package #:cl-weave/test)

(describe "filtering"
  (it "runs only tests matching a path substring"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "math" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "adds numbers"
        :function (lambda () (push :add events-log))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "subtracts numbers"
        :function (lambda () (push :subtract events-log))))
      (let ((events (cl-weave::collect-events root :name-filter "MATH > ADDS")))
        (expect events-log :to-equal '(:add))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("math" "adds numbers"))))))

  (it "does not run suite hooks when no child matches the filter"
    (let* ((root (cl-weave::make-suite :name "root"))
           (hook-events nil)
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "filtered"
                    :parent root
                    :before-all (list (lambda () (push :before-all hook-events)))
                    :after-all (list (lambda () (push :after-all hook-events)))))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "hidden"
        :function (lambda () (push :test hook-events))))
      (expect (cl-weave::collect-events root :name-filter "missing")
              :to-equal nil)
      (expect hook-events :to-equal nil)))

  (it "runs only tests whose source file matches the location filter"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "files" :parent root)))
           (target #P"/tmp/cl-weave/location-target.lisp")
           (other #P"/tmp/cl-weave/location-other.lisp")
           (events-log nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "target"
        :location (list :file (namestring target))
        :function (lambda () (push :target events-log))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "other"
        :location (list :file (namestring other))
        :function (lambda () (push :other events-log))))
      (let ((events (cl-weave::collect-events root :location-filter (list target))))
        (expect events-log :to-equal '(:target))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("files" "target"))))))

  (progn
  (it "normalizes, includes, and excludes test tags"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root (cl-weave::make-suite :name "tagged" :parent root))))
      (dolist (spec '(("fast unit" (:fast "UNIT" :FAST))
                      ("fast db" (:fast :db))
                      ("slow unit" (:slow :unit))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name (first spec)
          :tags (cl-weave::normalize-tags (second spec))
          :function (lambda () t))))
      (let ((events (cl-weave::collect-events
                     root :include-tags '(fast) :exclude-tags '("db"))))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("tagged" "fast unit"))))))

  (it "preserves tag filter semantics for order, duplicates, and empty filters"
    (let ((test (cl-weave::make-test-case
                 :name "tag semantics"
                 :function (lambda () t))))
      (dolist (test-tags '(nil
                           ("FAST")
                           ("UNIT" "FAST" "FAST")
                           ("DB" "FAST")))
        (setf (cl-weave::test-case-tags test) test-tags)
        (dolist (filters '((nil nil)
                           (("FAST" "FAST") nil)
                           (("MISSING" "FAST" "FAST") ("ABSENT"))
                           (("FAST" "MISSING") ("DB" "DB"))
                           (nil ("UNIT" "UNIT"))
                           (("MISSING") nil)
                           (("FAST") ("FAST"))))
          (destructuring-bind (include-tags exclude-tags) filters
            (let* ((expected
                     (and
                      (or (null include-tags)
                          (intersection
                           test-tags include-tags :test #'string=))
                      (or (null exclude-tags)
                          (not
                           (intersection
                            test-tags exclude-tags :test #'string=)))))
                   (actual
                     (cl-weave::test-tags-match-filter-p
                      test
                      (cl-weave::tag-membership-index include-tags)
                      (cl-weave::tag-membership-index exclude-tags))))
              (expect (not (null actual))
                      :to-equal (not (null expected))))))))))

  (it "combines tag, name, and location filters with AND semantics"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root (cl-weave::make-suite :name "combined" :parent root)))
           (target #P"/tmp/cl-weave/combined-target.lisp"))
      (dolist (name '("wanted" "other"))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name name :tags '("FAST")
          :location (list :file (namestring target))
          :function (lambda () t))))
      (let ((events (cl-weave::collect-events
                     root :include-tags '(:fast) :name-filter "wanted"
                     :location-filter (list target))))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("combined" "wanted"))))))

  (it "validates tag filters as proper lists of tag designators"
    (dolist (filter (list :fast '(42) (cons :fast :slow)))
      (expect (lambda ()
                (cl-weave::collect-events
                 (cl-weave::make-suite :name "root") :include-tags filter))
              :to-throw)))

  (progn
    (it "applies tag filters before assigning shard ordinals"
      (let* ((root (cl-weave::make-suite :name "root"))
             (suite (cl-weave::add-child
                     root
                     (cl-weave::make-suite :name "sharded" :parent root))))
        (dolist (spec (quote (("first" ("FAST"))
                              ("ignored" ("SLOW"))
                              ("second" ("FAST")))))
          (cl-weave::add-child
           suite
           (cl-weave::make-test-case
            :name (first spec)
            :tags (second spec)
            :function (lambda () t))))
        (let ((events (cl-weave::collect-events
                       root :include-tags (quote (:fast)) :shard (quote (2 2)))))
          (expect (mapcar (function cl-weave::test-event-path) events)
                  :to-equal (quote (("sharded" "second")))))))

    (it "indexes tag filters once and scans test tags linearly"
      (let* ((tag-count 5000)
             (filter-tags
               (loop for index below tag-count
                     collect (format nil "FILTER-~D" index)))
             (test-tags
               (loop for index below tag-count
                     collect (format nil "TEST-~D" index)))
             (root (cl-weave::make-suite :name "root"))
             (filter
               (cl-weave::make-selection-filter :include-tags filter-tags))
             (original-index-builder
               (symbol-function (quote cl-weave::tag-membership-index)))
             (original-index-member
               (symbol-function (quote cl-weave::tag-index-member-p)))
             (index-build-count 0)
             (membership-probe-count 0))
        (dotimes (index 3)
          (cl-weave::add-child
           root
           (cl-weave::make-test-case
            :name (format nil "test-~D" index)
            :tags test-tags
            :function (lambda () t))))
        (with-mocked-functions
            (((symbol-function (quote cl-weave::tag-membership-index))
              (lambda (tags)
                (when tags
                  (incf index-build-count))
                (funcall original-index-builder tags)))
             ((symbol-function (quote cl-weave::tag-index-member-p))
              (lambda (tag index)
                (incf membership-probe-count)
                (funcall original-index-member tag index))))
          (multiple-value-bind (selected-tests selected-suites test-paths)
              (cl-weave::collect-selection-indexes root filter nil)
            (declare (ignore selected-suites test-paths))
            (expect (hash-table-count selected-tests) :to-be 0)))
        (expect index-build-count :to-be 1)
        (expect membership-probe-count :to-be (* 3 tag-count)))))

  (it "can fail a run when no tests are selected"
    (let ((cl-weave::*root-suite* (cl-weave::make-suite :name "root"))
          (cl-weave::*current-suite* nil))
      (describe "selected"
        (it "visible"
          (expect t :to-be-truthy)))
      (expect (cl-weave:run-all
               :reporter :sexp
               :stream (make-string-output-stream)
               :name-filter "missing")
              :to-be t)
      (expect (cl-weave:run-all
               :reporter :sexp
               :stream (make-string-output-stream)
               :name-filter "missing"
               :pass-with-no-tests nil)
              :to-be nil))))
