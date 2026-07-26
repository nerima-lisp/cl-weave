(in-package #:cl-weave/test)

(describe "sequence"
  (it "runs and lists tests in deterministic seeded order"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "sequence" :parent root))))
      (dolist (name '("alpha" "beta" "gamma" "delta"))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name name
          :function (lambda () t))))
      (let ((events (cl-weave::collect-events root :order :random :seed 7))
            (plan (cl-weave:collect-test-plan root :order :random :seed 7)))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("sequence" "gamma")
                            ("sequence" "beta")
                            ("sequence" "delta")
                            ("sequence" "alpha")))
        (expect (mapcar #'cl-weave:test-plan-entry-path plan)
                :to-equal (mapcar #'cl-weave::test-event-path events)))))

  (it "preserves child order when randomized hashes collide"
    (let* ((suite (cl-weave::make-suite :name "sequence-collision"))
           (first (cl-weave::make-test-case :name "duplicate"
                                            :function (lambda () t)))
           (second (cl-weave::make-test-case :name "duplicate"
                                             :function (lambda () t)))
           (children (list first second)))
      (let ((cl-weave:*test-sequence-order* :random)
            (cl-weave:*test-sequence-seed* 17))
        (expect (every #'eq
                       (cl-weave::ordered-children suite children)
                       children)
                :to-be t))))

  (it "applies sharding before seeded ordering"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "sequence-shard" :parent root))))
      (dolist (name '("one" "two" "three" "four"))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name name
          :function (lambda () t))))
      (let* ((events (cl-weave::collect-events
                      root
                      :shard '(1 2)
                      :order :random
                      :seed 11))
             (names (mapcar (lambda (path) (second path))
                            (mapcar #'cl-weave::test-event-path events))))
        (expect (sort (copy-list names) #'string<)
                :to-equal '("one" "three")))))

  (it "rejects invalid sequence controls with stable errors"
    (let ((root (cl-weave::make-suite :name "root")))
      (expect (lambda ()
                (cl-weave::collect-events root :order :reverse))
              :to-throw
              "Sequence order must")
      (expect (lambda ()
                (cl-weave:collect-test-plan root :seed "123"))
              :to-throw
              "Sequence seed must")))

  (progn
  (it "preserves child order when seeded hashes collide"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::make-suite :name "collision" :parent root))
           (first (cl-weave::make-test-case :name "case229599"
                                             :function (lambda () t)))
           (second (cl-weave::make-test-case :name "case432382"
                                              :function (lambda () t))))
      (let ((cl-weave:*test-sequence-order* :random)
            (cl-weave:*test-sequence-seed* 23))
        (expect (mapcar (function cl-weave::test-case-name)
                        (cl-weave::ordered-children
                         suite
                         (list first second)))
                :to-equal (list "case229599" "case432382")))))

  (it "matches label hashing without mutating the input children"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::make-suite :name "mixed" :parent root))
           (child-suite (cl-weave::make-suite
                         :name "child-suite"
                         :parent suite))
           (string-test (cl-weave::make-test-case
                         :name "string-test"
                         :function (lambda () t)))
           (symbol-test (cl-weave::make-test-case
                         :name (quote symbol-test)
                         :function (lambda () t)))
           (unknown-child (list :unknown-child))
           (children (list string-test
                           unknown-child
                           child-suite
                           symbol-test))
           (snapshot (copy-list children))
           (prefix (cl-weave::sequence-suite-prefix suite)))
      (dolist (seed (list 0 7 23 104729))
        (let* ((cl-weave:*test-sequence-order* :random)
               (cl-weave:*test-sequence-seed* seed)
               (expected
                 (mapcar
                  (function cdr)
                  (stable-sort
                   (mapcar
                    (lambda (child)
                      (cons
                       (cl-weave::stable-string-hash
                        (cl-weave::sequence-child-label
                         suite child prefix)
                        seed)
                       child))
                    children)
                   (function <)
                   :key (function car))))
               (actual (cl-weave::ordered-children suite children)))
          (expect (every (function eq) actual expected) :to-be t)
          (expect (every (function eq) children snapshot) :to-be t))))))
)

(describe "sequence public controls"
  (it "provides deterministic defaults"
    (expect cl-weave:*test-sequence-order* :to-be :defined)
    (expect cl-weave:*test-sequence-seed* :to-be 0))

  (it "supports dynamic sequence control bindings"
    (let ((cl-weave:*test-sequence-order* :random)
          (cl-weave:*test-sequence-seed* 29))
      (expect cl-weave:*test-sequence-order* :to-be :random)
      (expect cl-weave:*test-sequence-seed* :to-be 29))))
