(in-package #:cl-weave/tests)

(describe "property generators and shrinker contracts"
  (it "validates integer generator bounds"
    (expect (lambda () (gen-integer :min 0.5)) :to-throw 'type-error)
    (expect (lambda () (gen-integer :max "10")) :to-throw 'type-error)
    (expect (lambda () (gen-integer :min 2 :max 1))
            :to-throw "MIN <= MAX"))

  (it "rejects invalid generator compositions at construction time"
    (expect-property-constructor-errors
     (list
      (list (lambda () (gen-character :alphabet "")) "non-empty sequence")
      (list (lambda () (gen-member nil)) "at least one value")
      (list (lambda () (gen-map :not-a-function (gen-boolean))) "FUNCTION")
      (list (lambda () (gen-map #'identity :not-a-generator)) "property generator")
      (list (lambda () (gen-list :not-a-generator)) "property generator")
      (list (lambda () (gen-list (gen-boolean) :min-length 2 :max-length 1))
            "MIN-LENGTH <= MAX-LENGTH")
      (list (lambda () (gen-list (gen-boolean) :min-length -1 :max-length 3))
            "non-negative MIN-LENGTH")
      (list (lambda () (gen-string :min-length 2 :max-length 1))
            "MIN-LENGTH <= MAX-LENGTH")
      (list (lambda () (gen-string :min-length -1 :max-length 3))
            "non-negative MIN-LENGTH")
      (list (lambda () (gen-vector :not-a-generator)) "property generator")
      (list (lambda () (gen-vector (gen-boolean) :min-length 2 :max-length 1))
            "MIN-LENGTH <= MAX-LENGTH")
      (list (lambda () (gen-one-of)) "at least one property generator")
      (list (lambda () (gen-tuple (gen-boolean) :not-a-generator))
            "property generator")
      (list (lambda () (gen-such-that :not-a-function (gen-boolean)))
            "PREDICATE")
      (list (lambda () (gen-such-that #'identity (gen-boolean) :attempts 0))
            "positive integer ATTEMPTS")
      (list (lambda () (gen-such-that #'identity :not-a-generator))
            "property generator")
      (list (lambda () (gen-recursive (gen-boolean) :not-a-function))
            "BUILDER")
      (list (lambda () (gen-recursive (gen-boolean) #'identity :max-depth -1))
            "non-negative integer MAX-DEPTH"))))

  (it "keeps integer production and shrinking within bounds"
    (let* ((singleton (gen-integer :min 5 :max 5))
           (positive (gen-integer :min 2 :max 10))
           (negative (gen-integer :min -10 :max -2))
           (rng (cl-weave::make-property-rng :state 1)))
      (expect (funcall (cl-weave::property-generator-produce singleton) rng)
              :to-be 5)
      (expect (funcall (cl-weave::property-generator-shrink positive) 8)
              :to-equal '(2 4))
      ;; Shrinking moves toward zero: the least-extreme in-range value (-2) and
      ;; the halved value (-4), never the far MIN bound (-10, more extreme
      ;; than the -8 input).
      (expect (funcall (cl-weave::property-generator-shrink negative) -8)
              :to-equal '(-2 -4))))

  (it "shrinks heterogeneous one-of values through matching built-in domains"
    (let ((generator (gen-one-of (gen-character :alphabet "ab")
                                 (gen-integer :min 0 :max 10))))
      (expect (cl-weave::property-shrink-candidates generator 5)
              :to-equal (list 0 2))
      (expect (cl-weave::property-shrink-candidates generator #\b)
              :to-equal (list #\a))))

  (it "guards structured shrinkers from foreign one-of values"
    (let ((state-machine
            (gen-one-of
             (gen-state-machine 0
                                (lambda (state event)
                                  (declare (ignore event))
                                  (1+ state))
                                (gen-member (list :inc)))
             (gen-member (list :foreign :other))))
          (tuple
            (gen-one-of
             (gen-tuple (gen-integer :min 0 :max 10) (gen-boolean))
             (gen-integer :min 0 :max 10))))
      (expect (cl-weave::property-shrink-candidates state-machine :other)
              :to-equal (list :foreign))
      (expect (cl-weave::property-shrink-candidates tuple 8)
              :to-equal (list 0 4))))

  (it "does not hide genuine shrinker failures in one-of"
    (let* ((cause (make-condition 'simple-error :format-control "broken"))
           (broken
             (cl-weave::make-property-generator
              :name :broken
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        (error cause))))
           (generator (gen-one-of (gen-character :alphabet "ab") broken)))
      (expect (lambda ()
                (cl-weave::property-shrink-candidates generator #\b))
              :to-throw 'property-shrinker-error)))

  (it "deduplicates recursive shrink candidates by last occurrence"
    (let* ((base
             (cl-weave::make-property-generator
              :name :base
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        '((:shared) (:base) (:shared)))))
           (step
             (cl-weave::make-property-generator
              :name :step
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        '((:step) (:shared)))))
           (generator
             (gen-recursive base
                            (lambda (self)
                              (declare (ignore self))
                              step))))
      (expect (cl-weave::property-shrink-candidates generator :value)
              :to-equal '((:base) (:step) (:shared)))))

  (it "exposes shrinker failures with recovery restarts"
    (let* ((attempts 0)
           (cause (make-condition 'simple-error :format-control "broken"))
           (generator
             (cl-weave::make-property-generator
              :name :broken
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        (incf attempts)
                        (if (= attempts 1)
                            (error cause)
                            '(:recovered))))))
      (handler-bind
          ((property-shrinker-error
             (lambda (condition)
               (expect (property-shrinker-error-generator condition)
                       :to-be generator)
               (expect (property-shrinker-error-value condition) :to-be :value)
               (expect (property-shrinker-error-cause condition) :to-be cause)
               (let ((restart (find-restart 'retry-shrinker condition)))
                 (expect restart :not :to-be nil)
                 (invoke-restart restart)))))
        (expect (cl-weave::property-shrink-candidates generator :value)
                :to-equal '(:recovered)))
      (handler-bind
          ((property-shrinker-error
             (lambda (condition)
               (let ((restart (find-restart 'use-value condition)))
                 (expect restart :not :to-be nil)
                 (invoke-restart restart '(:replacement))))))
        (setf attempts 0)
        (expect (cl-weave::property-shrink-candidates generator :value)
                :to-equal '(:replacement)))
      (handler-bind
          ((property-shrinker-error
             (lambda (condition)
               (let ((restart (find-restart 'skip-shrinking condition)))
                 (expect restart :not :to-be nil)
                 (invoke-restart restart)))))
        (setf attempts 0)
        (expect (cl-weave::property-shrink-candidates generator :value)
                :to-be nil))
      (setf attempts 0)
      (handler-case
          (progn
            (cl-weave::property-shrink-candidates generator :value)
            (error "Expected the shrinker error to be signaled."))
        (property-shrinker-error (condition)
          (expect (property-shrinker-error-cause condition) :to-be cause)))))

  (it "deduplicates circular candidates without looping"
    (let* ((cycle-a (cons :cycle nil))
           (cycle-b (cons :cycle nil))
           (cycle-last (cons :cycle nil))
           (shared-tail (list :tail))
           (shared-a (cons :shared shared-tail))
           (shared-b (cons :shared shared-tail))
           (source
             (cl-weave::make-property-generator
              :name :circular-candidates
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        (list cycle-a shared-a cycle-b shared-b cycle-last))))
           (idle
             (cl-weave::make-property-generator
              :name :idle
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        nil)))
           (one-of (gen-one-of source))
           (tuple (gen-tuple source idle)))
      (setf (cdr cycle-a) cycle-a
            (cdr cycle-b) cycle-b
            (cdr cycle-last) cycle-last)
      (flet ((exercise ()
               (let ((direct
                       (cl-weave::remove-duplicate-shrink-candidates
                        (list cycle-a shared-a cycle-b shared-b cycle-last)
                        #'equal))
                     (one-of-candidates
                       (cl-weave::property-shrink-candidates one-of :value))
                     (tuple-candidates
                       (cl-weave::property-shrink-candidates
                        tuple
                        (list :left :right))))
                 (expect (length direct) :to-be 2)
                 (expect (first direct) :to-be shared-b)
                 (expect (second direct) :to-be cycle-last)
                 (expect (length one-of-candidates) :to-be 2)
                 (expect (first one-of-candidates) :to-be shared-b)
                 (expect (second one-of-candidates) :to-be cycle-last)
                 (expect (length tuple-candidates) :to-be 2)
                 (expect (first (first tuple-candidates)) :to-be shared-b)
                 (expect (second (first tuple-candidates)) :to-be :right)
                 (expect (first (second tuple-candidates)) :to-be cycle-last)
                 (expect (second (second tuple-candidates)) :to-be :right))))
        #+sbcl
        (sb-ext:with-timeout 2
          (exercise))
        #-sbcl
        (exercise))))

  (it "rejects non-list and improper shrink candidates without traversing cycles"
    (dolist (candidates
             (list #(:vector)
                   (cons :head :tail)
                   (let ((cycle (list :cycle)))
                     (setf (cdr cycle) cycle)
                     cycle)))
      (let* ((generator
               (cl-weave::make-property-generator
                :name :invalid-candidates
                :produce #'identity
                :shrink (lambda (value)
                          (declare (ignore value))
                          candidates)))
             (cause nil))
        (handler-bind
            ((property-shrinker-error
               (lambda (condition)
                 (setf cause (property-shrinker-error-cause condition))
                 (expect (find-restart 'retry-shrinker condition)
                         :not :to-be nil)
                 (expect (find-restart 'use-value condition)
                         :not :to-be nil)
                 (expect (find-restart 'skip-shrinking condition)
                         :not :to-be nil)
                 (invoke-restart (find-restart 'skip-shrinking condition)))))
          (expect (cl-weave::property-shrink-candidates generator :value)
                  :to-be nil))
        (expect cause :to-satisfy (lambda (condition)
                                    (typep condition 'error))))))

  (it "validates replacement shrink candidates under the same restarts"
    (let ((generator
            (cl-weave::make-property-generator
             :name :replacement
             :produce #'identity
             :shrink (lambda (value)
                       (declare (ignore value))
                       (error "initial failure"))))
          (signals 0))
      (handler-bind
          ((property-shrinker-error
             (lambda (condition)
               (incf signals)
               (let ((restart (find-restart 'use-value condition)))
                 (expect restart :not :to-be nil)
                 (invoke-restart restart
                                 (if (= signals 1)
                                     #(:invalid)
                                     '(:valid)))))))
        (expect (cl-weave::property-shrink-candidates generator :value)
                :to-equal '(:valid)))
      (expect signals :to-be 2)))

  (it "recognizes only finite proper shrink candidate lists"
    (dolist (value (list nil '(:one) '(:one :two)))
      (expect (cl-weave::finite-proper-list-p value) :to-be t))
    (dolist (value (list :atom (cons :head :tail)))
      (expect (cl-weave::finite-proper-list-p value) :to-be nil))
    (let ((cycle (list :cycle)))
      (setf (cdr cycle) cycle)
      (expect (cl-weave::finite-proper-list-p cycle) :to-be nil)))

  (it "prints actionable shrinker failure diagnostics"
    (let* ((generator
             (cl-weave::make-property-generator
              :name :diagnostic-generator
              :produce #'identity
              :shrink #'identity))
           (condition
             (make-condition 'property-shrinker-error
                             :generator generator
                             :value '(:input 7)
                             :cause (make-condition
                                     'simple-error
                                     :format-control "invalid candidate")))
           (message (princ-to-string condition)))
      (dolist (fragment '("DIAGNOSTIC-GENERATOR"
                          "(:INPUT 7)"
                          "invalid candidate"))
        (expect message :to-contain fragment))))

  (it-property "checks integer addition commutativity"
      ((left (gen-integer :min -20 :max 20))
       (right (gen-integer :min -20 :max 20)))
    (expect (+ left right) :to-be (+ right left)))

  (it-property "checks list reversal involution"
      ((values (gen-list (gen-member '(:a :b :c)) :max-length 6)))
    (expect (reverse (reverse values)) :to-equal values))

  (it-property "checks boolean identity"
      ((flag (gen-boolean)))
    (expect (not (not flag)) :to-be flag))

  (it-property "composes tuple generators"
      ((pair (gen-tuple (gen-integer :min 0 :max 10)
                        (gen-member '(:ok :retry)))))
    (destructuring-bind (count state) pair
      (expect count :to-satisfy (lambda (value) (<= 0 value 10)))
      (expect '(:ok :retry) :to-contain state)))

  (it-property "filters generated values"
      ((even (gen-such-that #'evenp (gen-integer :min 0 :max 20))))
    (expect even :to-satisfy #'evenp))

  (it-property "chooses among generator alternatives"
      ((value (gen-one-of (gen-member '(:left :right))
                          (gen-member '(:up :down)))))
    (expect '(:left :right :up :down) :to-contain value))

  (it-property "generates bounded recursive s-expressions"
      ((form (gen-recursive
              (gen-member '(:x :y 0 1))
              (lambda (self)
                (gen-one-of
                 (gen-list self :min-length 1 :max-length 3)
                 (gen-tuple (gen-member '(quote if progn)) self)))
              :max-depth 3)))
    (expect (tree-depth form) :to-be-less-than-or-equal 4)
    (expect form :to-satisfy (lambda (value) (or (atom value) (consp value)))))

  (it-property "maps generated values"
      ((value (gen-map #'1+ (gen-integer :min 0 :max 5))))
    (expect value :to-satisfy (lambda (number) (<= 1 number 6))))

  (it-property "generates symbols and keywords"
      ((symbol (gen-symbol :names '("ALPHA" "BETA") :package "CL-USER"))
       (keyword (gen-keyword '("LEFT" "RIGHT"))))
    (expect symbol :to-satisfy #'symbolp)
    (expect (symbol-package symbol) :to-be (find-package "CL-USER"))
    (expect keyword :to-satisfy #'keywordp))

  (it-property "generates characters from an alphabet"
      ((character (gen-character :alphabet "abc")))
    (expect character :to-satisfy #'characterp)
    (expect "abc" :to-contain (string character)))

  (it-property "generates bounded strings"
      ((value (gen-string :min-length 2 :max-length 5 :alphabet "ab")))
    (expect value :to-satisfy #'stringp)
    (expect value :to-satisfy
            (lambda (string)
              (<= 2 (length string) 5)))
    (expect value :to-satisfy
            (lambda (string)
              (every (lambda (character)
                       (find character "ab" :test #'char=))
                     string))))

  (it-property "generates bounded vectors"
      ((value (gen-vector (gen-member '(:left :right))
                          :min-length 1
                          :max-length 4)))
    (expect value :to-satisfy #'vectorp)
    (expect value :to-satisfy
            (lambda (vector)
              (<= 1 (length vector) 4)))
    (expect value :to-satisfy
            (lambda (vector)
              (every (lambda (entry)
                       (member entry '(:left :right)))
                     vector))))

  (it-property "generates replayable state-machine traces"
      ((trace (gen-state-machine
               0
               (lambda (state event)
                 (ecase event
                   (:inc (1+ state))
                   (:dec (1- state))
                   (:reset 0)))
               (gen-member '(:inc :dec :reset))
               :min-length 1
               :max-length 5)))
    (let ((events (getf trace :events))
          (states (getf trace :states)))
      (expect (getf trace :initial) :to-be 0)
      (expect events :to-satisfy
              (lambda (value)
                (<= 1 (length value) 5)))
      (expect states :to-satisfy
              (lambda (value)
                (= (length value) (1+ (length events)))))
      (expect (first states) :to-be 0)
      (expect (getf trace :final) :to-be (first (last states)))))

  (it-property "generates bounded s-expression trees"
      ((form (gen-sexp :max-depth 3 :max-list-length 3)))
    (expect (tree-depth form) :to-be-less-than-or-equal 4)
    (expect form :to-satisfy (lambda (value) (or (atom value) (consp value)))))

  (it-property "generates operator-headed forms"
      ((form (gen-form :operators '(progn list)
                       :max-depth 2
                       :max-arguments 2)))
    (expect form :to-satisfy
            (lambda (value)
              (or (atom value)
                  (and (consp value)
                       (member (first value) '(progn list)))))))

  (it "short-circuits element shrinking for oversized sequences"
    (let* ((shrink-calls 0)
           (element-generator
             (cl-weave::make-property-generator
              :name :counted-element
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        (incf shrink-calls)
                        nil)))
           (generator (gen-vector element-generator :max-length 16))
           (bounded-candidates
             (cl-weave::property-shrink-candidates
              generator
              (make-array 8 :initial-element :value))))
      (expect shrink-calls :to-be 8)
      (expect (length bounded-candidates) :to-be 2)
      (expect (length (first bounded-candidates)) :to-be 0)
      (expect (length (second bounded-candidates)) :to-be 4)
      (setf shrink-calls 0)
      (let ((oversized (make-array 2000000 :initial-element :value)))
        #+sbcl
        (sb-ext:gc :full t)
        (let* ((before
                 #+sbcl (sb-ext:get-bytes-consed)
                 #-sbcl 0)
               (oversized-candidates
                 (cl-weave::property-shrink-candidates generator oversized))
               (allocated
                 #+sbcl (- (sb-ext:get-bytes-consed) before)
                 #-sbcl 0))
          (expect shrink-calls :to-be 0)
          (expect oversized-candidates :to-equal nil)
          #+sbcl
          (expect (< allocated (* 1024 1024)) :to-be t)))))

  (it "validates malformed and failing child shrinkers through composites"
    (let ((cycle (list :cycle))
          (cause (make-condition 'simple-error :format-control "child failed")))
      (setf (cdr cycle) cycle)
      (labels ((make-child (name shrink)
                 (cl-weave::make-property-generator
                  :name name
                  :produce #'identity
                  :shrink shrink))
               (assert-child-error (child composite value expected-cause)
                 (let ((observed nil))
                   (handler-bind
                       ((property-shrinker-error
                          (lambda (condition)
                            (setf observed condition)
                            (expect (find-restart 'retry-shrinker condition)
                                    :not :to-be nil)
                            (expect (find-restart 'use-value condition)
                                    :not :to-be nil)
                            (expect (find-restart 'skip-shrinking condition)
                                    :not :to-be nil)
                            (invoke-restart 'skip-shrinking))))
                     (cl-weave::property-shrink-candidates composite value))
                   (expect observed :not :to-be nil)
                   (expect (property-shrinker-error-generator observed)
                           :to-be
                           child)
                   (if expected-cause
                       (expect (property-shrinker-error-cause observed)
                               :to-be
                               expected-cause)
                       (expect (property-shrinker-error-cause observed)
                               :to-satisfy
                               (lambda (condition) (typep condition 'error)))))))
        (let* ((vector-child
                 (make-child :vector-child
                             (lambda (value)
                               (declare (ignore value))
                               #(:invalid))))
               (dotted-child
                 (make-child :dotted-child
                             (lambda (value)
                               (declare (ignore value))
                               (cons :invalid :tail))))
               (circular-child
                 (make-child :circular-child
                             (lambda (value)
                               (declare (ignore value))
                               cycle)))
               (failing-child
                 (make-child :failing-child
                             (lambda (value)
                               (declare (ignore value))
                               (error cause)))))
          (assert-child-error
           vector-child
           (gen-list vector-child :min-length 1 :max-length 4)
           '(:value)
           nil)
          (assert-child-error
           dotted-child
           (gen-vector dotted-child :min-length 1 :max-length 4)
           #(:value)
           nil)
          (assert-child-error
           circular-child
           (gen-tuple circular-child)
           '(:value)
           nil)
          (assert-child-error
           failing-child
           (gen-such-that (constantly t) failing-child)
           :value
           cause)))))


)

