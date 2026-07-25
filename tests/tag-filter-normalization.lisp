(in-package #:cl-weave/tests)

(progn
  (describe "tag filter normalization"
  (it "accepts maximum include and exclude tags in canonical first order"
    (let* ((limit cl-weave::+maximum-tag-count+)
           (include-tags (make-list limit :initial-element :fast))
           (exclude-tags (make-list limit :initial-element :database))
           (root (cl-weave::make-suite :name "root"))
           (root-calls 0)
           (captured-options nil))
      (setf (first include-tags) :fast
            (second include-tags) "slow"
            (third include-tags) 'fast
            (fourth include-tags) :other
            (first exclude-tags) "database"
            (second exclude-tags) :cache
            (third exclude-tags) "DATABASE")
      (with-mocked-functions
          (((symbol-function 'cl-weave:root-suite)
            (lambda ()
              (incf root-calls)
              root))
           ((symbol-function 'cl-weave::collect-events-with-options)
            (lambda (suite options)
              (declare (ignore suite))
              (setf captured-options options)
              nil)))
        #+sbcl
        (sb-ext:with-timeout 10
          (expect
           (cl-weave:run-all
            :reporter :sexp
            :stream (make-broadcast-stream)
            :include-tags include-tags
            :exclude-tags exclude-tags)
           :to-be-truthy))
        #-sbcl
        (expect
         (cl-weave:run-all
          :reporter :sexp
          :stream (make-broadcast-stream)
          :include-tags include-tags
          :exclude-tags exclude-tags)
         :to-be-truthy))
      (expect root-calls :to-be 1)
      (expect captured-options :to-be-truthy)
      (expect (cl-weave::collection-options-include-tags captured-options)
              :to-equal '("FAST" "SLOW" "OTHER"))
      (expect (cl-weave::collection-options-exclude-tags captured-options)
              :to-equal '("DATABASE" "CACHE")))))
  (describe "normalization NIL fast paths"
  (it "preserves empty registration and collection defaults"
    (let* ((initargs
             (cl-weave::test-registration-initargs
              "empty" #'identity nil nil nil nil nil nil nil nil nil nil))
           (options (cl-weave::normalize-collection-options)))
      (expect (cl-weave::normalize-tags nil) :to-be nil)
      (expect (getf initargs :execution-mode) :to-be nil)
      (expect (getf initargs :tags) :to-be nil)
      (expect (getf initargs :watch-dependencies) :to-be nil)
      (expect (cl-weave::collection-options-name-filter options) :to-be nil)
      (expect (cl-weave::collection-options-location-filter options) :to-be nil)
      (expect (cl-weave::collection-options-test-path-filter options) :to-be nil)
      (expect (cl-weave::collection-options-include-tags options) :to-be nil)
      (expect (cl-weave::collection-options-exclude-tags options) :to-be nil)
      (expect (cl-weave::collection-options-bail options) :to-be nil)
      (expect (cl-weave::collection-options-shard options) :to-be nil)
      (expect (cl-weave::collection-options-order options) :to-be :defined)
      (expect (cl-weave::collection-options-seed options) :to-be 0)
      (expect (cl-weave::collection-options-retry options) :to-be 0)
      (expect (cl-weave::collection-options-timeout-ms options) :to-be nil)
      (expect (cl-weave::collection-options-max-workers options) :to-be nil)))

  (it "preserves non-empty tag canonicalization and option normalization"
    (let ((options
            (cl-weave::normalize-collection-options
             :include-tags '(:fast "FAST" :slow)
             :exclude-tags '(:database "DATABASE" :cache)
             :bail t
             :order :random
             :seed 17
             :retry 2
             :timeout-ms 50
             :max-workers 3)))
      (expect (cl-weave::normalize-tags '(:fast "FAST" :slow))
              :to-equal '("FAST" "SLOW"))
      (expect (cl-weave::collection-options-include-tags options)
              :to-equal '("FAST" "SLOW"))
      (expect (cl-weave::collection-options-exclude-tags options)
              :to-equal '("DATABASE" "CACHE"))
      (expect (cl-weave::collection-options-bail options) :to-be-truthy)
      (expect (cl-weave::collection-options-order options) :to-be :random)
      (expect (cl-weave::collection-options-seed options) :to-be 17)
      (expect (cl-weave::collection-options-retry options) :to-be 2)
      (expect (cl-weave::collection-options-timeout-ms options) :to-be 50)
      (expect (cl-weave::collection-options-max-workers options) :to-be 3)))

  (it "keeps improper and circular tag validation on non-NIL input"
    (let ((circular (list :fast))
          (dotted (cons :fast :slow)))
      (setf (cdr circular) circular)
      (flet ((check-malformed-inputs ()
               (expect (lambda () (cl-weave::normalize-tags dotted))
                       :to-throw "finite proper list")
               (expect (lambda () (cl-weave::normalize-tags circular))
                       :to-throw "finite proper list")))
        #+sbcl
        (sb-ext:with-timeout 10
          (check-malformed-inputs))
        #-sbcl
        (check-malformed-inputs))))))
