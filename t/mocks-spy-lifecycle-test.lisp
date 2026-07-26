(in-package #:cl-weave/test)

(describe "nested spy restoration"
  (it "restores nested spies safely out of order"
    (let ((original (symbol-function 'sample-size))
          (outer nil)
          (inner nil))
      (unwind-protect
          (progn
            (setf outer (spy-on 'sample-size)
                  inner (spy-on 'sample-size))
            (expect (mock-restore outer) :to-be outer)
            (expect (symbol-function 'sample-size) :to-be inner)
            (expect (mock-restore inner) :to-be inner)
            (expect (symbol-function 'sample-size) :to-be original))
        (when inner
          (mock-restore inner))
        (when outer
          (mock-restore outer)))))
  (it "preserves external redefinitions while collapsing restored spies"
      (let ((original (symbol-function 'sample-size))
            (replacement
              (lambda (&rest arguments)
                (declare (ignore arguments))
                :external))
            (outer nil)
            (inner nil))
        (unwind-protect
            (progn
              (setf outer (spy-on 'sample-size)
                    inner (spy-on 'sample-size))
              (setf (symbol-function 'sample-size) replacement)
              (expect (mock-restore outer) :to-be outer)
              (expect (symbol-function 'sample-size) :to-be replacement)
              (expect (mock-restore inner) :to-be inner)
              (expect (symbol-function 'sample-size) :to-be replacement)
              (let ((probe (spy-on 'sample-size)))
                (unwind-protect
                    (progn
                      (expect (mock-restore probe) :to-be probe)
                      (expect (symbol-function 'sample-size)
                              :to-be
                              replacement))
                  (ignore-errors (mock-restore probe))
                  (ignore-errors (dispose-mock probe))))
              (expect (dispose-mock outer) :to-be outer)
              (expect (dispose-mock inner) :to-be inner))
          (ignore-errors (restore-all-mocks))
          (when inner
            (ignore-errors (dispose-mock inner)))
          (when outer
            (ignore-errors (dispose-mock outer)))
          (setf (symbol-function 'sample-size) original))))

  (it "restores every nested spy with restore-all-mocks"
      (let ((original (symbol-function 'sample-size)))
        (unwind-protect
            (progn
              (spy-on 'sample-size)
              (spy-on 'sample-size)
              (expect (restore-all-mocks) :to-be t)
              (expect (symbol-function 'sample-size) :to-be original))
          (restore-all-mocks))))

  (it "tracks resident frames across spy lifecycle and unrelated stacks"
  (let ((original (symbol-function 'sample-size))
        (ordinary (make-mock-function #'identity))
        (outer nil)
        (inner nil)
        (unrelated-spies nil))
    (flet ((expect-active-disposal-error (spy)
             (handler-case
                 (progn
                   (dispose-mock spy)
                   (error "Expected active spy disposal to fail."))
               (active-spy-disposal-error (condition)
                 (expect (active-spy-disposal-error-mock condition) :to-be spy)
                 (expect (active-spy-disposal-error-symbol condition)
                         :to-be
                         'sample-size)))))
      (unwind-protect
          (progn
            (setf unrelated-spies
                  (loop repeat 64
                        for symbol = (gensym "RESIDENT-SPY-")
                        do (setf (symbol-function symbol) #'identity)
                        collect (cons symbol (spy-on symbol))))
            (let ((ordinary-state (cl-weave::mock-state-for ordinary)))
              (expect (cl-weave::mock-state-resident-spy-frame ordinary-state)
                      :to-be
                      nil))
            (expect (dispose-mock ordinary) :to-be ordinary)
            (setf ordinary nil)
            (setf outer (spy-on 'sample-size)
                  inner (spy-on 'sample-size))
            (let* ((outer-state (cl-weave::mock-state-for outer))
                   (inner-state (cl-weave::mock-state-for inner))
                   (outer-frame (cl-weave::mock-state-restore outer-state))
                   (inner-frame (cl-weave::mock-state-restore inner-state)))
              (expect (cl-weave::mock-state-resident-spy-frame outer-state)
                      :to-be
                      outer-frame)
              (expect (cl-weave::mock-state-resident-spy-frame inner-state)
                      :to-be
                      inner-frame)
              (expect-active-disposal-error outer)
              (expect-active-disposal-error inner)
              (expect (mock-restore outer) :to-be outer)
              (expect (cl-weave::mock-state-restore outer-state) :to-be nil)
              (expect (cl-weave::mock-state-resident-spy-frame outer-state)
                      :to-be
                      outer-frame)
              (expect (symbol-function 'sample-size) :to-be inner)
              (expect-active-disposal-error outer)
              (expect (mock-restore inner) :to-be inner)
              (expect (symbol-function 'sample-size) :to-be original)
              (expect (cl-weave::mock-state-resident-spy-frame outer-state)
                      :to-be
                      nil)
              (expect (cl-weave::mock-state-resident-spy-frame inner-state)
                      :to-be
                      nil)
              (expect (dispose-mock outer) :to-be outer)
              (expect (dispose-mock inner) :to-be inner)
              (expect (mock-function-p outer) :to-be nil)
              (expect (mock-function-p inner) :to-be nil)))
        (when inner
          (ignore-errors (mock-restore inner))
          (ignore-errors (dispose-mock inner)))
        (when outer
          (ignore-errors (mock-restore outer))
          (ignore-errors (dispose-mock outer)))
        (dolist (entry unrelated-spies)
          (ignore-errors (mock-restore (cdr entry)))
          (ignore-errors (dispose-mock (cdr entry)))
          (when (fboundp (car entry))
            (fmakunbound (car entry))))
        (when ordinary
          (ignore-errors (dispose-mock ordinary)))
        (setf (symbol-function 'sample-size) original)))))
)

(describe "mock lock safety"
  #+sb-thread
  (it "signals active spy disposal after releasing the registry lock"
    (flet ((exercise ()
             (let ((original (symbol-function 'sample-size))
                   (spy nil)
                   (reentered nil))
               (unwind-protect
                   (progn
                     (setf spy (spy-on 'sample-size))
                     (catch 'condition-handled
                       (handler-bind
                           ((active-spy-disposal-error
                              (lambda (condition)
                                (expect
                                 (active-spy-disposal-error-mock condition)
                                 :to-be
                                 spy)
                                (setf reentered (mock-function-p spy))
                                (throw 'condition-handled nil))))
                         (dispose-mock spy)))
                     (expect reentered :to-be t))
                 (when spy
                   (ignore-errors (mock-restore spy))
                   (ignore-errors (dispose-mock spy)))
                 (setf (symbol-function 'sample-size) original)))))
      #+sbcl
      (sb-ext:with-timeout 5
        (exercise))
      #-sbcl
      (exercise)))

  #+sb-thread
  (it "signals disposed invocation after releasing the state lock"
    (flet ((exercise ()
             (let* ((mock (make-mock-function #'identity))
                    (state (cl-weave::mock-state-for mock))
                    (reentered nil))
               (dispose-mock mock)
               (catch 'condition-handled
                 (handler-bind
                     ((mock-disposed-error
                        (lambda (condition)
                          (expect (mock-disposed-error-mock condition)
                                  :to-be
                                  mock)
                          (cl-weave::clear-mock-state state)
                          (setf reentered t)
                          (throw 'condition-handled nil))))
                   (cl-weave::register-mock-call state mock nil)))
               (expect reentered :to-be t))))
      #+sbcl
      (sb-ext:with-timeout 5
        (exercise))
      #-sbcl
      (exercise)))

  #+sb-thread
  (it "keeps the registered implementation snapshot across disposal"
    (flet ((exercise ()
             (let* ((registered (sb-thread:make-semaphore :count 0))
                    (release (sb-thread:make-semaphore :count 0))
                    (original-register
                      (symbol-function 'cl-weave::register-mock-call))
                    (mock
                      (make-mock-function
                       (lambda (value)
                         (list :original value))))
                    (state (cl-weave::mock-state-for mock))
                    (worker nil)
                    (result nil))
               (unwind-protect
                   (progn
                     (setf (symbol-function 'cl-weave::register-mock-call)
                           (lambda (call-state call-mock arguments)
                             (let ((registration
                                     (multiple-value-list
                                      (funcall original-register
                                               call-state
                                               call-mock
                                               arguments))))
                               (sb-thread:signal-semaphore registered)
                               (sb-thread:wait-on-semaphore release)
                               (values-list registration))))
                     (setf worker
                           (sb-thread:make-thread
                            (lambda ()
                              (setf result (funcall mock :payload)))))
                     (sb-thread:wait-on-semaphore registered)
                     (expect
                      (fill-pointer (cl-weave::mock-state-calls state))
                      :to-be
                      1)
                     (expect (dispose-mock mock) :to-be mock)
                     (expect
                      (fill-pointer (cl-weave::mock-state-calls state))
                      :to-be
                      0)
                     (expect
                      (fill-pointer (cl-weave::mock-state-results state))
                      :to-be
                      0)
                     (sb-thread:signal-semaphore release)
                     (sb-thread:join-thread worker)
                     (setf worker nil)
                     (expect result :to-equal '(:original :payload)))
                 (setf (symbol-function 'cl-weave::register-mock-call)
                       original-register)
                 (when worker
                   (sb-thread:signal-semaphore release)
                   (ignore-errors (sb-thread:join-thread worker)))))))
      #+sbcl
      (sb-ext:with-timeout 5
        (exercise))
      #-sbcl
      (exercise)))

  #+sb-thread
  (it "linearizes concurrent disposal at one registry mutation"
    (flet ((exercise ()
             (dotimes (iteration 100)
               (declare (ignorable iteration))
               (let* ((start (sb-thread:make-semaphore :count 0))
                      (mock (make-mock-function #'identity))
                      (state (cl-weave::mock-state-for mock))
                      (outcomes (make-array 2 :initial-element nil))
                      (threads
                        (loop for index below 2
                              collect
                              (let ((slot index))
                                (sb-thread:make-thread
                                 (lambda ()
                                   (sb-thread:wait-on-semaphore start)
                                   (setf (aref outcomes slot)
                                         (handler-case
                                             (progn
                                               (dispose-mock mock)
                                               :success)
                                           (error () :failure)))))))))
                 (dotimes (index 2)
                   (declare (ignorable index))
                   (sb-thread:signal-semaphore start))
                 (mapc #'sb-thread:join-thread threads)
                 (expect (count :success outcomes) :to-be 1)
                 (expect (count :failure outcomes) :to-be 1)
                 (expect (mock-function-p mock) :to-be nil)
                 (expect (cl-weave::mock-state-disposed-p state) :to-be t)))))
      #+sbcl
      (sb-ext:with-timeout 15
        (exercise))
      #-sbcl
      (exercise))))
