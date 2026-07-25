(in-package #:cl-weave/tests)

(describe "property shrinking"
  (it "shrinks heterogeneous generator alternatives safely"
    (let ((generator (gen-one-of (gen-member '(:a :b))
                                 (gen-list (gen-member '(:x :y))
                                           :min-length 1
                                           :max-length 2))))
      (expect (funcall (cl-weave::property-generator-shrink generator) :b)
              :to-equal '(:a))
      (expect (funcall (cl-weave::property-generator-shrink generator) '(:x :y))
              :to-satisfy
              (lambda (candidates)
                (member '(:x) candidates :test #'equal)))))

  (it "shrinks integers toward zero without offering a more extreme bound"
    ;; Regression: the MIN bound must never be a shrink candidate. For a
    ;; negative range MIN is the most extreme value, so offering it let a
    ;; greedy shrink move to a larger magnitude than the input it started from.
    (let ((candidates (cl-weave::integer-shrink-candidates -3 -100 100)))
      (expect candidates :not :to-contain -100)
      (expect candidates
              :to-satisfy (lambda (cs) (every (lambda (c) (< (abs c) 3)) cs))))
    ;; When zero is out of range, shrink toward the nearest reachable bound.
    (expect (cl-weave::integer-shrink-candidates 80 10 100) :to-contain 10)
    (expect (cl-weave::integer-shrink-candidates -80 -100 -10) :to-contain -10))

  (it "shrinks strings and vectors safely"
    (let ((string-generator (gen-string :min-length 1 :max-length 4 :alphabet "ab"))
          (vector-generator (gen-vector (gen-member '(:a :b))
                                        :min-length 1
                                        :max-length 3)))
      (expect (funcall (cl-weave::property-generator-shrink string-generator)
                       "bb")
              :to-contain "ab")
      (expect (funcall (cl-weave::property-generator-shrink vector-generator)
                       #(:b :b))
              :to-contain-equal #(:a :b))
      (expect (cl-weave::remove-duplicate-shrink-candidates
               '((0 1) (1 0) (0 1)) #'equal)
              :to-equal '((1 0) (0 1)))))
(it "does not share list spines with shrink candidates"
    (let* ((generator (gen-list (gen-member '(:a :b))
                                :min-length 1
                                :max-length 3))
           (value (list :b :b :b))
           (candidates
             (funcall (cl-weave::property-generator-shrink generator) value))
           (candidate (find '(:b :a :b) candidates :test #'equal)))
      (expect candidate :to-satisfy #'identity)
      (setf (third candidate) :changed)
      (expect value :to-equal '(:b :b :b))))

  (it "shrinks state-machine traces by event stream"
    (let* ((transition (lambda (state event)
                         (ecase event
                           (:inc (1+ state))
                           (:dec (1- state)))))
           (generator (gen-state-machine
                       0 transition (gen-member '(:inc :dec))
                       :min-length 1
                       :max-length 3))
           (trace '(:initial 0 :events (:inc :inc) :states (0 1 2) :final 2))
           (candidates (funcall (cl-weave::property-generator-shrink generator)
                                trace))
           (single-event (find-if
                          (lambda (candidate)
                            (equal (getf candidate :events) '(:inc)))
                          candidates)))
      (expect single-event :to-satisfy #'identity)
      (expect (getf single-event :states) :to-equal '(0 1))
      (expect (getf single-event :final) :to-be 1)))

  (it "rejects invalid state-machine transitions"
    (expect (lambda ()
              (gen-state-machine 0 :not-a-function (gen-member '(:inc))))
            :to-throw "TRANSITION"))

  (it "reports generated and minimized values on failure"
    (handler-case
        (let ((cl-weave:*property-test-count* 20)
              (cl-weave:*property-seed* 1))
          (cl-weave::run-property
           (list (gen-integer :min 1 :max 5))
           (lambda (value)
             (expect value :to-be 0))
           '(value)
           '(property-failure-example)))
      (assertion-failure (condition)
        (let* ((detail (cl-weave::failure-detail condition))
               (actual (cl-weave::assertion-detail-actual detail)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :property)
          (expect actual :to-contain :seed)
          (expect actual :to-contain :case-index)
          (expect (getf actual :seed) :to-be 1)
          (expect (getf actual :case-index) :to-be 0)
          (expect actual :to-contain :values)
          (expect actual :to-contain :minimal)))))

  (it "does not treat warnings as property failures"
    (let ((cl-weave:*property-test-count* 3)
          (cl-weave:*property-seed* 17)
          (runs 0))
      (handler-bind ((warning (lambda (condition)
                                (declare (ignore condition))
                                (invoke-restart 'muffle-warning))))
        (expect (cl-weave::run-property
                 (list (gen-integer :min 5 :max 5))
                 (lambda (value)
                   (incf runs)
                   (warn "generated ~S" value))
                 '(value)
                 '(warning-property))
                :to-be t))
      (expect runs :to-be 3)))

  (it "matches property failures by condition type by default"
    (expect (same-property-failure-p
             (make-condition 'simple-error
                             :format-control "first"
                             :format-arguments nil)
             (make-condition 'simple-error
                             :format-control "second"
                             :format-arguments nil))
            :to-be t)
    (expect (same-property-failure-p
             (make-condition 'simple-error
                             :format-control "failure"
                             :format-arguments nil)
             (make-condition 'type-error :datum 1 :expected-type 'string))
            :to-be nil))

  (it "never classifies non-conditions as matching property failures"
    (dolist (pair '((:failure :failure)
                    (:failure nil)
                    (nil :failure)))
      (expect (same-property-failure-p (first pair) (second pair))
              :to-be nil)))

  (it "dispatches every shrink candidate to exactly one continuation"
    (labels ((dispatch (current visited candidate property)
               (let* ((original (make-condition 'simple-error
                                                :format-control "original"
                                                :format-arguments nil))
                      (state (cl-weave::make-property-shrink-state
                              :original original
                              :function property
                              :current current
                              :visited (let ((seen (make-hash-table :test #'equal)))
                                         (dolist (value (cons current visited) seen)
                                           (setf (gethash value seen) t)))
                              :steps 1
                              :max-steps 10))
                      (calls nil))
                 (expect (hash-table-p
                          (cl-weave::property-shrink-state-visited state))
                         :to-be t)
                 (cl-weave::call-property-shrink-candidate/k
                  state 0 candidate
                  (lambda (next-state)
                    (push (list :accept
                                (cl-weave::property-shrink-state-current
                                 next-state))
                          calls))
                  (lambda (rejected-state)
                    (expect rejected-state :to-be state)
                    (push (list :reject) calls)))
                 calls)))
      (dolist (case
               (list
                (list '((:accept (1))) '(2) nil 1
                      (lambda (value) (error "failure: ~S" value)))
                (list '((:reject)) '(2) nil 2
                      (lambda (value) (error "failure: ~S" value)))
                (list '((:reject)) '(2) '((1)) 1
                      (lambda (value) (error "failure: ~S" value)))
                (list '((:reject)) '(2) nil 1 #'identity)
                (list '((:reject)) '(2) nil 1
                      (lambda (value)
                        (declare (ignore value))
                        (error 'type-error :datum 1 :expected-type 'string)))))
        (destructuring-bind (expected current visited candidate property) case
          (expect (dispatch current visited candidate property)
                  :to-equal expected)))))

  (it "stops at the first accepted shrink candidate"
    (let ((generator
            (cl-weave::make-property-generator
             :name :ordered
             :produce #'identity
             :shrink (lambda (value)
                       (if (= value 2) '(1 0) nil)))))
      (expect (cl-weave::shrink-property-values
               (list generator)
               '(2)
               (lambda (value)
                 (error "failure: ~S" value)))
              :to-equal '(1))))

  (it "does not shrink a property failure into a different error type"
    (let ((cl-weave:*property-test-count* 1)
          (cl-weave:*property-seed* 23)
          (generator
            (cl-weave::make-property-generator
             :name :heterogeneous-failure
             :produce (lambda (rng)
                        (declare (ignore rng))
                        2)
             :shrink (lambda (value)
                       (if (= value 2) '(1 0) '())))))
      (handler-case
          (cl-weave::run-property
           (list generator)
           (lambda (value)
             (case value
               (1 (error "different failure"))
               (otherwise (expect value :to-be -1))))
           '(value)
           '(heterogeneous-property-failure))
        (assertion-failure (condition)
          (let* ((detail (cl-weave::failure-detail condition))
                 (actual (cl-weave::assertion-detail-actual detail)))
            (expect (getf actual :minimal) :to-equal '(0)))))))

  (it "stops shrinking when candidates form a cycle"
    (let ((generator
            (cl-weave::make-property-generator
             :name :cyclic
             :produce (lambda (rng)
                        (declare (ignore rng))
                        :a)
             :shrink (lambda (value)
                       (ecase value
                         (:a '(:b))
                         (:b '(:a)))))))
      (expect (cl-weave::shrink-property-values
               (list generator) '(:a)
               (lambda (value) (error "failure at ~S" value)))
              :to-equal '(:b))))

  (it "offers the current value when the shrink step limit is reached"
    (let ((cl-weave:*property-shrink-max-steps* 1)
          (generator
            (cl-weave::make-property-generator
             :name :unbounded
             :produce (lambda (rng) (declare (ignore rng)) 3)
             :shrink (lambda (value) (list (1- value)))))
          (limit nil))
      (handler-bind
          ((property-shrink-limit
             (lambda (condition)
               (setf limit condition)
               (invoke-restart 'accept-current))))
        (expect (cl-weave::shrink-property-values
                 (list generator) '(3)
                 (lambda (value) (error "failure at ~S" value)))
                :to-equal '(2)))
      (expect (property-shrink-limit-values limit) :to-equal '(2))
      (expect (property-shrink-limit-steps limit) :to-be 1)
      (expect (property-shrink-limit-max-steps limit) :to-be 1)))

  (it "spends the shrink budget on rejected candidates"
    (let ((cl-weave:*property-shrink-max-steps* 2)
          (evaluated nil)
          (limit nil)
          (generator
            (cl-weave::make-property-generator
             :name :rejected
             :produce (lambda (rng) (declare (ignore rng)) 3)
             :shrink (lambda (value)
                       (declare (ignore value))
                       '(2 1 0)))))
      (handler-bind
          ((property-shrink-limit
             (lambda (condition)
               (setf limit condition)
               (invoke-restart 'accept-current))))
        (expect (cl-weave::shrink-property-values
                 (list generator) '(3)
                 (lambda (value)
                   (push value evaluated)
                   (when (= value 3)
                     (error "original failure"))))
                :to-equal '(3)))
      (expect evaluated :to-equal '(1 2 3))
      (expect (property-shrink-limit-steps limit) :to-be 2)))

  (it "trampolines a full shrink budget without stack growth"
    (let ((cl-weave:*property-shrink-max-steps* 1000)
          (evaluations 0)
          (generator
            (cl-weave::make-property-generator
             :name :deep-shrink
             :produce (lambda (rng) (declare (ignore rng)) 1000)
             :shrink (lambda (value)
                       (when (plusp value)
                         (list (1- value)))))))
      (expect (cl-weave::shrink-property-values
               (list generator) '(1000)
               (lambda (value)
                 (incf evaluations)
                 (error "failure at ~S" value)))
              :to-equal '(0))
      (expect evaluations :to-be 1001)))

  (it "stops circular cons shrink candidates"
    (let* ((first (cons :cycle nil))
           (duplicate (cons :cycle nil))
           (generator
             (cl-weave::make-property-generator
              :name :circular-cons
              :produce #'identity
              :shrink (lambda (value)
                        (cond
                          ((eq value :start) (list first))
                          ((eq value first) (list duplicate))
                          ((eq value duplicate) (list first))
                          (t nil))))))
      (setf (cdr first) first
            (cdr duplicate) duplicate)
      (labels ((exercise ()
                 (let ((minimal
                         (cl-weave::shrink-property-values
                          (list generator) '(:start)
                          (lambda (value)
                            (declare (ignore value))
                            (error "failure")))))
                   (expect (first minimal) :to-be first))))
        #+sbcl (sb-ext:with-timeout 2 (exercise))
        #-sbcl (exercise))))

  (it "stops circular vector shrink candidates"
    (let* ((first (vector nil))
           (second (vector nil))
           (generator
             (cl-weave::make-property-generator
              :name :circular-vector
              :produce #'identity
              :shrink (lambda (value)
                        (cond
                          ((eq value :start) (list first))
                          ((eq value first) (list second))
                          ((eq value second) (list first))
                          (t nil))))))
      (setf (aref first 0) first
            (aref second 0) second)
      (labels ((exercise ()
                 (let ((minimal
                         (cl-weave::shrink-property-values
                          (list generator) '(:start)
                          (lambda (value)
                            (declare (ignore value))
                            (error "failure")))))
                   (expect (first minimal) :to-be second))))
        #+sbcl (sb-ext:with-timeout 2 (exercise))
        #-sbcl (exercise))))

  (it "prints circular property failures safely"
    (labels ((exercise ()
               (let* ((cycle (cons :cycle nil))
                      (generator
                        (cl-weave::make-property-generator
                         :name :circular-report
                         :produce #'identity
                         :shrink (constantly nil))))
                 (setf (cdr cycle) cycle)
                 (let* ((cause
                          (make-condition
                           'simple-error
                           :format-control "failure at ~S"
                           :format-arguments (list cycle)))
                        (limit-text
                          (princ-to-string
                           (make-condition
                            'property-shrink-limit
                            :values (list cycle)
                            :steps 1
                            :max-steps 1)))
                        (shrinker-text
                          (princ-to-string
                           (make-condition
                            'property-shrinker-error
                            :generator generator
                            :value cycle
                            :cause cause)))
                        (failure nil))
                   (handler-case
                       (cl-weave::signal-property-failure
                        '(value) '(property value) (list cycle) (list cycle)
                        7 0 cause)
                     (assertion-failure (condition)
                       (setf failure condition)))
                   (expect limit-text :to-satisfy
                           (lambda (text) (search "#1=" text)))
                   (expect shrinker-text :to-satisfy
                           (lambda (text) (search "#1=" text)))
                   (expect failure :to-satisfy #'identity)
                   (let* ((detail (cl-weave::failure-detail failure))
                          (actual (cl-weave::assertion-detail-actual detail))
                          (condition-text (getf actual :condition)))
                     (expect condition-text :to-satisfy
                             (lambda (text) (search "#1=" text))))))))
      #+sbcl (sb-ext:with-timeout 2 (exercise))
      #-sbcl (exercise))
    (expect
     (princ-to-string
      (make-condition 'property-shrink-limit
                      :values '(2)
                      :steps 1
                      :max-steps 1))
     :to-equal "Property shrinking exceeded the 1 step limit at (2)."))

)
