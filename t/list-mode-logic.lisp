(in-package #:cl-weave/test)

(progn
  (it "queries facts with Prolog-style macro clauses"
    (let ((facts '((:test ("logic" "runs"))
                   (:status ("logic" "runs") :run)
                   (:concurrent ("logic" "runs"))
                   (:test ("logic" "skips"))
                   (:status ("logic" "skips") :skip))))
      (expect (logic-where facts
                (:status ?test :run)
                (:concurrent ?test))
              :to-equal '(((?test . ("logic" "runs")))))
      (expect (logic-where facts
                (:limit 1)
                (:test ?test))
              :to-equal '(((?test . ("logic" "runs")))))))

  (it "rejects malformed logic-where option clauses"
    (dolist (bad-form
             (list (lambda ()
                     (eval '(logic-where '((:test 1)) (:limit 1) (:limit 2) (:test ?test))))
                   (lambda ()
                     (eval '(logic-where '((:test 1)) (:max-steps 1) (:max-steps 2)
                              (:test ?test))))
                   (lambda ()
                     (eval '(logic-where '((:test 1)) (:limit 1 2) (:test ?test))))
                   (lambda () (eval '(logic-where '((:test 1)) (:limit 1))))))
      (expect bad-form :to-throw)))

  (it "indexes exact path filters without changing path semantics"
    (let* ((count 2000)
           (root (cl-weave::make-suite :name "root"))
           (suite
             (cl-weave::add-child
              root
              (cl-weave::make-suite :name "indexed" :parent root)))
           (filters nil))
      (dotimes (index count)
        (let ((name (format nil "case-~4,'0D" index)))
          (cl-weave::add-child
           suite
           (cl-weave::make-test-case
            :name name
            :function (lambda () t)))
          (push (list (copy-seq "indexed") (copy-seq name)) filters)))
      (dolist (name (list (copy-seq "duplicate")
                          (copy-seq "duplicate")))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name name
          :function (lambda () t))))
      (push (list (copy-seq "indexed") (copy-seq "duplicate")) filters)
      (push (list (copy-seq "indexed") (copy-seq "duplicate")) filters)
      (let* ((plan (cl-weave:collect-test-plan
                    root
                    :test-path-filter filters))
             (paths (mapcar #'cl-weave:test-plan-entry-path plan)))
        (expect (length plan) :to-be (+ count 2))
        (expect (first paths) :to-equal '("indexed" "case-0000"))
        (expect (nth (1- count) paths)
                :to-equal '("indexed" "case-1999"))
        (expect (subseq paths count)
                :to-equal '(("indexed" "duplicate")
                            ("indexed" "duplicate")))
        (expect (length (cl-weave:collect-test-plan
                         root
                         :test-path-filter nil))
                :to-be (+ count 2)))))

  (it "computes each test path once per collection traversal"
    (let* ((count 128)
           (root (cl-weave::make-suite :name "root"))
           (suite
             (cl-weave::add-child
              root
              (cl-weave::make-suite :name "path-count" :parent root)))
           (original-test-path
             (symbol-function 'cl-weave::test-path)))
      (dotimes (index count)
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name (format nil "case-~D" index)
          :function (lambda () t))))
      (dolist (shard (list nil '(1 2)))
        (let ((call-count 0))
          (with-mocked-functions
              (((symbol-function 'cl-weave::test-path)
                (lambda (parent test)
                  (incf call-count)
                  (funcall original-test-path parent test))))
            (cl-weave:collect-test-plan root :shard shard))
          (expect call-count :to-be count)))))

  (it "builds one focus index and uses linear suite membership checks"
    (let* ((depth 1024)
           (root (cl-weave::make-suite :name "root"))
           (parent root)
           (original-build-focus-index
             (symbol-function 'cl-weave::build-focus-index))
           (original-focused-child-p
             (symbol-function 'cl-weave::focused-child-p))
           (original-selected-suite-p
             (symbol-function 'cl-weave::selected-suite-p))
           (focus-index-count 0)
           (recursive-focus-count 0)
           (suite-membership-count 0))
      (dotimes (index depth)
        (let ((child
                (cl-weave::make-suite
                 :name (format nil "level-~D" index)
                 :parent parent)))
          (cl-weave::add-child parent child)
          (setf parent child)))
      (cl-weave::add-child
       parent
       (cl-weave::make-test-case
        :name "focused leaf"
        :focus t
        :function (lambda () t)))
      (with-mocked-functions
          (((symbol-function 'cl-weave::build-focus-index)
            (lambda (suite)
              (incf focus-index-count)
              (funcall original-build-focus-index suite)))
           ((symbol-function 'cl-weave::focused-child-p)
            (lambda (child)
              (incf recursive-focus-count)
              (funcall original-focused-child-p child)))
           ((symbol-function 'cl-weave::selected-suite-p)
            (lambda (suite filter ancestor-focused)
              (incf suite-membership-count)
              (funcall original-selected-suite-p
                       suite filter ancestor-focused))))
        (let ((plan (cl-weave:collect-test-plan root)))
          (expect (length plan) :to-be 1)
          (expect (car (last
                        (cl-weave:test-plan-entry-path (first plan))))
                  :to-equal "focused leaf")))
      (expect focus-index-count :to-be 1)
      (expect recursive-focus-count :to-be 0)
      (expect suite-membership-count
              :to-be-less-than-or-equal
              (1+ depth)))))

(it "derives recursive relations with Prolog-style rules"
    (let ((program (logic-program
                    (:parent "grand" "parent")
                    (:parent "parent" "child")
                    (:- (:ancestor ?left ?right)
                        (:parent ?left ?right))
                    (:- (:ancestor ?left ?right)
                        (:parent ?left ?middle)
                        (:ancestor ?middle ?right)))))
      (expect (logic-run program
                (:ancestor ?left "child"))
              :to-equal
              '(((?left . "parent"))
                ((?left . "grand"))))
      (expect (logic-run program
                (:limit 1)
                (:ancestor ?left "child"))
              :to-equal
              '(((?left . "parent"))))))

(it "rejects cyclic logic bindings"
    (multiple-value-bind (bindings matched-p)
        (cl-weave::unify-logic-values '?x '(:node ?x) nil)
      (declare (ignore bindings))
      (expect matched-p :to-be nil))
    (multiple-value-bind (bindings matched-p)
        (cl-weave::unify-logic-values '(:node ?x) '?x nil)
      (declare (ignore bindings))
      (expect matched-p :to-be nil)))

(it "resolves variables in dotted logic pairs without losing the tail"
    (multiple-value-bind (bindings matched-p)
        (cl-weave::unify-logic-values '(:pair ?head . ?tail)
                                      '(:pair :left . :right)
                                      nil)
      (expect matched-p :to-be t)
      (expect (cl-weave::resolve-logic-value '(:pair ?head . ?tail) bindings)
              :to-equal '(:pair :left . :right))))

(it "resolves long proper lists without consuming stack per element"
    (let* ((length 100000)
           (value (make-list length :initial-element '?value))
           (resolved (cl-weave::resolve-logic-value
                      value '((?value . :resolved)))))
      (expect (length resolved) :to-be length)
      (expect (every (lambda (part) (eq part :resolved)) resolved)
              :to-be t)))

(it "recursively resolves a dotted tail after iterating the list spine"
    (expect (cl-weave::resolve-logic-value
             '(:first ?head . ?tail)
             '((?head . :middle) (?tail . (:tail ?value)) (?value . :end)))
            :to-equal '(:first :middle :tail :end)))

(it "bounds recursive logic searches with explicit recovery restarts"
    (let ((program (logic-program
                    (:- (:loop ?value)
                        (:loop ?value)))))
      (expect (handler-bind
                  ((logic-search-exhausted
                     (lambda (condition)
                       (expect (logic-search-exhausted-limit condition) :to-be 3)
                       (expect (logic-search-exhausted-steps condition) :to-be 3)
                       (expect (logic-search-exhausted-pending condition)
                               :to-satisfy #'plusp)
                       (expect (logic-search-exhausted-partial-results condition)
                               :to-equal nil)
                       (expect (find-restart 'cl-weave:increase-limit condition)
                               :to-be-truthy)
                       (invoke-restart (find-restart 'cl-weave:return-partial-results
                                                     condition)))))
                (logic-query program '((:loop "forever")) :max-steps 3))
              :to-equal nil)))

(it "forwards logic step limits through test plan queries"
    (let ((program (logic-program (:item "found")))
          (exhaustions 0))
      (expect (handler-bind
                  ((logic-search-exhausted
                     (lambda (condition)
                       (incf exhaustions)
                       (invoke-restart (find-restart 'cl-weave:increase-limit condition)
                                       2))))
                (query-test-plan program '((:item ?value)) :max-steps 1))
              :to-equal '(((?value . "found"))))
      (expect exhaustions :to-be 1)))

(it "propagates max steps through logic query macros"
    (let ((program (logic-program
                    (:- (:loop ?value)
                        (:loop ?value))))
          (exhaustions 0))
      (dolist (query (list (lambda ()
                             (logic-run program
                               (:max-steps 2)
                               (:loop "forever")))
                           (lambda ()
                             (logic-where program
                               (:max-steps 2)
                               (:loop "forever")))
                           (lambda ()
                             (test-plan-where program
                               (:max-steps 2)
                               (:loop "forever")))))
        (handler-bind
            ((logic-search-exhausted
               (lambda (condition)
                 (incf exhaustions)
                 (invoke-restart
                  (find-restart 'cl-weave:return-partial-results condition)))))
          (funcall query)))
      (expect exhaustions :to-be 3)))

(it "walks defensive cyclic binding inputs without recursing forever"
    (expect (cl-weave::logic-walk '?x '((?x . ?y) (?y . ?x)))
            :to-satisfy #'logic-variable-p))

(it "queries test plans with macro clauses"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "logic" :parent root :focus t))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "runs"
        :function (lambda () t)
        :execution-mode :concurrent))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "plain"
        :function (lambda () t)))
      (let ((plan (cl-weave:collect-test-plan root)))
        (expect (test-plan-where plan
                  (:status ?test :run)
                  (:focused ?test)
                  (:concurrent ?test))
                :to-equal
                '(((?test . ("logic" "runs"))))))))

(it "queries derived test plan views with rules"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "logic" :parent root :focus t))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "runs"
        :function (lambda () t)
        :execution-mode :concurrent))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "plain"
        :function (lambda () t)))
      (let* ((plan (cl-weave:collect-test-plan root))
             (program (append
                       (test-plan-facts plan)
                       (logic-program
                        (:- (:selected ?test)
                            (:status ?test :run)
                            (:focused ?test)
                            (:concurrent ?test))))))
        (expect (test-plan-where program
                  (:selected ?test))
                :to-equal
                '(((?test . ("logic" "runs"))))))))

(it "preserves plan and event order through deeply nested suite tails"
  (let* ((depth 1024)
         (root (cl-weave::make-suite :name "root"))
         (current root))
    (dotimes (index depth)
      (let ((nested (cl-weave::make-suite
                     :name (format nil "level-~D" index)
                     :parent current)))
        (cl-weave::add-child current nested)
        (cl-weave::add-child
         current
         (cl-weave::make-test-case
          :name (format nil "after-~D" index)
          :function (lambda () t)))
        (setf current nested)))
    (cl-weave::add-child
     current
     (cl-weave::make-test-case :name "leaf" :function (lambda () t)))
    (let* ((expected-names
             (cons "leaf"
                   (loop for index downfrom (1- depth) to 0
                         collect (format nil "after-~D" index))))
           (plan (cl-weave:collect-test-plan root))
           (events (cl-weave::collect-events root)))
      (expect (length plan) :to-be (1+ depth))
      (expect (length events) :to-be (1+ depth))
      (expect (mapcar (lambda (entry)
                        (car (last (cl-weave:test-plan-entry-path entry))))
                      plan)
              :to-equal expected-names)
      (expect (mapcar (lambda (event)
                        (car (last (cl-weave::test-event-path event))))
                      events)
              :to-equal expected-names)
      (expect (mapcar (function cl-weave::test-event-status) events)
              :to-equal (make-list (1+ depth) :initial-element :pass)))))
