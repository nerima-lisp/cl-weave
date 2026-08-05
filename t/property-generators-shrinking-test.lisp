(in-package #:cl-weave/test)

(defstruct equalp-shrink-candidate value)

(defstruct (recursive-equalp-shrink-candidate
               (:include equalp-shrink-candidate))
    next
    alternate)

(describe "cycle-safe shrink candidate deduplication"
  (it "preserves the last equal cons self-cycle"
    (let ((first (cons :cycle nil))
          (middle (cons :cycle nil))
          (last (cons :cycle nil)))
      (setf (cdr first) first
            (cdr middle) middle
            (cdr last) last)
      (flet ((exercise ()
               (let ((candidates
                       (cl-weave::remove-duplicate-shrink-candidates
                        (list first middle last)
                        #'equal)))
                 (expect (length candidates) :to-be 1)
                 (expect (first candidates) :to-be last))))
        #+sbcl
        (sb-ext:with-timeout 2
          (exercise))
        #-sbcl
        (exercise))))

  (it "preserves the last equalp vector self-cycle"
    (let ((first (make-array 1))
          (middle (make-array 1))
          (last (make-array 1)))
      (setf (aref first 0) first
            (aref middle 0) middle
            (aref last 0) last)
      (flet ((exercise ()
               (let ((candidates
                       (cl-weave::remove-duplicate-shrink-candidates
                        (list first middle last)
                        #'equalp)))
                 (expect (length candidates) :to-be 1)
                 (expect (first candidates) :to-be last))))
        #+sbcl
        (sb-ext:with-timeout 2
          (exercise))
        #-sbcl
        (exercise))))

  (it "does not mistake shared DAGs for cycles" (let* ((shared-leaf (list :leaf)) (shared-list (list shared-leaf shared-leaf)) (copied-list (list (list :leaf) (list :leaf))) (vector-leaf (list :leaf)) (shared-vector (vector vector-leaf vector-leaf)) (copied-vector (vector (list :leaf) (list :leaf)))) (expect (cl-weave::candidate-requires-safe-equality-p shared-list (function equal)) :to-be nil) (expect (cl-weave::candidate-requires-safe-equality-p copied-list (function equal)) :to-be nil) (expect (cl-weave::candidate-requires-safe-equality-p shared-vector (function equalp)) :to-be nil) (expect (cl-weave::candidate-requires-safe-equality-p copied-vector (function equalp)) :to-be nil) (let ((list-result (cl-weave::remove-duplicate-shrink-candidates (list shared-list copied-list) (function equal))) (vector-result (cl-weave::remove-duplicate-shrink-candidates (list shared-vector copied-vector) (function equalp)))) (expect (length list-result) :to-be 1) (expect (first list-result) :to-be copied-list) (expect (length vector-result) :to-be 1) (expect (first vector-result) :to-be copied-vector))))

  (it "keeps equalp structure semantics in vector shrinking"
    (let* ((first (make-equalp-shrink-candidate :value 7))
           (last (make-equalp-shrink-candidate :value 7))
           (element-generator
             (cl-weave::make-property-generator
              :name :equalp-structure-candidates
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        (list first last))))
           (generator
             (gen-vector element-generator :min-length 1 :max-length 1))
           (candidates
             (cl-weave::property-shrink-candidates
              generator
              (vector (make-equalp-shrink-candidate :value 8)))))
      (expect (length candidates) :to-be 1)
      (expect (aref (first candidates) 0) :to-be last)))

  (it "deduplicates 100000 acyclic candidates without quadratic fallback" (flet ((exercise () (let* ((values (loop for index below 100000 collect index)) (composites (loop for index below 100000 collect (list index))) (unique (cl-weave::remove-duplicate-shrink-candidates values (function equal))) (duplicates (cl-weave::remove-duplicate-shrink-candidates (append values values) (function equal))) (composite-unique (cl-weave::remove-duplicate-shrink-candidates composites (function equal))) (composite-duplicates (cl-weave::remove-duplicate-shrink-candidates (append composites composites) (function equal)))) (expect unique :to-equal values) (expect duplicates :to-equal values) (expect (length composite-unique) :to-be 100000) (expect (first composite-unique) :to-be (first composites)) (expect (length composite-duplicates) :to-be 100000) (expect (first composite-duplicates) :to-be (first composites))))) #+sbcl (sb-ext:with-timeout 10 (exercise)) #-sbcl (exercise)))

  (it "preserves composite equality on the acyclic hash fast path" (labels ((make-table (test entries) (let ((table (make-hash-table :test test))) (dolist (entry entries table) (setf (gethash (car entry) table) (cdr entry)))))) (let* ((dotted-first (cons 1 2)) (dotted-last (cons 1 2)) (list-first (list :nested (list 1 2))) (list-last (list :nested (list 1 2))) (vector-first (vector "X" (list 1 2))) (vector-last (vector "x" (list 1 2))) (array-first (make-array (quote (2 5)) :initial-contents (quote ((0 1 2 3 4) (5 6 7 8 9))))) (array-last (make-array (quote (2 5)) :initial-contents (quote ((0 1 2 3 4) (5 6 7 8 9))))) (array-late-different (make-array (quote (2 5)) :initial-contents (quote ((0 1 2 3 4) (5 6 7 8 10))))) (array-shape-different (make-array (quote (5 2)) :initial-contents (quote ((0 1) (2 3) (4 5) (6 7) (8 9))))) (table-first (make-table (quote equal) (quote ((:present . nil) (:value . 2))))) (table-last (make-table (quote equal) (quote ((:value . 2) (:present . nil))))) (table-missing (make-table (quote equal) (quote ((:missing . nil) (:value . 2))))) (table-test-diff (make-table (quote eql) (quote ((:present . nil) (:value . 2)))))) (dolist (case (list (list dotted-first dotted-last (function equal)) (list list-first list-last (function equal)) (list vector-first vector-last (function equalp)) (list array-first array-last (function equalp)) (list table-first table-last (function equalp)))) (let ((result (cl-weave::remove-duplicate-shrink-candidates (list (first case) (second case)) (third case)))) (expect (length result) :to-be 1) (expect (first result) :to-be (second case)))) (dolist (different (list array-late-different array-shape-different table-missing table-test-diff)) (expect (length (cl-weave::remove-duplicate-shrink-candidates (list (if (arrayp different) array-first table-first) different) (function equalp))) :to-be 2)))))

  (it "compares deep-keyed and recursive equalp hash tables safely"
  (labels ((make-deep-key (leaf)
             (loop repeat 100000
                   do (setf leaf (cons leaf nil))
                   finally (return leaf)))
           (make-key-table (test key value)
             (let ((table (make-hash-table :test test)))
               (setf (gethash key table) value)
               table))
           (make-large-scalar-table (reverse-p)
             (let ((table (make-hash-table :test (function equal))))
               (loop repeat 5000
                     for ordinal from 0
                     for key = (if reverse-p
                                   (- 4999 ordinal)
                                   ordinal)
                     do (setf (gethash key table) key))
               table))
           (make-cyclic-eq-key-table ()
             (let ((key (cons :cycle nil))
                   (table (make-hash-table :test (function eq))))
               (setf (cdr key) key
                     (gethash key table) :same)
               table))
           (make-self-value-table ()
             (let ((table (make-hash-table :test (function equal))))
               (setf (gethash :self table) table)
               table))
           (make-self-key-table (test value &optional extra-entry-p)
             (let ((table (make-hash-table :test test)))
               (setf (gethash table table) value)
               (when extra-entry-p
                 (setf (gethash :extra table) t))
               table))
           (make-mutual-table-cycle ()
             (let ((left (make-hash-table :test (function equal)))
                   (right (make-hash-table :test (function equal))))
               (setf (gethash :peer left) right
                     (gethash :peer right) left)
               left))
           (make-owner-key-value-cycle ()
             (let* ((owner (make-hash-table :test (function equalp)))
                    (key (cons :owner owner))
                    (value (make-hash-table :test (function equalp))))
               (setf (gethash :owner value) owner
                     (gethash key owner) value)
               owner)))
    (flet ((exercise ()
             (let* ((self-first (make-self-value-table))
                    (self-last (make-self-value-table))
                    (mutual-first (make-mutual-table-cycle))
                    (mutual-last (make-mutual-table-cycle))
                    (owner-first (make-owner-key-value-cycle))
                    (owner-last (make-owner-key-value-cycle))
                    (large-first (make-large-scalar-table nil))
                    (large-last (make-large-scalar-table t))
                    (cyclic-key-first (make-cyclic-eq-key-table))
                    (cyclic-key-last (make-cyclic-eq-key-table))
                    (deep-first-key (make-deep-key :same))
                    (deep-last-key (make-deep-key :same))
                    (deep-different-key (make-deep-key :different))
                    (deep-first
                      (make-key-table (function equal) deep-first-key :same))
                    (deep-last
                      (make-key-table (function equal) deep-last-key :same))
                    (deep-different
                      (make-key-table
                       (function equal)
                       deep-different-key
                       :same))
                    (equalp-self-key-first
                      (make-self-key-table (function equalp) :same))
                    (equalp-self-key-last
                      (make-self-key-table (function equalp) :same))
                    (self-key-base
                      (make-self-key-table (function eq) :same))
                    (self-key-value-different
                      (make-self-key-table (function eq) :different))
                    (self-key-test-different
                      (make-self-key-table (function eql) :same))
                    (self-key-count-different
                      (make-self-key-table (function eq) :same t)))
               (labels ((expect-last (first last)
                          (let ((result
                                  (cl-weave::remove-duplicate-shrink-candidates
                                   (list first last)
                                   (function equalp))))
                            (expect (length result) :to-be 1)
                            (expect (first result) :to-be last))))
                 (expect
                  (cl-weave::candidate-requires-safe-equality-p
                   deep-first
                   (function equalp))
                  :to-be t)
                 (expect-last self-first self-last)
                 (expect-last mutual-first mutual-last)
                 (expect-last owner-first owner-last)
                 (expect-last large-first large-last)
                 (expect-last deep-first deep-last)
                 (expect-last equalp-self-key-first equalp-self-key-last)
                 (expect
                  (length
                   (cl-weave::remove-duplicate-shrink-candidates
                    (list cyclic-key-first cyclic-key-last)
                    (function equalp)))
                  :to-be 2)
                 (expect
                  (length
                   (cl-weave::remove-duplicate-shrink-candidates
                    (list deep-first deep-different)
                    (function equalp)))
                  :to-be 2)
                 (dolist (different
                           (list self-key-value-different
                                 self-key-test-different
                                 self-key-count-different))
                   (expect
                    (length
                     (cl-weave::remove-duplicate-shrink-candidates
                      (list self-key-base different)
                      (function equalp)))
                    :to-be 2))))))
      #+sbcl
      (sb-ext:with-timeout 20
        (exercise))
      #-sbcl
      (exercise))))

(it "compares equal cons cycles and bisimilar shapes safely"
  (labels ((exercise ()
             (dolist (link (list (function rplaca) (function rplacd)))
               (let ((first (cons :cycle :tail))
                     (middle (cons :cycle :tail))
                     (last (cons :cycle :tail)))
                 (funcall link first first)
                 (funcall link middle middle)
                 (funcall link last last)
                 (let ((result
                         (cl-weave::remove-duplicate-shrink-candidates
                          (list first middle last)
                          (function equal))))
                   (expect (length result) :to-be 1)
                   (expect (first result) :to-be last))))
             (let ((one-cycle (cons :cycle nil))
                   (two-cycle-first (cons :cycle nil))
                   (two-cycle-last (cons :cycle nil)))
               (setf (cdr one-cycle) one-cycle
                     (cdr two-cycle-first) two-cycle-last
                     (cdr two-cycle-last) two-cycle-first)
               (let ((result
                       (cl-weave::remove-duplicate-shrink-candidates
                        (list one-cycle two-cycle-first)
                        (function equal))))
                 (expect (length result) :to-be 1)
                 (expect (first result) :to-be two-cycle-first)))))
    #+sbcl
    (sb-ext:with-timeout 5
      (exercise))
    #-sbcl
    (exercise)))

(it "compares recursive equalp structures safely"
  (labels ((make-self-node (value)
             (let ((node
                     (make-recursive-equalp-shrink-candidate :value value)))
               (setf (recursive-equalp-shrink-candidate-next node) node
                     (recursive-equalp-shrink-candidate-alternate node) node)
               node))
           (make-mutual-node (peer-value)
             (let ((root
                     (make-recursive-equalp-shrink-candidate :value :root))
                   (peer
                     (make-recursive-equalp-shrink-candidate
                      :value peer-value)))
               (setf (recursive-equalp-shrink-candidate-next root) peer
                     (recursive-equalp-shrink-candidate-next peer) root)
               root))
           (make-shared-node ()
             (let ((leaf
                     (make-recursive-equalp-shrink-candidate :value :leaf)))
               (make-recursive-equalp-shrink-candidate
                :value :root
                :next leaf
                :alternate leaf)))
           (expect-result (left right expected-count)
             (let ((result
                     (cl-weave::remove-duplicate-shrink-candidates
                      (list left right)
                      #'equalp)))
               (expect (length result) :to-be expected-count)
               (when (= expected-count 1)
                 (expect (first result) :to-be right)))))
    (flet ((exercise ()
             (let* ((self-first (make-self-node :same))
                    (self-last (make-self-node :same))
                    (self-different (make-self-node :different))
                    (mutual-first (make-mutual-node :peer))
                    (mutual-last (make-mutual-node :peer))
                    (mutual-different (make-mutual-node :different))
                    (shared-first (make-shared-node))
                    (shared-last (make-shared-node))
                    (other-class
                      (make-equalp-shrink-candidate :value :root)))
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 self-first #'equalp)
                :to-be t)
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 mutual-first #'equalp)
                :to-be t)
               #+sbcl
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 shared-first #'equalp)
                :to-be nil)
               #-sbcl
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 shared-first #'equalp)
                :to-be t)
               #+sbcl
               (progn
                 (expect-result self-first self-last 1)
                 (expect-result mutual-first mutual-last 1)
                 (expect-result shared-first shared-last 1))
               #-sbcl
               (progn
                 (expect-result self-first self-last 2)
                 (expect-result mutual-first mutual-last 2)
                 (expect-result shared-first shared-last 2)
                 (expect-result self-first self-first 1))
               (expect-result self-first self-different 2)
               (expect-result mutual-first mutual-different 2)
               (expect-result shared-first other-class 2))))
      #+sbcl
      (sb-ext:with-timeout 5
        (exercise))
      #-sbcl
      (exercise))))

 (it "honors vector fill-pointer equalp semantics safely"
  (labels ((make-fill-vector (capacity fill-pointer tail)
             (let ((value
                     (make-array capacity
                                 :fill-pointer fill-pointer
                                 :initial-element tail)))
               (setf (aref value 0) 1
                     (aref value 1) 2)
               value))
           (expect-equal-candidates (first last)
             (let ((result
                     (cl-weave::remove-duplicate-shrink-candidates
                      (list first last)
                      (function equalp))))
               (expect (length result) :to-be 1)
               (expect (first result) :to-be last))))
    (flet ((exercise ()
             (let* ((tail-first (make-fill-vector 4 2 :first-tail))
                    (tail-last (make-fill-vector 4 2 :last-tail))
                    (capacity-last (make-fill-vector 6 2 :last-tail))
                    (capacity-ten (make-fill-vector 10 5 :same-tail))
                    (capacity-five (make-fill-vector 5 5 :same-tail))
                    (plain-last (vector 1 2))
                    (length-last (make-fill-vector 4 3 3))
                    (inactive-self-first (make-fill-vector 4 2 nil))
                    (inactive-self-last (make-fill-vector 4 2 nil)))
               (setf (aref inactive-self-first 2) inactive-self-first
                     (aref inactive-self-last 2) inactive-self-last)
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 inactive-self-first
                 (function equalp))
                :to-be nil)
               (expect (equalp tail-first capacity-last) :to-be t)
               (expect (equalp capacity-ten capacity-five) :to-be t)
               (expect-equal-candidates tail-first tail-last)
               (expect-equal-candidates tail-first capacity-last)
               (expect-equal-candidates capacity-ten capacity-five)
               (expect-equal-candidates tail-first plain-last)
               (expect-equal-candidates
                inactive-self-first
                inactive-self-last)
               (expect
                (length
                 (cl-weave::remove-duplicate-shrink-candidates
                  (list tail-first length-last)
                  (function equalp)))
                :to-be 2))))
      #+sbcl
      (sb-ext:with-timeout 5
        (exercise))
      #-sbcl
      (exercise))))
(progn
(it "deduplicates deeply nested acyclic conses without stack recursion"
  (flet ((exercise ()
           (labels ((make-deep-candidate (leaf)
                      (loop repeat 100000
                            do (setf leaf (cons leaf nil))
                            finally (return leaf))))
             (let* ((first (make-deep-candidate :same))
                    (last (make-deep-candidate :same))
                    (different (make-deep-candidate :different))
                    (equal-result
                      (cl-weave::remove-duplicate-shrink-candidates
                       (list first last)
                       (function equal)))
                    (equalp-result
                      (cl-weave::remove-duplicate-shrink-candidates
                       (list first last)
                       (function equalp)))
                    (different-result
                      (cl-weave::remove-duplicate-shrink-candidates
                       (list first different)
                       (function equalp))))
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 first
                 (function equal))
                :to-be t)
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 first
                 (function equalp))
                :to-be t)
               (expect (length equal-result) :to-be 1)
               (expect (first equal-result) :to-be last)
               (expect (length equalp-result) :to-be 1)
               (expect (first equalp-result) :to-be last)
               (expect (length different-result) :to-be 2)
               (expect (first different-result) :to-be first)
               (expect (second different-result) :to-be different)))))
    #+sbcl
    (sb-ext:with-timeout 20
      (exercise))
    #-sbcl
    (exercise)))
(it "classifies mixed cycles and EQUALP hash tables exactly"
  (labels ((make-mixed-cycle ()
             (let ((root (cons :root nil))
                   (items (make-array 1)))
               (setf (cdr root) items
                     (aref items 0) root)
               root))
           (make-table (test entries)
             (let ((table (make-hash-table :test test)))
               (dolist (entry entries table)
                 (setf (gethash (car entry) table)
                       (cdr entry))))))
    (flet ((exercise ()
             (let* ((mixed-first (make-mixed-cycle))
                    (mixed-last (make-mixed-cycle))
                    (equalp-first
                      (make-table
                       (function equalp)
                       (list (cons #\A "VALUE")
                             (cons 1 "NUMBER"))))
                    (equalp-last
                      (make-table
                       (function equalp)
                       (list (cons 1.0 "number")
                             (cons #\a "value"))))
                    (different-test
                      (make-table
                       (function equal)
                       (list (cons #\a "value")
                             (cons 1 "number"))))
                    (candidates
                      (list mixed-first
                            mixed-last
                            equalp-first
                            equalp-last
                            different-test))
                    (classes
                      (cl-weave::candidate-equality-class-ids
                       candidates
                       (function equalp)))
                    (result
                      (cl-weave::remove-duplicate-shrink-candidates
                       candidates
                       (function equalp))))
               (expect (first classes) :to-be (second classes))
               (expect (third classes) :to-be (fourth classes))
               (expect (= (fourth classes) (fifth classes)) :to-be nil)
               (expect (length result) :to-be 3)
               (expect (first result) :to-be mixed-last)
               (expect (second result) :to-be equalp-last)
               (expect (third result) :to-be different-test))))
      #+sbcl
      (sb-ext:with-timeout 5
        (exercise))
      #-sbcl
      (exercise))))
))

(describe "cycle-safe-candidate-equal-p direct branch coverage"
  (it "compares EQUALP vectors by length and elementwise equality"
    (expect (cl-weave::cycle-safe-candidate-equal-p #(1 2 3) #(1 2 3) (function equalp))
            :to-be-truthy)
    (expect (cl-weave::cycle-safe-candidate-equal-p #(1 2 3) #(1 2 4) (function equalp))
            :to-be nil)
    (expect (cl-weave::cycle-safe-candidate-equal-p #(1 2 3) #(1 2) (function equalp))
            :to-be nil))

  (it "compares EQUALP multi-dimensional arrays by dimensions and elementwise equality"
    (let ((first (make-array '(2 2) :initial-contents '((1 2) (3 4))))
          (same (make-array '(2 2) :initial-contents '((1 2) (3 4))))
          (different-value (make-array '(2 2) :initial-contents '((1 2) (3 9))))
          (different-shape (make-array '(4 1) :initial-contents '((1) (2) (3) (4)))))
      (expect (cl-weave::cycle-safe-candidate-equal-p first same (function equalp))
              :to-be-truthy)
      (expect (cl-weave::cycle-safe-candidate-equal-p first different-value (function equalp))
              :to-be nil)
      (expect (cl-weave::cycle-safe-candidate-equal-p first different-shape (function equalp))
              :to-be nil)))

  (it "rejects a one-sided EQUALP array comparison"
    (expect (cl-weave::cycle-safe-candidate-equal-p #(1 2) 42 (function equalp)) :to-be nil)
    (expect (cl-weave::cycle-safe-candidate-equal-p 42 #(1 2) (function equalp)) :to-be nil))

  (it "does not deep-compare arrays under a plain EQUAL test"
    (let ((first (vector 1 2))
          (second (vector 1 2)))
      (expect (cl-weave::cycle-safe-candidate-equal-p first second (function equal))
              :to-be nil)
      (expect (cl-weave::cycle-safe-candidate-equal-p first first (function equal))
              :to-be-truthy)))

  (it "compares EQUALP hash tables by test, count, and entries"
    (let ((first (make-hash-table :test (function equal)))
          (same (make-hash-table :test (function equal)))
          (different-value (make-hash-table :test (function equal)))
          (different-count (make-hash-table :test (function equal)))
          (different-test (make-hash-table :test (function eql))))
      (setf (gethash :a first) 1
            (gethash :b first) 2)
      (setf (gethash :a same) 1
            (gethash :b same) 2)
      (setf (gethash :a different-value) 1
            (gethash :b different-value) 99)
      (setf (gethash :a different-count) 1)
      (setf (gethash :a different-test) 1
            (gethash :b different-test) 2)
      (expect (cl-weave::cycle-safe-candidate-equal-p first same (function equalp))
              :to-be-truthy)
      (expect (cl-weave::cycle-safe-candidate-equal-p first different-value (function equalp))
              :to-be nil)
      (expect (cl-weave::cycle-safe-candidate-equal-p first different-count (function equalp))
              :to-be nil)
      (expect (cl-weave::cycle-safe-candidate-equal-p first different-test (function equalp))
              :to-be nil)))

  (it "rejects a one-sided EQUALP hash-table comparison"
    (let ((table (make-hash-table :test (function equal))))
      (expect (cl-weave::cycle-safe-candidate-equal-p table :not-a-table (function equalp))
              :to-be nil)
      (expect (cl-weave::cycle-safe-candidate-equal-p :not-a-table table (function equalp))
              :to-be nil)))

  #+sbcl
  (it "compares EQUALP structure-objects by class and slot values"
    (let ((first (make-equalp-shrink-candidate :value 7))
          (same (make-equalp-shrink-candidate :value 7))
          (different (make-equalp-shrink-candidate :value 9))
          (other-class (make-recursive-equalp-shrink-candidate :value 7)))
      (expect (cl-weave::cycle-safe-candidate-equal-p first same (function equalp))
              :to-be-truthy)
      (expect (cl-weave::cycle-safe-candidate-equal-p first different (function equalp))
              :to-be nil)
      (expect (cl-weave::cycle-safe-candidate-equal-p first other-class (function equalp))
              :to-be nil)))

  #+sbcl
  (it "rejects a one-sided EQUALP structure-object comparison"
    (let ((candidate (make-equalp-shrink-candidate :value 1)))
      (expect (cl-weave::cycle-safe-candidate-equal-p candidate :not-a-structure (function equalp))
              :to-be nil)
      (expect (cl-weave::cycle-safe-candidate-equal-p :not-a-structure candidate (function equalp))
              :to-be nil))))
