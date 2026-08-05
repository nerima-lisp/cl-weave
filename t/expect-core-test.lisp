(in-package #:cl-weave/test)

(describe "expect core"
  (matcher-pass-cases
    ("snapshot linearization preserves differences and sequence order"
 (progn
   (expect (cl-weave::snapshot-first-difference
         (format nil "alpha~%beta")
         (format nil "omega~%beta"))
        :to-equal
        (quote (:line 1 :expected "alpha" :actual "omega")))
   (expect (cl-weave::snapshot-first-difference
            (format nil "alpha~%beta~%gamma")
            (format nil "alpha~%delta~%gamma"))
           :to-equal
           '(:line 2 :expected "beta" :actual "delta"))
   (expect (cl-weave::snapshot-first-difference
            "alpha"
            (format nil "alpha~%beta"))
           :to-equal
           '(:line 2 :expected nil :actual "beta"))
   (expect (cl-weave::snapshot-first-difference
            (format nil "alpha~%beta")
            "alpha")
           :to-equal
           '(:line 2 :expected "beta" :actual nil))
   (expect (cl-weave::snapshot-first-difference
            (format nil "alpha~%beta")
            (format nil "alpha~%beta"))
           :to-be-null)
   (let ((cl-weave::*snapshot-session* nil)) (let* ((snapshot-root
            (make-test-temporary-directory "snapshot-linearization"))
          (cl-weave::*snapshot-directory* snapshot-root)
          (cl-weave::*snapshot-file-name* "linearization.snapshots")
          (cl-weave::*update-snapshots* t))
     (unwind-protect
          (progn
            (cl-weave::write-snapshot-file
             '(("before" . "before")
               ("after" . "after")))
            (expect
             (cl-weave::snapshot-sequence-match-or-update-p
              '(:created)
              '("vm/run"))
             :to-be-truthy)
            (expect (cl-weave::read-snapshot-file)
                    :to-equal
                    '(("before" . "before")
                      ("after" . "after")
                      ("vm/run[0]" . ":created")))
            (cl-weave::write-snapshot-file
             '(("before" . "before")
               ("vm/run[0]" . ":stale-0")
               ("middle" . "middle")
               ("vm/run[2]" . ":stale-2")
               ("after" . "after")))
            (expect
             (cl-weave::snapshot-sequence-match-or-update-p
              '(:first :second)
              '("vm/run"))
             :to-be-truthy)
            (expect (cl-weave::read-snapshot-file)
                    :to-equal
                    '(("before" . "before")
                      ("middle" . "middle")
                      ("after" . "after")
                      ("vm/run[0]" . ":first")
                      ("vm/run[1]" . ":second")))
            (let ((write-count 0))
              (with-mocked-functions
                  (((symbol-function
                     'cl-weave::write-snapshot-file-unlocked)
                    (lambda (entries file)
                      (declare (ignore entries file))
                      (incf write-count))))
                (expect
                 (cl-weave::snapshot-sequence-match-or-update-p
                  '(:first :second)
                  '("vm/run"))
                 :to-be-truthy))
              (expect write-count :to-be 0))
            (expect
             (cl-weave::snapshot-sequence-match-or-update-p
              '()
              '("vm/run"))
             :to-be-truthy)
            (expect (cl-weave::read-snapshot-file)
                    :to-equal
                    '(("before" . "before")
                      ("middle" . "middle")
                      ("after" . "after"))))
       (uiop:delete-directory-tree snapshot-root
                                   :validate t
                                   :if-does-not-exist :ignore))))))
    ("to-equal" (expect (list :a 1) :to-equal (list :a 1)))
    ("to-equalp" (expect "ok" :to-equalp "OK"))
    ("to-be-truthy" (expect :value :to-be-truthy))
    ("to-be-falsy" (expect nil :to-be-falsy))
    ("to-be-null" (expect nil :to-be-null))
    ("to-be-defined" (expect :value :to-be-defined))
    ("expect-assertions"
     (progn
       (expect-assertions 2)
       (expect :a :to-be :a)
       (expect-not nil :to-be t)))
    ("expect-has-assertions"
     (progn
       (expect-has-assertions)
       (expect t)))
    #+sbcl
    ("to-be-nan" (expect (quiet-nan) :to-be-nan))
    #+sbcl
    ("ordered comparison matchers fail cleanly on NaN instead of trapping"
     (progn
       (expect-not (quiet-nan) :to-be-greater-than 0)
       (expect-not (quiet-nan) :to-be-greater-than-or-equal 0)
       (expect-not (quiet-nan) :to-be-less-than 0)
       (expect-not (quiet-nan) :to-be-less-than-or-equal 0)
       (expect-not (quiet-nan) :to-be-close-to 1.0)))
    ("to-be-one-of list" (expect :ready :to-be-one-of '(:pending :ready :done)))
    ("to-be-one-of vector and hash-table values"
     (progn
       (expect 2 :to-be-one-of #(1 2 3))
       (let ((table (make-hash-table :test #'equal)))
         (setf (gethash :first table) :pending
               (gethash :second table) :ready)
         (expect :ready :to-be-one-of table))))
    ("to-be-one-of empty vector negation"
 (expect-not :ready :to-be-one-of #()))
    ("to-be-one-of hash-table failure payload"
     (let ((table (make-hash-table :test #'equal)))
       (setf (gethash :first table) :pending
             (gethash :second table) :ready)
       (handler-case
           (progn
             (expect :blocked :to-be-one-of table)
             (error "Expected :to-be-one-of to fail."))
         (cl-weave:assertion-failure (condition)
           (with-assertion-detail (detail condition actual expected)
             (expect (cl-weave::assertion-detail-matcher detail)
                     :to-be
                     :to-be-one-of)
             (expect (getf actual :value) :to-be :blocked)
             (expect (getf actual :candidates) :to-be table)
             (expect (getf actual :test) :to-be 'eql)
             (expect (getf actual :candidate-count) :to-be 2)
             (expect (getf actual :matched-index) :to-be-null)
             (expect (getf expected :candidates) :to-be table)
             (expect (getf expected :test) :to-be 'eql)
             (expect (getf expected :candidate-count) :to-be 2))))))
    ("to-be-nan failure payload"
     (handler-case
         (progn
           (expect 42 :to-be-nan)
           (error "Expected :to-be-nan to fail."))
       (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
           (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-nan)
           (expect (getf actual :value) :to-be 42)
           (expect (getf actual :float) :to-be-falsy)
           (expect (getf actual :nan) :to-be-falsy)
           (expect (getf expected :predicate) :to-be :nan)
           (expect (getf expected :test) :to-be :float-nan-p)))))
    ("to-satisfy" (expect 4 :to-satisfy #'evenp))
    ("to-be-type-of" (expect 10 :to-be-type-of 'integer))
    ("to-be-instance-of"
     (expect (make-instance 'sample-widget) :to-be-instance-of 'sample-widget))
    ("to-contain list" (expect '(:a :b :c) :to-contain :b))
    ("to-contain vector" (expect #(:a :b :c) :to-contain :b))
    ("to-contain string" (expect "common-lisp" :to-contain "lisp"))
    ("to-contain-equal list"
     (expect '((:id 1 :name "Ada") (:id 2 :name "Grace"))
             :to-contain-equal
             '(:id 1 :name "Ada")))
    ("to-contain-equal vector"
     (expect #((:id 1 :roles ("dev")) (:id 2 :roles ("ops")))
             :to-contain-equal
             '(:id 2 :roles ("ops"))))
    ("to-contain-equal hash-table values"
     (let ((table (make-hash-table :test #'equal)))
       (setf (gethash "user" table) '(:name "Ada" :roles ("dev")))
       (expect table :to-contain-equal '(:name "Ada" :roles ("dev")))))
    ("to-match substring"
     (expect "common-lisp" :to-match "lisp"))
    ("to-match predicate"
     (expect "Common Lisp"
             :to-match
             (lambda (text)
               (search "Lisp" text))))
    ("to-match failure payload"
     (handler-case
         (progn
           (expect "common-lisp" :to-match "scheme")
           (error "Expected :to-match to fail."))
       (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
           (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-match)
           (expect (getf actual :value) :to-equal "common-lisp")
           (expect (getf actual :pattern) :to-equal "scheme")
           (expect (getf actual :mode) :to-be :substring)
           (expect (getf actual :reason) :to-be :no-match)
           (expect (getf expected :pattern) :to-equal "scheme")
           (expect (getf expected :test) :to-be :substring)))))
    ("to-match-object plist subset"
     (expect '(:id 1 :name "Ada" :roles ("dev" "ops"))
             :to-match-object
             '(:name "Ada")))
    ("to-match-object nested plist subset"
     (expect '(:user (:id 1 :profile (:name "Ada" :active t)) :meta :ignored)
             :to-match-object
             '(:user (:profile (:active t)))))
    ("to-match-object vector exact shape"
     (expect #((:id 1 :name "Ada") (:id 2 :name "Grace" :role "compiler"))
             :to-match-object
             #((:id 1) (:role "compiler"))))
    ("to-match-object hash-table subset"
     (let ((table (make-hash-table :test #'equal)))
       (setf (gethash "user" table) '(:name "Ada" :roles #("dev" "ops")))
       (expect table :to-match-object '(("user" . (:roles #("dev" "ops")))))))
    ("to-match-object slot subset"
     (expect (make-instance 'sample-widget :name "Ada" :state :ready)
             :to-match-object
             '((name . "Ada") (state . :ready))))
    ("to-have-length list" (expect '(:a :b :c) :to-have-length 3))
    ("to-have-length vector" (expect #(:a :b :c) :to-have-length 3))
    ("to-have-length string" (expect "abc" :to-have-length 3))
    ("to-have-property plist"
     (expect '(:user (:name "Ada" :roles #("dev" "ops")))
             :to-have-property
             '(:user :name)
             "Ada"))
    ("to-have-property alist"
     (expect '((:user . ((:name . "Ada"))))
             :to-have-property
             '(:user :name)
             "Ada"))
    ("to-have-property hash-table"
     (let ((table (make-hash-table :test #'equal)))
       (setf (gethash "user" table) '(:name "Ada"))
       (expect table :to-have-property #("user" :name) "Ada")))
    ("to-have-property slot"
     (expect (make-instance 'sample-widget :name "Ada")
             :to-have-property
             'name
             "Ada"))
    ("to-have-property sequence index"
     (expect '(:users #("Ada" "Grace"))
             :to-have-property
             '(:users 1)
             "Grace"))
    ("to-be-close-to default digits" (expect 304/1000 :to-be-close-to 3/10))
    ("to-be-close-to explicit digits"
 (progn
   (expect (+ 0.1d0 0.2d0) :to-be-close-to 0.3d0 5)
   (expect 1 :to-be-close-to 1 cl-weave::+maximum-close-to-precision+)))
    ("to-be-greater-than" (expect 10 :to-be-greater-than 9))
    ("to-be-greater-than-or-equal" (expect 10 :to-be-greater-than-or-equal 10))
    ("to-be-less-than" (expect 9 :to-be-less-than 10))
    ("to-be-less-than-or-equal" (expect 10 :to-be-less-than-or-equal 10))
    ("to-throw" (expect (lambda () (error "boom")) :to-throw))
    ("to-throw condition type"
     (expect (lambda () (error "typed boom")) :to-throw 'simple-error))
    ("to-throw message substring"
     (expect (lambda () (error "needle in haystack")) :to-throw "needle"))
    ("to-throw predicate"
     (expect (lambda () (error "predicate boom"))
             :to-throw
             (lambda (condition)
               (search "predicate" (princ-to-string condition)))))
    ("to-throw rejects muffled warnings"
     (expect (lambda ()
               (expect (lambda ()
                         (handler-bind ((warning #'muffle-warning))
                           (warn "not an error")
                           :ok))
                       :to-throw))
             :to-throw
             'assertion-failure))
    ("expect-resolves" (expect-resolves (lambda () 42) :to-be 42))
    ("expect-rejects condition type"
     (expect-rejects (lambda () (error "missing user")) :to-be-type-of 'simple-error))
    ("expect-poll eventually matches"
     (let ((attempt 0))
       (expect-poll (lambda ()
                      (incf attempt))
         (:timeout-ms 200 :interval-ms 0)
         :to-be 3)))
    ("expect-poll times out after a slow pass"
     (let ((timeout-signals 0))
       (handler-case
           (handler-bind
               ((cl-weave:assertion-failure
                  (lambda (condition)
                    (when (eq (cl-weave::assertion-detail-matcher
                               (cl-weave::failure-detail condition))
                              :poll)
                      (incf timeout-signals)))))
               (expect-poll (lambda ()
                              (sleep 0.01)
                              :ready)
                 (:timeout-ms 0 :interval-ms 0)
                 :to-be :ready))
         (cl-weave:assertion-failure (condition)
           (with-assertion-detail (detail condition actual)
             (expect timeout-signals :to-be 1)
             (expect (cl-weave::assertion-detail-matcher detail) :to-be :poll)
             (expect (getf actual :attempts) :to-be 1)
             (expect (getf actual :timeout-ms) :to-be 0)
             (expect (getf actual :interval-ms) :to-be 0)
             (expect (getf actual :last-value) :to-be :ready)
             (expect (getf actual :last-condition) :to-be-null)
             (let ((last-assertion (getf actual :last-assertion)))
               (expect (getf last-assertion :matcher) :to-be :to-be)
               (expect (getf last-assertion :actual) :to-be :ready)
               (expect (getf last-assertion :expected) :to-equal '(:ready))
               (expect (getf last-assertion :pass) :to-be-truthy))))))
    ("expect-poll without explicit options"
     (let ((attempt 0))
       (expect-poll (lambda ()
                      (incf attempt))
         :to-be 1)))
    ("expect-resolves rejected thunk payload"
     (handler-case
         (progn
           (expect-resolves (lambda () (error "boom")) :to-be :ok)
           (error "Expected expect-resolves to fail."))
       (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
           (expect (cl-weave::assertion-detail-matcher detail) :to-be :resolves)
           (expect (getf actual :state) :to-be :rejected)
           (expect (getf actual :condition-type) :to-be 'simple-error)
           (expect (getf actual :message) :to-match "boom")
           (expect expected :to-equal '(:state :resolved))))))
    ("expect-rejects resolved thunk payload"
     (handler-case
         (progn
           (expect-rejects (lambda () :ok) :to-be-type-of 'simple-error)
           (error "Expected expect-rejects to fail."))
       (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
           (expect (cl-weave::assertion-detail-matcher detail) :to-be :rejects)
           (expect (getf actual :state) :to-be :resolved)
           (expect (getf actual :value) :to-be :ok)
           (expect expected :to-equal '(:state :rejected))))))
    ("expect-poll timeout payload"
     (handler-case
         (progn
           (let ((attempt 0))
             (expect-poll (lambda ()
                            (incf attempt)
                            :pending)
               (:timeout-ms 0 :interval-ms 0)
               :to-be :ready))
           (error "Expected expect-poll to fail."))
       (cl-weave:assertion-failure (condition)
         (with-assertion-detail (detail condition actual expected)
           (let ((last-assertion (getf actual :last-assertion)))
             (expect (cl-weave::assertion-detail-matcher detail) :to-be :poll)
             (expect (getf actual :attempts) :to-be 1)
             (expect (getf actual :timeout-ms) :to-be 0)
             (expect (getf actual :interval-ms) :to-be 0)
             (expect (getf actual :last-value) :to-be :pending)
             (expect (getf last-assertion :matcher) :to-be :to-be)
             (expect (getf last-assertion :actual) :to-be :pending)
             (expect (getf last-assertion :expected) :to-equal '(:ready))
             (expect expected :to-equal '(:state :pass)))))))
    ("expect-poll rejects unsupported option keys"
     (handler-case
         (progn
           (expect-poll (lambda () :ok)
             (:timeout-ms 0 :bogus 1)
             :to-be :ok)
           (error "Expected expect-poll to fail."))
       (simple-error (condition)
         (expect (simple-condition-format-control condition)
                 :to-contain
                 "unsupported keys"))))
    ("expect-poll records thrown conditions in timeout payload"
     (handler-case
         (progn
           (let ((attempt 0))
             (expect-poll (lambda ()
                            (if (= (incf attempt) 1)
                                :pending
                                (progn
                                  (sleep 0.1)
                                  (error "boom"))))
               (:timeout-ms 50 :interval-ms 0)
               :to-be :ready))
           (error "Expected expect-poll to fail."))
       (cl-weave:assertion-failure (condition)
         (with-assertion-detail (detail condition actual)
           (let ((report (getf actual :last-condition)))
             (expect (cl-weave::assertion-detail-matcher detail) :to-be :poll)
             (expect (getf actual :last-assertion) :to-be nil)
             (expect (getf report :state) :to-be :rejected)
             (expect (getf report :condition-type) :to-be 'simple-error)
             (expect (getf report :message) :to-match "boom"))))))
    ("to-run-under-ms" (expect (lambda () (+ 1 1)) :to-run-under-ms 1000))
    ("to-allocate-under"
     (expect (lambda () nil) :to-allocate-under most-positive-fixnum))
    ("to-have-slot symbol" (expect 'sample-widget :to-have-slot 'name))
    ("to-have-slot instance"
     (expect (make-instance 'sample-widget :name "ok") :to-have-slot 'state))
    ("to-have-method-specialized-on"
     (expect #'render-widget :to-have-method-specialized-on '(sample-widget t)))
    ("to-have-slot failure reports normalized payload"
     (handler-case
         (progn
           (expect 'sample-widget :to-have-slot 'missing-slot)
           (error "Expected expect to fail."))
       (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
           (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-have-slot)
           (expect actual :to-equal '(:class sample-widget :slots (name state)))
           (expect expected :to-equal '(:slot missing-slot))))))
    ("to-have-method-specialized-on failure reports normalized payload"
     (handler-case
         (progn
           (expect #'render-widget-mode :to-have-method-specialized-on '(missing t))
           (error "Expected expect to fail."))
       (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual expected)
           (expect (cl-weave::assertion-detail-matcher detail)
                   :to-be
                   :to-have-method-specialized-on)
           (expect (getf actual :methods) :to-contain-equal '(sample-widget t))
           (expect (getf actual :methods) :to-contain-equal '((eql :preview) t))
           (expect expected :to-equal '(:specializers (missing t)))))))
    ("to-throw rejects non-throwing thunk"
     (expect (lambda () (expect (lambda () :ok) :to-throw)) :to-throw))
    ("to-throw rejects non-function"
     (expect (lambda () (expect :not-a-function :to-throw)) :to-throw))
    ("smart equality assertion" (expect (= (+ 1 1) 2)))
    ("smart relational assertion" (expect (< 1 2 3)))
    ("smart truthy assertion" (expect (member :b '(:a :b :c))))
    ("to-match-inline-snapshot"
     (expect '(:ok 42) :to-match-inline-snapshot "(:ok 42)"))
    ("to-match-snapshot"
     ;; Write and read the snapshot in a throwaway temp directory that is
     ;; deleted afterwards, like the sibling snapshot tests. Using a persistent
     ;; directory left the written file behind in the working tree.
     (let ((cl-weave::*snapshot-session* nil)) (let* ((snapshot-root (make-test-temporary-directory "cl-weave-core-snapshots"))
            (cl-weave::*snapshot-directory* snapshot-root)
            (cl-weave::*snapshot-file-name* "matchers.snapshots"))
       (unwind-protect
            (progn
              (cl-weave:with-snapshot-updates
                (expect '(:ok 42) :to-match-snapshot "matcher external snapshot"))
              (expect '(:ok 42) :to-match-snapshot "matcher external snapshot"))
         (uiop:delete-directory-tree snapshot-root
                                     :validate t
                                     :if-does-not-exist :ignore)))))
    ("to-match-snapshot-sequence"
     (let ((cl-weave::*snapshot-session* nil)) (let* ((snapshot-root (make-test-temporary-directory "snapshot-sequence"))
            (cl-weave::*snapshot-directory* snapshot-root)
            (cl-weave::*snapshot-file-name* "sequence.snapshots"))
       (unwind-protect
            (progn
              (cl-weave:with-snapshot-updates
                (expect #((:pc 0 :acc 0) (:pc 1 :acc 1))
                        :to-match-snapshot-sequence
                        "vm/run"))
              (expect '((:pc 0 :acc 0) (:pc 1 :acc 1))
                      :to-match-snapshot-sequence
                      "vm/run")
              (multiple-value-bind (value present-p)
                  (cl-weave:snapshot-value "vm/run[1]")
                (expect value :to-equal "(:pc 1 :acc 1)")
                (expect present-p :to-be-truthy)))
         (uiop:delete-directory-tree snapshot-root
                                     :validate t
                                     :if-does-not-exist :ignore)))))
    ("snapshot inspection API reads external snapshot artifacts"
     (let ((cl-weave::*snapshot-session* nil)) (let* ((snapshot-root (make-test-temporary-directory "snapshot-api"))
            (cl-weave::*snapshot-directory* snapshot-root)
            (cl-weave::*snapshot-file-name* "api.snapshots")
            (key "snapshot-api-entry"))
       (unwind-protect
            (progn
              (cl-weave:with-snapshot-updates
                (expect '(:state :ready :attempt 2) :to-match-snapshot key))
              (expect (cl-weave:snapshot-entries)
                      :to-contain-equal
                      (cons key "(:state :ready :attempt 2)"))
              (multiple-value-bind (value present-p)
                  (cl-weave:snapshot-value key)
                (expect value :to-equal "(:state :ready :attempt 2)")
                (expect present-p :to-be-truthy))
              (multiple-value-bind (value present-p)
                  (cl-weave:snapshot-value "missing-snapshot-key")
                (expect value :to-be-null)
                (expect present-p :to-be-falsy))
              (expect (lambda () (cl-weave:snapshot-value :not-a-string))
                      :to-throw))
         (uiop:delete-directory-tree snapshot-root
                                     :validate t
                                     :if-does-not-exist :ignore)))))
    ("to-match-snapshot rejects missing snapshots"
     (let ((cl-weave::*snapshot-directory* (test-snapshot-directory "cl-weave-core-snapshots"))
           (cl-weave::*snapshot-file-name* "missing.snapshots")
           (key (symbol-name (gensym "MISSING-SNAPSHOT-"))))
       (expect (lambda ()
                 (expect '(:missing 42) :to-match-snapshot key))
               :to-throw)))
    ("not" (expect 1 :not :to-be 2))
    ("expect-not" (expect-not 1 :to-be 2))
    ("expect-extend matcher" (expect 5 :to-be-odd))
    ("extend-expect matcher" (expect 5 :to-be-between 1 10))))

  (it "exercises every to-match pattern mode and failure reason"
    (expect (nth-value 0 (cl-weave::match-string-pattern-p 42 "digit"))
            :to-be nil)
    (expect (nth-value 1 (cl-weave::match-string-pattern-p 42 "digit"))
            :to-satisfy
            (lambda (report) (eq (getf report :reason) :not-a-string)))
    (expect (nth-value 0 (cl-weave::match-string-pattern-p "hello" 'stringp))
            :to-be-truthy)
    (expect (nth-value 0 (cl-weave::match-string-pattern-p "hello" (lambda (s) (search "xyz" s))))
            :to-be nil)
    (expect (nth-value 1 (cl-weave::match-string-pattern-p "hello" (lambda (s) (search "xyz" s))))
            :to-satisfy
            (lambda (report) (eq (getf report :reason) :predicate-false)))
    (let ((report (nth-value 1 (cl-weave::match-string-pattern-p
                                 "hello" (lambda (s) (declare (ignore s)) (error "boom"))))))
      (expect (getf report :reason) :to-be :predicate-error)
      (expect (getf report :error) :to-contain "boom"))
    (expect (nth-value 0 (cl-weave::match-string-pattern-p "hello" 42))
            :to-be nil)
    (let ((expected-report (nth-value 2 (cl-weave::match-string-pattern-p "hello" 42))))
      (expect (getf expected-report :test) :to-be :valid-pattern)))

)

(describe "matcher builtins branch coverage"
  (it "fails to-be-defined for a nil actual"
    (expect-not nil :to-be-defined))
  #+sbcl
  (it "fails to-be-close-to when the expected value is NaN"
    (expect-not 1.0d0 :to-be-close-to (quiet-nan)))
  (it "fails to-have-slot via expect-not when the slot is missing"
    (expect-not 'sample-widget :to-have-slot 'missing-slot))
  (it "fails to-have-method-specialized-on via expect-not when unspecialized"
    (expect-not #'render-widget-mode :to-have-method-specialized-on '(missing t))))
