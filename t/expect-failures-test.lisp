(in-package #:cl-weave/test)

(describe "expect structured failures"
  (it "validates assertion expectation contracts"
    (dolist (case (quote ((:to-be-truthy :value)
                          (:to-be-falsy nil)
                          (:to-be-null nil)
                          (:to-be-defined :value)
                          (:to-have-been-called :not-a-mock)
                          (:to-have-returned :not-a-mock)
                          (:to-have-thrown :not-a-mock))))
      (destructuring-bind (matcher actual) case
        (let ((condition
                (handler-case
                    (progn
                      (cl-weave::assert-expectation
                       actual
                       (list matcher :unexpected)
                       `(expect ,actual ,matcher :unexpected))
                      nil)
                  (simple-error (caught)
                    caught))))
          (expect condition :to-be-type-of (quote simple-error))
          (expect (princ-to-string condition)
                  :to-contain
                  "expects no expected values")
          (expect (princ-to-string condition)
                  :to-contain
                  (symbol-name matcher)))))
    (multiple-value-bind (pass detail)
        (cl-weave::assert-expectation 1 (list :to-be 1) (quote (expect 1 :to-be 1)))
      (expect pass :to-be-truthy)
      (expect detail :to-be-type-of (quote cl-weave::assertion-detail)))
    (multiple-value-bind (pass detail)
        (cl-weave::assert-expectation 1 (list :to-be 1) (quote (expect 1 :to-be 1)) nil)
      (expect pass :to-be-truthy)
      (expect detail :to-be-null))
    (multiple-value-bind (pass detail) (expect 1 :to-be 1)
      (expect pass :to-be-truthy)
      (expect detail :to-be-null)))

  (it "signals assertion-failure with structured data"
    (handler-case
        (progn
          (expect 1 :to-be 2)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be)
          (expect (cl-weave::assertion-detail-actual detail) :to-be 1)
          (expect (cl-weave::assertion-detail-expected detail) :to-equal '(2))))))

  (it "signals assertion-failure when expect-poll receives a non-callable"
    (handler-case
        (progn
          (expect-poll :not-a-function (:timeout-ms 0 :interval-ms 0) :to-be :ok)
          (error "Expected expect-poll to fail."))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :poll)
          (expect (getf actual :callable) :to-be-falsy)
          (expect (getf actual :value) :to-be :not-a-function)))))

  (it "reports contain-equal matcher failures with structured data"
    (handler-case
        (progn
          (expect '((:id 1 :name "Ada"))
                  :to-contain-equal
                  '(:id 2 :name "Grace"))
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-contain-equal)
          (expect (getf actual :container) :to-equal '((:id 1 :name "Ada")))
          (expect (getf actual :value) :to-equal '(:id 2 :name "Grace"))
          (expect (getf actual :test) :to-be :equalp)
          (expect (getf expected :value) :to-equal '(:id 2 :name "Grace"))
          (expect (getf expected :test) :to-be :equalp)))))

  (it "reports match-object matcher failures with structured path data"
    (handler-case
        (progn
          (expect '(:user (:name "Ada" :roles #("dev")))
                  :to-match-object
                  '(:user (:name "Grace")))
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
          (let ((failure (getf actual :failure)))
            (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-match-object)
            (expect (getf actual :subset) :to-equal '(:user (:name "Grace")))
            (expect (getf failure :path) :to-equal '(:user :name))
            (expect (getf failure :reason) :to-be :value-mismatch)
            (expect (getf failure :actual-value) :to-equal "Ada")
            (expect (getf failure :expected-value) :to-equal "Grace")
            (expect (getf failure :test) :to-be :equalp)
            (expect (getf expected :subset) :to-equal '(:user (:name "Grace")))
            (expect (getf expected :test) :to-be :partial-equalp))))))

  (it "classifies match-object traversal failures consistently"
    (dolist (case (list
                   (list '(:user (:name "Ada"))
                         '(:user (:age 37))
                         '(:user :age)
                         :missing-property
                         nil
                         37)
                   (list '(:items 7)
                         '(:items #(1))
                         '(:items)
                         :type-mismatch
                         7
                         #(1))
                   (list #(1)
                         #(1 2)
                         nil
                         :length-mismatch
                         1
                         2)
                   (list #(1 9)
                         #(1 2)
                         '(1)
                         :value-mismatch
                         9
                         2)))
      (destructuring-bind
          (actual expected path reason actual-value expected-value)
          case
        (multiple-value-bind (pass failure)
            (cl-weave::match-object-value-p actual expected)
          (expect pass :to-be-falsy)
          (expect (getf failure :path) :to-equal path)
          (expect (getf failure :reason) :to-be reason)
          (expect (getf failure :actual-value) :to-equalp actual-value)
          (expect (getf failure :expected-value) :to-equalp expected-value)
          (expect (getf failure :test) :to-be :equalp)))))

  (it "matches large object sequences without consuming control stack"
    (let ((actual (make-array 20000
                              :initial-element '(:state :ready :extra t)))
          (expected (make-array 20000
                                :initial-element '(:state :ready))))
      (expect actual :to-match-object expected)))

  (it "reports property matcher failures with structured path data"
    (handler-case
        (progn
          (expect '(:user (:name "Ada"))
                  :to-have-property
                  '(:user :age)
                  37)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-have-property)
          (expect (getf actual :path) :to-equal '(:user :age))
          (expect (getf actual :present) :to-be nil)
          (expect (getf expected :path) :to-equal '(:user :age))
          (expect (getf expected :value) :to-be 37)))))

  (it "reports close-to matcher failures with structured numeric data"
    (handler-case
        (progn
          (expect 31/100 :to-be-close-to 3/10 2)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-close-to)
          (expect (getf actual :value) :to-be 31/100)
          (expect (getf actual :expected-value) :to-be 3/10)
          (expect (getf actual :num-digits) :to-be 2)
          (expect (getf actual :difference) :to-be 1/100)
          (expect (getf actual :threshold) :to-be 1/200)
          (expect (getf expected :value) :to-be 3/10)
          (expect (getf expected :num-digits) :to-be 2)
          (expect (getf expected :threshold) :to-be 1/200)))))

  (it "reports comparison matcher failures with structured numeric data"
    (handler-case
        (progn
          (expect "10" :to-be-greater-than 9)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-greater-than)
          (expect (getf actual :value) :to-equal "10")
          (expect (getf actual :expected-value) :to-be 9)
          (expect (getf actual :matcher) :to-be :to-be-greater-than)
          (expect (getf actual :operator) :to-be '>)
          (expect (getf actual :actual-real) :to-be-falsy)
          (expect (getf actual :expected-real) :to-be-truthy)
          (expect (getf expected :value) :to-be 9)
          (expect (getf expected :matcher) :to-be :to-be-greater-than)
          (expect (getf expected :operator) :to-be '>)))))

  (it "signals negated matcher failures with structured data"
    (handler-case
        (progn
          (expect-not 1 :to-be 1)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be)
          (expect (cl-weave::assertion-detail-actual detail) :to-be 1)
          (expect (cl-weave::assertion-detail-expected detail) :to-equal '(1))
          (expect (cl-weave::assertion-detail-negated detail) :to-be-truthy)
          (expect (cl-weave::assertion-detail-pass detail) :to-be-truthy)))))

  (it "reports to-throw failures with structured condition data"
    (handler-case
        (progn
          (expect (lambda () (error "wrong message")) :to-throw "needle")
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-throw)
          (expect (getf actual :threw) :to-be-truthy)
          (expect (getf actual :condition-type) :to-be 'simple-error)
          (expect (getf actual :message) :to-contain "wrong message")
          (expect (getf expected :matcher) :to-be :message-substring)
          (expect (getf expected :value) :to-equal "needle")))))

  (it "reports to-throw missing conditions with structured data"
    (handler-case
        (progn
          (expect (lambda () :ok) :to-throw 'simple-error)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-throw)
          (expect (getf actual :threw) :to-be nil)
          (expect (getf actual :condition-type) :to-be nil)
          (expect (getf actual :message) :to-be nil)
          (expect (getf expected :matcher) :to-be :condition-type)
          (expect (getf expected :value) :to-be 'simple-error)))))

  (it "reports missing external snapshots as structured data"
    (let ((cl-weave::*snapshot-directory* (test-snapshot-directory "cl-weave-core-snapshots"))
          (cl-weave::*snapshot-file-name* "missing-structured.snapshots")
          (key (symbol-name (gensym "MISSING-STRUCTURED-SNAPSHOT-"))))
      (handler-case
          (progn
            (expect '(:missing 42) :to-match-snapshot key)
            (expect nil :to-be-truthy))
        (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
            (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-match-snapshot)
            (expect (getf actual :snapshot-key) :to-equal key)
            (expect (getf actual :snapshot-file) :to-contain "missing-structured.snapshots")
            (expect (getf actual :value) :to-equal "(:missing 42)")
            (expect (getf actual :reason) :to-be :missing-snapshot)
            (expect (getf expected :snapshot-key) :to-equal key)
            (expect (getf expected :present) :to-be nil)
            (expect (getf expected :reason) :to-be :missing-snapshot))))))

  (it "reports external snapshot mismatches with first-difference data"
    (let ((cl-weave::*snapshot-session* nil)) (let* ((snapshot-root (make-test-temporary-directory "mismatch-structured"))
           (cl-weave::*snapshot-directory* snapshot-root)
           (cl-weave::*snapshot-file-name* "mismatch-structured.snapshots")
           (key "mismatch-structured-snapshot"))
      (unwind-protect
           (progn
             (cl-weave:with-snapshot-updates
               (expect '(:ok 42) :to-match-snapshot key))
             (handler-case
                 (progn
                   (expect '(:ok 43) :to-match-snapshot key)
                   (expect nil :to-be-truthy))
               (cl-weave:assertion-failure (condition)
                 (with-assertion-detail (detail condition actual expected)
                   (let ((difference (getf actual :difference)))
                     (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-match-snapshot)
                     (expect (getf actual :snapshot-key) :to-equal key)
                     (expect (getf actual :reason) :to-be :snapshot-mismatch)
                     (expect (getf actual :value) :to-equal "(:ok 43)")
                     (expect (getf expected :present) :to-be-truthy)
                     (expect (getf expected :value) :to-equal "(:ok 42)")
                     (expect difference :to-equal (getf expected :difference))
                     (expect (getf difference :line) :to-be 1)
                     (expect (getf difference :expected) :to-equal "(:ok 42)")
                     (expect (getf difference :actual) :to-equal "(:ok 43)"))))))
        (uiop:delete-directory-tree snapshot-root
                                    :validate t
                                    :if-does-not-exist :ignore)))))

  (it "reports external snapshot sequence mismatches with state context"
    (let ((cl-weave::*snapshot-session* nil)) (let* ((snapshot-root (make-test-temporary-directory "sequence-mismatch"))
           (cl-weave::*snapshot-directory* snapshot-root)
           (cl-weave::*snapshot-file-name* "sequence-mismatch.snapshots")
           (prefix "vm/mismatch"))
      (unwind-protect
           (progn
             (cl-weave:with-snapshot-updates
               (expect '((:pc 0 :acc 0) (:pc 1 :acc 1))
                       :to-match-snapshot-sequence
                       prefix))
             (handler-case
                 (progn
                   (expect '((:pc 0 :acc 0) (:pc 1 :acc 99))
                           :to-match-snapshot-sequence
                           prefix)
                   (expect nil :to-be-truthy))
               (cl-weave:assertion-failure (condition)
                 (with-assertion-detail (detail condition actual expected)
                   (let ((difference (getf actual :difference)))
                     (expect (cl-weave::assertion-detail-matcher detail)
                             :to-be
                             :to-match-snapshot-sequence)
                     (expect (getf actual :snapshot-prefix) :to-equal prefix)
                     (expect (getf actual :snapshot-key) :to-equal "vm/mismatch[1]")
                     (expect (getf actual :snapshot-index) :to-be 1)
                     (expect (getf actual :snapshot-count) :to-be 2)
                     (expect (getf actual :reason) :to-be :snapshot-mismatch)
                     (expect (getf actual :value) :to-equal "(:pc 1 :acc 99)")
                     (expect (getf expected :value) :to-equal "(:pc 1 :acc 1)")
                     (expect difference :to-equal (getf expected :difference))
                     (expect (getf difference :line) :to-be 1)
                     (expect (getf difference :expected) :to-equal "(:pc 1 :acc 1)")
                     (expect (getf difference :actual) :to-equal "(:pc 1 :acc 99)"))))))
        (uiop:delete-directory-tree snapshot-root
                                    :validate t
                                    :if-does-not-exist :ignore)))))

  (it "compares large snapshot sequences through exactly one continuation"
    (let* ((count 20000)
           (prefix "large-sequence")
           (values (loop repeat count collect :ready))
           (entries (loop for index below count
                          collect (cons (cl-weave::snapshot-sequence-key
                                         prefix index)
                                        ":ready")))
           (continuations nil))
      (cl-weave::call-with-snapshot-sequence-comparison/k
       values entries prefix count 0
       (lambda () (push :match continuations))
       (lambda (&rest ignored)
         (declare (ignore ignored))
         (push :mismatch continuations)))
      (expect continuations :to-equal '(:match))))

  (progn
(it "reports external snapshot sequence length drift"
    (let ((cl-weave::*snapshot-session* nil)) (let* ((snapshot-root (make-test-temporary-directory "sequence-extra"))
           (cl-weave::*snapshot-directory* snapshot-root)
           (cl-weave::*snapshot-file-name* "sequence-extra.snapshots")
           (prefix "vm/extra"))
      (unwind-protect
           (progn
             (cl-weave:with-snapshot-updates
               (expect '((:pc 0 :acc 0) (:pc 1 :acc 1))
                       :to-match-snapshot-sequence
                       prefix))
             (handler-case
                 (progn
                   (expect '((:pc 0 :acc 0))
                           :to-match-snapshot-sequence
                           prefix)
                   (expect nil :to-be-truthy))
               (cl-weave:assertion-failure (condition)
(with-assertion-detail (detail condition actual expected)
                   (expect (cl-weave::assertion-detail-matcher detail)
                           :to-be
                           :to-match-snapshot-sequence)
                   (expect (getf actual :snapshot-prefix) :to-equal prefix)
                   (expect (getf actual :snapshot-key) :to-equal "vm/extra[1]")
                   (expect (getf actual :snapshot-index) :to-be 1)
                   (expect (getf actual :snapshot-count) :to-be 1)
                   (expect (getf actual :reason) :to-be :unexpected-snapshot)
                   (expect (getf actual :present) :to-be-falsy)
                   (expect (getf expected :present) :to-be-truthy)
                   (expect (getf expected :value) :to-equal "(:pc 1 :acc 1)")))))
        (uiop:delete-directory-tree snapshot-root
                                    :validate t
                                    :if-does-not-exist :ignore)))))
  (it "evaluates dynamic matcher designators"
    (let ((matcher :to-be))
      (expect 1 matcher 1)
      (expect-not 1 matcher 2))))

)
