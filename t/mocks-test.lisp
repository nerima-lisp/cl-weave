(in-package #:cl-weave/test)

(describe "mocking"
  (it "restores symbol functions"
    (expect (sample-size '(a b c)) :to-be 3)
    (with-mocked-functions (((symbol-function 'sample-size)
                             (lambda (value)
                               (declare (ignore value))
                               99)))
      (expect (sample-size '(a b c)) :to-be 99))
    (expect (sample-size '(a b c)) :to-be 3))

  (it "evaluates mocked function places once"
    (let ((place-evaluations 0))
      (with-mocked-functions
          (((symbol-function
             (progn (incf place-evaluations) 'sample-size))
            (lambda (value)
              (declare (ignore value))
              99)))
        (expect place-evaluations :to-be 1)
        (expect (sample-size '(a b c)) :to-be 99))
      (expect place-evaluations :to-be 1)
      (expect (sample-size '(a b c)) :to-be 3)))

  (it "restores earlier replacements when a later replacement fails"
    (expect
     (lambda ()
       (with-mocked-functions
           (((symbol-function 'sample-size)
             (lambda (value)
               (declare (ignore value))
               99))
            ((symbol-function 'sample-size)
             (error "replacement failure")))
         :unreachable))
     :to-throw)
    (expect (sample-size '(a b c)) :to-be 3))

  (it "records mock function calls"
    (let ((mock (make-mock-function (lambda (left right)
                                      (+ left right)))))
      (expect (funcall mock 1 2) :to-be 3)
      (expect (funcall mock 5 8) :to-be 13)
      (expect mock :to-have-been-called)
      (expect mock :to-have-been-called-times 2)
      (expect mock :to-have-been-called-with 1 2)
      (expect mock :to-have-been-nth-called-with 1 1 2)
      (expect mock :to-have-been-nth-called-with 2 5 8)
      (expect mock :to-have-been-last-called-with 5 8)
      (expect (mock-calls mock) :to-equal '((1 2) (5 8)))
      (clear-mock mock)
      (expect mock :not :to-have-been-called)
      (expect (mock-calls mock) :to-equal nil)
      (expect (mock-results mock) :to-equal nil)))

  (it "clears one mock while preserving its implementation"
    (let ((mock (make-mock-function (lambda (value) value))))
      (expect (funcall mock :before) :to-be :before)
      (expect mock :to-have-been-called-times 1)
      (expect (clear-mock mock) :to-be mock)
      (expect mock :not :to-have-been-called)
      (expect (mock-results mock) :to-equal nil)
      (expect (funcall mock :after) :to-be :after)
      (expect mock :to-have-been-called-with :after)))

  (it "creates mock functions that preserve multiple return values"
    (let ((mock (make-mock-function (lambda (value)
                         (values value (1+ value))))))
      (multiple-value-bind (value incremented) (funcall mock 41)
        (expect value :to-be 41)
        (expect incremented :to-be 42))
      (expect mock :to-have-been-called-times 1)
      (expect mock :to-have-been-called-with 41)
      (expect mock :to-have-returned-with 41 42)
      (expect (mock-calls mock) :to-equal '((41)))))

  (it "detects registered mock functions without signalling for other values"
    (let ((mock (make-mock-function)))
      (expect (mock-function-p mock) :to-be t)
      (expect (mock-function-p (lambda () :not-a-mock)) :to-be nil)
      (expect (mock-function-p :not-a-function) :to-be nil)))

  (it "updates mock implementations"
    (let ((mock (make-mock-function)))
      (expect (funcall mock 1) :to-be nil)
      (expect (mock-implementation mock (lambda (value) (* value 2))) :to-be mock)
      (expect (funcall mock 21) :to-be 42)
      (expect mock :to-have-been-called-with 21)
      (expect (mock-implementation mock (lambda (value) (+ value 1))) :to-be mock)
      (expect (funcall mock 41) :to-be 42)
      (expect mock :to-have-returned-with 42)))

  (it "sets mock return values including Common Lisp multiple values"
    (let ((mock (make-mock-function (lambda () :old))))
      (expect (mock-return-value mock :next) :to-be mock)
      (expect (funcall mock :ignored) :to-be :next)
      (expect mock :to-have-returned-with :next)
      (expect (mock-return-values mock :ok 42) :to-be mock)
      (multiple-value-bind (status count) (funcall mock)
        (expect status :to-be :ok)
        (expect count :to-be 42))
      (expect mock :to-have-returned-with :ok 42)
      (expect (mock-return-values mock :done 7) :to-be mock)
      (multiple-value-bind (status count) (funcall mock :ignored)
        (expect status :to-be :done)
        (expect count :to-be 7))
      (expect (mock-return-value mock :final) :to-be mock)
      (expect (funcall mock) :to-be :final)))

  (it "rejects non-function mock implementations early"
    (expect (lambda () (make-mock-function :not-a-function)) :to-throw)
    (let ((mock (make-mock-function)))
      (expect (lambda () (mock-implementation mock :not-a-function)) :to-throw)))

  (it "spies on global function cells and restores originals"
    (expect (sample-size '(a b c)) :to-be 3)
    (let ((spy (spy-on 'sample-size)))
      (expect (mock-function-p spy) :to-be t)
      (expect (sample-size '(a b c d)) :to-be 4)
      (expect spy :to-have-been-called-with '(a b c d))
      (expect spy :to-have-returned-with 4)
      (expect (mock-return-value spy 99) :to-be spy)
      (expect (sample-size '(a b)) :to-be 99)
      (expect (mock-restore spy) :to-be spy)
      (expect (sample-size '(a b)) :to-be 2)
      (expect (mock-restore spy) :to-be spy)))

  (it "restores all spies"
    (let ((spy (spy-on 'sample-size)))
      (expect (mock-return-value spy 10) :to-be spy)
      (expect (sample-size '(a b c)) :to-be 10)
      (expect (restore-all-mocks) :to-be t)
      (expect (sample-size '(a b c)) :to-be 3)
      (expect spy :not :to-have-been-called)))

  (it "rejects spy targets without function cells"
    (expect (lambda () (spy-on "sample-size")) :to-throw)
    (let ((missing (gensym "MISSING-FUNCTION-")))
      (expect (lambda () (spy-on missing)) :to-throw)))

  (it "clears all registered mock histories with clear-all-mocks"
    (let ((left (make-mock-function (lambda () :left)))
          (right (make-mock-function (lambda (value) value))))
      (expect (funcall left) :to-be :left)
      (expect (funcall right :right) :to-be :right)
      (expect left :to-have-been-called-times 1)
      (expect right :to-have-been-called-with :right)
      (expect (clear-all-mocks) :to-be t)
      (expect left :not :to-have-been-called)
      (expect right :not :to-have-been-called)
      (expect (funcall left) :to-be :left)
      (expect left :to-have-been-called-times 1)))

  (it "resets one mock history and implementation"
    (let ((mock (make-mock-function (lambda () :custom))))
      (expect (funcall mock) :to-be :custom)
      (expect mock :to-have-been-called-times 1)
      (expect (reset-mock mock) :to-be mock)
      (expect mock :not :to-have-been-called)
      (expect (funcall mock) :to-be nil)
      (expect mock :to-have-returned-with nil)))

  (it "resets all registered mock histories and implementations with reset-all-mocks"
    (let ((left (make-mock-function (lambda () :left)))
          (right (make-mock-function (lambda () :right))))
      (expect (funcall left) :to-be :left)
      (expect (funcall right) :to-be :right)
      (expect left :to-have-been-called-times 1)
      (expect right :to-have-been-called-times 1)
      (expect (reset-all-mocks) :to-be t)
      (expect left :not :to-have-been-called)
      (expect right :not :to-have-been-called)
      (expect (funcall left) :to-be nil)
      (expect (funcall right) :to-be nil)))

  (it "matches ordered zero-argument mock calls"
    (let ((mock (make-mock-function (lambda () :pong))))
      (expect (funcall mock) :to-be :pong)
      (expect mock :to-have-been-nth-called-with 1)
      (expect mock :to-have-been-last-called-with)))

  (it "records mock return values including multiple values"
    (let ((mock (make-mock-function (lambda (value)
                                      (values value (* value 2))))))
      (multiple-value-bind (value doubled) (funcall mock 4)
        (expect value :to-be 4)
        (expect doubled :to-be 8))
      (multiple-value-bind (value doubled) (funcall mock 7)
        (expect value :to-be 7)
        (expect doubled :to-be 14))
      (expect mock :to-have-returned)
      (expect mock :to-have-returned-times 2)
      (expect mock :to-have-returned-with 4 8)
      (expect mock :to-have-nth-returned-with 1 4 8)
      (expect mock :to-have-nth-returned-with 2 7 14)
      (expect mock :to-have-last-returned-with 7 14)
      (expect (mock-results mock)
              :to-equal
              '((:type :return :value 4 :values (4 8))
                (:type :return :value 7 :values (7 14))))))

  (it "matches returned order without counting thrown results"
    (let ((mock (let ((state 0))
                  (make-mock-function
                   (lambda ()
                     (incf state)
                     (when (= state 2)
                       (error "mock exploded"))
                     (values state :ok))))))
      (multiple-value-bind (value status) (funcall mock)
        (expect value :to-be 1)
        (expect status :to-be :ok))
      (expect (lambda () (funcall mock)) :to-throw "mock exploded")
      (multiple-value-bind (value status) (funcall mock)
        (expect value :to-be 3)
        (expect status :to-be :ok))
      (expect (length (mock-results mock))
              :to-be
              (length (mock-calls mock)))
      (expect mock :to-have-returned-times 2)
      (expect mock :to-have-nth-returned-with 1 1 :ok)
      (expect mock :to-have-nth-returned-with 2 3 :ok)
      (expect mock :to-have-last-returned-with 3 :ok)
      (expect mock :to-have-thrown)))

  (it "records thrown conditions from mock functions"
    (let ((mock (make-mock-function (lambda ()
                                      (error "mock exploded")))))
      (expect (lambda () (funcall mock)) :to-throw "mock exploded")
      (expect mock :to-have-thrown)
      (expect mock :not :to-have-returned)
      (expect (getf (first (mock-results mock)) :type) :to-be :throw)
      (expect (length (mock-results mock))
              :to-be
              (length (mock-calls mock)))
      (expect (getf (first (mock-results mock)) :message)
              :to-contain
              "mock exploded")))

  (it "records non-error non-local exits from mock functions"
    (let ((mock (make-mock-function (lambda () (throw 'mock-exit :escaped)))))
      (expect (catch 'mock-exit (funcall mock)) :to-be :escaped)
      (expect (mock-calls mock) :to-equal '(()))
      (expect (mock-results mock) :to-equal '((:type :non-local-exit)))))

  #+sb-thread
  (it "records concurrent calls and results without losing updates"
    (let* ((count 100)
           (mock (make-mock-function #'identity))
           (state (cl-weave::mock-state-for mock))
           (threads
             (loop for value below count
                   collect (sb-thread:make-thread
                            (lambda () (funcall mock value))))))
      (mapc #'sb-thread:join-thread threads)
      (let ((calls (mock-calls mock))
            (results (mock-results mock)))
        (expect (length calls) :to-be count)
        (expect (length results) :to-be count)
        (expect (vectorp (cl-weave::mock-state-calls state)) :to-be t)
        (expect (vectorp (cl-weave::mock-state-results state)) :to-be t)
        (expect (fill-pointer (cl-weave::mock-state-calls state)) :to-be count)
        (expect (fill-pointer (cl-weave::mock-state-results state)) :to-be count)
        (loop for call in calls
              for result in results
              do (expect (getf result :type) :to-be :return)
                 (expect (getf result :values) :to-equal call))
        (let ((capacity (array-total-size (cl-weave::mock-state-calls state))))
          (clear-mock mock)
          (expect (mock-calls mock) :to-equal nil)
          (expect (mock-results mock) :to-equal nil)
          (expect (fill-pointer (cl-weave::mock-state-calls state)) :to-be 0)
          (expect (array-total-size (cl-weave::mock-state-calls state))
                  :to-be capacity))))
    (let* ((entered (sb-thread:make-semaphore :count 0))
           (release (sb-thread:make-semaphore :count 0))
           (mock (make-mock-function
                  (lambda (value)
                    (if (eq value :old)
                        (progn
                          (sb-thread:signal-semaphore entered)
                          (sb-thread:wait-on-semaphore release)
                          :old-result)
                        :new-result))))
           (thread nil))
      (unwind-protect
          (progn
            (setf thread
                  (sb-thread:make-thread (lambda () (funcall mock :old))))
            (sb-thread:wait-on-semaphore entered)
            (clear-mock mock)
            (expect (funcall mock :new) :to-be :new-result)
            (sb-thread:signal-semaphore release)
            (sb-thread:join-thread thread)
            (setf thread nil)
            (expect (mock-calls mock) :to-equal '((:new)))
            (expect (length (mock-results mock)) :to-be 1)
            (expect (getf (first (mock-results mock)) :values)
                    :to-equal
                    '(:new-result)))
        (when thread
          (sb-thread:signal-semaphore release)
          (sb-thread:join-thread thread)))))

  #+sb-thread
  (it "synchronizes concurrent mock registration and registry snapshots"
    (let* ((initial-count (length (cl-weave::mock-registry-entries)))
           (worker-count 8)
           (mocks-per-worker 25)
           (workers
             (loop repeat worker-count
                   collect (sb-thread:make-thread
                            (lambda ()
                              (loop repeat mocks-per-worker
                                    for mock = (make-mock-function #'identity)
                                    always (and (eq (funcall mock :registered)
                                                    :registered)
                                                (mock-function-p mock)))))))
           (snapshot-worker
             (sb-thread:make-thread
              (lambda ()
                (loop repeat 50
                      do (clear-all-mocks)
                         (cl-weave::mock-registry-entries))))))
      (expect (every #'identity (mapcar #'sb-thread:join-thread workers))
              :to-be
              t)
      (sb-thread:join-thread snapshot-worker)
      (let ((entries (cl-weave::mock-registry-entries)))
        (expect (length entries)
                :to-be
                (+ initial-count (* worker-count mocks-per-worker)))
        (expect (every (lambda (entry)
                         (and (functionp (car entry))
                              (cl-weave::mock-state-p (cdr entry))))
                       entries)
                :to-be
                t))))

  (it "treats muffled warnings as normal mock returns"
    (let ((mock (make-mock-function
                 (lambda ()
                   (handler-bind ((warning #'muffle-warning))
                     (warn "mock warning")
                     :ok)))))
      (expect (funcall mock) :to-be :ok)
      (expect mock :to-have-returned-with :ok)
      (expect mock :not :to-have-thrown)))

  (it "preserves implementation restarts while recording errors"
    (let ((mock (make-mock-function
                 (lambda ()
                   (restart-case
                       (error "recoverable mock error")
                     (recover () :recovered))))))
      (expect (handler-bind ((error (lambda (condition)
                                     (declare (ignore condition))
                                     (invoke-restart 'recover))))
                (funcall mock))
              :to-be
              :recovered)
      (expect mock :not :to-have-thrown)
      (expect mock :to-have-returned-with :recovered)
      (expect (length (mock-results mock))
              :to-be
              (length (mock-calls mock)))))

  (it "reports structured mock assertion failures"
    (handler-case
        (let ((mock (make-mock-function (lambda () :ok))))
          (funcall mock)
          (expect mock :to-have-returned-times 2)
          (error "unreachable"))
      (assertion-failure (condition)
        (let ((assertion (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher assertion)
                  :to-be
                  :to-have-returned-times)
          (expect (getf (cl-weave::assertion-detail-actual assertion)
                        :return-count)
                  :to-be
                  1)
          (expect (cl-weave::assertion-detail-expected assertion)
                  :to-equal
                  '(:return-count 2))))))

  (it "reports structured ordered mock assertion failures"
    (handler-case
        (let ((mock (make-mock-function (lambda (value) value))))
          (funcall mock :actual)
          (expect mock :to-have-been-nth-called-with 2 :missing)
          (error "unreachable"))
      (assertion-failure (condition)
        (let ((assertion (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher assertion)
                  :to-be
                  :to-have-been-nth-called-with)
          (expect (getf (cl-weave::assertion-detail-actual assertion)
                        :call-count)
                  :to-be
                  1)
          (expect (cl-weave::assertion-detail-expected assertion)
                  :to-equal
                  '(:index 2 :arguments (:missing)))))))

  (it "clears retained history references without replacing storage"
    (let* ((result (list :result))
           (mock (make-mock-function (lambda (&rest arguments)
                                      (declare (ignore arguments))
                                      result)))
           (first-argument (list :first))
           (second-argument (list :second)))
      (funcall mock first-argument)
      (funcall mock second-argument)
      (let* ((state (cl-weave::mock-state-for mock))
             (calls (cl-weave::mock-state-calls state))
             (results (cl-weave::mock-state-results state))
             (calls-capacity (array-total-size calls))
             (results-capacity (array-total-size results))
             (generation (cl-weave::mock-state-generation state))
             #+sb-thread
             (lock (cl-weave::mock-state-lock state)))
        (clear-mock mock)
        (expect (cl-weave::mock-state-calls state) :to-be calls)
        (expect (cl-weave::mock-state-results state) :to-be results)
        (expect (array-total-size calls) :to-be calls-capacity)
        (expect (array-total-size results) :to-be results-capacity)
        (expect (fill-pointer calls) :to-be 0)
        (expect (fill-pointer results) :to-be 0)
        (expect (cl-weave::mock-state-generation state) :to-be (1+ generation))
        #+sb-thread
        (expect (cl-weave::mock-state-lock state) :to-be lock)
        (dotimes (index 2)
          (expect (aref calls index) :to-be nil)
          (expect (aref results index) :to-be nil)))))

  #+sbcl
  (it "copies only the requested side of mock history"
    (let* ((payload (loop repeat 200000 collect :payload))
           (calls-heavy
             (make-mock-function
              (lambda (&rest arguments)
                (declare (ignore arguments))
                :ok)))
           (results-heavy (make-mock-function (lambda () payload))))
      (funcall calls-heavy payload)
      (funcall results-heavy)
      (flet ((allocated-by (snapshot)
               (funcall snapshot)
               (let ((before (sb-ext:get-bytes-consed)))
                 (funcall snapshot)
                 (- (sb-ext:get-bytes-consed) before))))
        (expect (< (allocated-by (lambda () (mock-results calls-heavy)))
                   (* 1024 1024))
                :to-be
                t)
        (expect (< (allocated-by (lambda () (mock-calls results-heavy)))
                   (* 1024 1024))
                :to-be
                t))))

  (progn
    (it "copies cyclic mock argument graphs for both snapshot APIs"
      (flet ((exercise ()
               (let* ((mock (make-mock-function
                             (lambda (&rest arguments)
                               (declare (ignore arguments))
                               :ok)))
                      (cdr-cycle (cons :cdr nil))
                      (car-cycle (cons nil :car))
                      (mutual-left (cons :left nil))
                      (mutual-right (cons nil :right)))
                 (setf (cdr cdr-cycle) cdr-cycle
                       (car car-cycle) car-cycle
                       (cdr mutual-left) mutual-right
                       (car mutual-right) mutual-left)
                 (funcall mock cdr-cycle car-cycle mutual-left)
                 (flet ((check-calls (calls)
                          (let* ((arguments (first calls))
                                 (cdr-copy (first arguments))
                                 (car-copy (second arguments))
                                 (mutual-left-copy (third arguments))
                                 (mutual-right-copy (cdr mutual-left-copy)))
                            (expect (eq cdr-copy cdr-cycle) :to-be nil)
                            (expect (eq car-copy car-cycle) :to-be nil)
                            (expect (eq mutual-left-copy mutual-left) :to-be nil)
                            (expect (eq (cdr cdr-copy) cdr-copy) :to-be t)
                            (expect (eq (car car-copy) car-copy) :to-be t)
                            (expect (eq (car mutual-right-copy) mutual-left-copy)
                                    :to-be
                                    t))))
                   (check-calls (mock-calls mock))
                   (multiple-value-bind (history-calls history-results)
                       (cl-weave::mock-history-snapshot mock)
                     (declare (ignore history-results))
                     (check-calls history-calls))))))
        #+sbcl
        (sb-ext:with-timeout 2
          (exercise))
        #-sbcl
        (exercise)))

    (it "preserves sharing across mock history entries and paired results"
      (let* ((mock (make-mock-function (function identity)))
             (marker (vector :marker))
             (shared-tail (list marker))
             (first-root (cons :first shared-tail))
             (second-root (cons :second shared-tail)))
        (funcall mock first-root)
        (funcall mock second-root)
        (flet ((check-calls (calls)
                 (let ((first-copy (first (first calls)))
                       (second-copy (first (second calls))))
                   (expect (eq first-copy first-root) :to-be nil)
                   (expect (eq second-copy second-root) :to-be nil)
                   (expect (eq (cdr first-copy) (cdr second-copy)) :to-be t)
                   (expect (eq (car (cdr first-copy)) marker) :to-be t))))
          (check-calls (mock-calls mock))
          (multiple-value-bind (history-calls history-results)
              (cl-weave::mock-history-snapshot mock)
            (check-calls history-calls)
            (progn
              (expect (eq (getf (first history-results) :value)
                          (first (first history-calls)))
                      :to-be
                      t)
              (expect (eq (first (getf (first history-results) :values))
                          (first (first history-calls)))
                      :to-be
                      t))
            (progn
              (expect (eq (getf (second history-results) :value)
                          (first (second history-calls)))
                      :to-be
                      t)
              (expect (eq (first (getf (second history-results) :values))
                          (first (second history-calls)))
                      :to-be
                      t))))))

    (it "isolates mock snapshots from subsequent source cons mutation"
      (let* ((mock (make-mock-function (function identity)))
             (shared-tail (list :tail))
             (first-root (cons :first shared-tail))
             (second-root (cons :second shared-tail)))
        (funcall mock first-root)
        (funcall mock second-root)
        (let ((calls-only (mock-calls mock)))
          (multiple-value-bind (history-calls history-results)
              (cl-weave::mock-history-snapshot mock)
            (declare (ignore history-results))
            (setf (car first-root) :mutated-first
                  (cdr first-root) nil
                  (car second-root) :mutated-second
                  (car shared-tail) :mutated-tail)
            (flet ((check-calls (calls)
                     (let ((first-copy (first (first calls)))
                           (second-copy (first (second calls))))
                       (expect (car first-copy) :to-be :first)
                       (expect (car second-copy) :to-be :second)
                       (expect (car (cdr first-copy)) :to-be :tail)
                       (expect (eq (cdr first-copy) (cdr second-copy))
                               :to-be
                               t))))
              (check-calls calls-only)
              (check-calls history-calls))))))

    (it "disposes a live mock and rejects subsequent use"
      (let* ((initial-count (length (cl-weave::mock-registry-entries)))
             (payload (list :payload))
             (mock (make-mock-function (lambda () payload)))
             (state (cl-weave::mock-state-for mock)))
        (funcall mock)
        (let ((calls (cl-weave::mock-state-calls state))
              (results (cl-weave::mock-state-results state)))
          (expect (dispose-mock mock) :to-be mock)
          (expect (length (cl-weave::mock-registry-entries)) :to-be initial-count)
          (expect (mock-function-p mock) :to-be nil)
          (expect (cl-weave::mock-state-disposed-p state) :to-be t)
          (expect (fill-pointer calls) :to-be 0)
          (expect (fill-pointer results) :to-be 0)
          (expect (aref calls 0) :to-be nil)
          (expect (aref results 0) :to-be nil)
          (handler-case
              (progn
                (funcall mock)
                (error "Expected disposed mock invocation to fail."))
            (mock-disposed-error (condition)
              (expect (mock-disposed-error-mock condition) :to-be mock)))
          (expect (lambda () (mock-calls mock)) :to-throw)
          (expect (lambda () (dispose-mock mock)) :to-throw)))))

  #+sb-thread
  (it "linearizes concurrent implementation updates with disposal"
    (flet ((exercise ()
             (dotimes (iteration 25)
               (declare (ignorable iteration))
               (let* ((setter-count 16)
                      (start (sb-thread:make-semaphore :count 0))
                      (mock (make-mock-function #'identity))
                      (state (cl-weave::mock-state-for mock))
                      (outcomes (make-array setter-count :initial-element nil))
                      (setters
                        (loop for index below setter-count
                              collect
                              (let ((slot index))
                                (sb-thread:make-thread
                                 (lambda ()
                                   (sb-thread:wait-on-semaphore start)
                                   (setf (aref outcomes slot)
                                         (handler-case
                                             (progn
                                               (mock-implementation mock #'list)
                                               :updated)
                                           (mock-disposed-error () :disposed)
                                           (simple-error () :unregistered))))))))
                      (disposer
                        (sb-thread:make-thread
                         (lambda ()
                           (sb-thread:wait-on-semaphore start)
                           (dispose-mock mock)))))
                 (dotimes (index (1+ setter-count))
                   (declare (ignorable index))
                   (sb-thread:signal-semaphore start))
                 (mapc #'sb-thread:join-thread setters)
                 (sb-thread:join-thread disposer)
                 (expect
                  (every (lambda (outcome)
                           (member outcome
                                   '(:updated :disposed :unregistered)))
                         outcomes)
                  :to-be
                  t)
                 (expect (cl-weave::mock-state-disposed-p state) :to-be t)
                 (expect (cl-weave::mock-state-implementation state)
                         :to-be
                         #'cl-weave::default-mock-implementation)
                 (expect (mock-function-p mock) :to-be nil)))))
      #+sbcl
      (sb-ext:with-timeout 15
        (exercise))
      #-sbcl
      (exercise))))
