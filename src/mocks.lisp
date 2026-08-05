(in-package #:cl-weave)

(defun default-mock-implementation (&rest arguments)
  (declare (ignore arguments))
  nil)

(defun ensure-mock-implementation (implementation)
  (unless (functionp implementation)
    (error
      "cl-weave: mock implementation must be a function, got ~S."
      implementation))
  implementation)

(define-conditional-lock-macro with-mock-state-lock ((state)) (mock-state-lock state))

(define-conditional-lock-macro with-mock-registry-lock () *mock-registry-lock*)

(defmacro with-state-unless-disposed ((state disposed-p) &body body)
  "Run BODY with STATE locked, unless the mock STATE belongs to has already
been disposed. When disposed, BODY is skipped and DISPOSED-P (a place) is
set to true; STATE's lock is released either way before this form
returns, so callers signal MOCK-DISPOSED-ERROR (if that is what disposal
means to them) only after the lock is gone."
  `(with-mock-state-lock (,state)
     (cond
       ((mock-state-disposed-p ,state) (setf ,disposed-p t))
       (t ,@body))))

(defun mock-registry-entries ()
  ;; Cross-lock order is registry then state.  Code holding a state lock must
  ;; never acquire the registry lock.
  (with-mock-registry-lock
    (loop for mock being the hash-keys of *mock-states*
            using (hash-value state)
          collect (cons mock state))))

(defun register-mock-call (state mock arguments)
  (let ((disposed-p nil)
        (call-token nil)
        (implementation nil))
    (with-state-unless-disposed (state disposed-p)
      (labels ((push-history (history value)
                 (let ((size (array-total-size history)))
                   (when (= (fill-pointer history) size)
                     (setf history
                           (adjust-array
                             history
                             (max +mock-history-initial-capacity+ (* 2 size))
                             :fill-pointer (fill-pointer history))))
                   (vector-push value history)
                   history)))
        (let ((index (fill-pointer (mock-state-calls state))))
          (setf (mock-state-calls state)
                (push-history (mock-state-calls state) arguments)
                (mock-state-results state)
                (push-history (mock-state-results state)
                              '(:type :incomplete))
                call-token
                (cons (mock-state-generation state) index)
                implementation
                (mock-state-implementation state)))))
    (when disposed-p
      (error 'mock-disposed-error :mock mock))
    ;; Interleave mock invocations onto the time-travel timeline (opt-in).
    (when *execution-journal*
      (record-journal-frame :mock-call :actual arguments :pass t))
    (values call-token implementation)))

(defun register-mock-result (state call-token result)
  (with-mock-state-lock
    (state)
    (when (= (car call-token) (mock-state-generation state))
      (setf (aref (mock-state-results state) (cdr call-token)) result))))

(defun mock-state-for (mock)
  (or
    (with-mock-registry-lock (gethash mock *mock-states*))
    (error "Value is not a cl-weave mock function: ~S" mock)))

(defun mock-thrown-result (condition)
  (list
    :type
    :throw
    :condition-type
    (class-name (class-of condition))
    :message
    (princ-to-string condition)))

(defun make-unregistered-mock-function (implementation)
  (let ((state
        (make-mock-state
          :implementation
          (ensure-mock-implementation implementation)
          :restore
          nil))
        (mock nil))
    (setf mock (lambda (&rest arguments)
        (multiple-value-bind (call-token implementation) (register-mock-call state mock arguments)
          (let ((completed nil)
                (signaled-error nil))
            (unwind-protect (handler-bind ((error
                    (lambda (condition)
                      (setf signaled-error condition))))
                (let ((values (multiple-value-list (apply implementation arguments))))
                  (register-mock-result
                    state
                    call-token
                    (list :type :return :value (first values) :values values))
                  (setf completed t)
                  (values-list values)))
              (unless completed
                (register-mock-result
                  state
                  call-token
                  (if signaled-error (mock-thrown-result signaled-error)
                    '(:type :non-local-exit)))))))))
    (values mock state)))

(defun make-mock-function (&optional (implementation #'default-mock-implementation))
  (multiple-value-bind (mock state) (make-unregistered-mock-function implementation)
    (with-mock-registry-lock
      (setf (gethash mock *mock-states*) state))
    mock))

(defun mock-function-p (value)
  (with-mock-registry-lock (nth-value 1 (gethash value *mock-states*))))

(defun copy-cons-graph (root)
  (if (atom root) root
    (let ((copies (make-hash-table :test (function eq)))
          (pending nil))
      (labels ((copy-reference (value)
                 (if (consp value) (multiple-value-bind (copy present-p) (gethash value copies)
                (unless present-p
                  (setf copy (list nil)
                        (gethash value copies) copy)
                  (push value pending))
                copy)
              value)))
        (let ((root-copy (copy-reference root)))
          (loop while pending
                do (let* ((original (pop pending))
                   (copy (gethash original copies)))
              (setf (car copy) (copy-reference (car original))
                    (cdr copy) (copy-reference (cdr original)))))
          root-copy)))))

(defun mock-history-snapshot (mock)
  (let ((state (mock-state-for mock)))
    (multiple-value-bind (calls results) (with-mock-state-lock
        (state)
        (values
          (coerce (mock-state-calls state) (quote list))
          (coerce (mock-state-results state) (quote list))))
      (let ((snapshot (copy-cons-graph (cons calls results))))
        (values (car snapshot) (cdr snapshot))))))

(defun mock-calls (mock)
  (let* ((state (mock-state-for mock))
         (calls
        (with-mock-state-lock (state) (coerce (mock-state-calls state) (quote list)))))
    (copy-cons-graph calls)))

(defun mock-results (mock)
  (let* ((state (mock-state-for mock))
         (results
        (with-mock-state-lock (state) (coerce (mock-state-results state) (quote list)))))
    (copy-cons-graph results)))

(defun mock-implementation (mock implementation)
  (let ((state (mock-state-for mock))
        (implementation (ensure-mock-implementation implementation))
        (disposed-p nil))
    (with-state-unless-disposed (state disposed-p)
      (setf (mock-state-implementation state) implementation))
    (when disposed-p
      (error 'mock-disposed-error :mock mock)))
  mock)

(defun mock-return-values (mock &rest values)
  (mock-implementation
    mock
    (lambda (&rest arguments)
      (declare (ignore arguments))
      (values-list values))))

(defun mock-return-value (mock value)
  (mock-return-values mock value))

(defun restore-symbol-if-current (symbol frame)
  "If SYMBOL's function cell still holds FRAME's mock, restore it to
FRAME's original function."
  (when (and (fboundp symbol) (eq (symbol-function symbol) (spy-frame-mock frame)))
    (setf (symbol-function symbol) (spy-frame-original frame))))

(defun clear-resident-spy-frame (frame)
  "Detach FRAME's mock state from resident-spy bookkeeping once FRAME is
no longer the active occupant of its target symbol."
  (with-mock-state-lock ((spy-frame-state frame))
    (setf (mock-state-implementation (spy-frame-state frame)) (spy-frame-original frame)
          (mock-state-resident-spy-frame (spy-frame-state frame)) nil)))

(defun collapse-restored-spies (symbol)
  (let ((stack (gethash symbol *spy-stacks*)))
    (loop while (and stack (spy-frame-restored-p (first stack)))
          for frame = (pop stack)
          do (restore-symbol-if-current symbol frame)
             (clear-resident-spy-frame frame))
    (if stack
        (setf (gethash symbol *spy-stacks*) stack)
        (remhash symbol *spy-stacks*))))

(defun spy-on (symbol)
  (unless (symbolp symbol)
    (error "cl-weave: spy target must be a symbol, got ~S." symbol))
  (let ((missing-target-p nil)
        (mock nil))
    (with-mock-registry-lock
      (if (fboundp symbol)
        (let ((original (symbol-function symbol)))
          (multiple-value-bind (created-mock state)
              (make-unregistered-mock-function original)
            (let ((frame
                  (make-spy-frame
                    :symbol
                    symbol
                    :mock
                    created-mock
                    :state
                    state
                    :original
                    original
                    :restored-p
                    nil)))
              (setf mock created-mock
                    (mock-state-restore state) frame
                    (mock-state-resident-spy-frame state) frame
                    (gethash created-mock *mock-states*) state)
              (push frame (gethash symbol *spy-stacks*))
              (setf (symbol-function symbol) created-mock))))
        (setf missing-target-p t)))
    (when missing-target-p
      (error "cl-weave: spy target must name a function cell, got ~S." symbol))
    mock))

(defun clear-mock-history-unlocked (state)
  (let ((calls (mock-state-calls state))
        (results (mock-state-results state)))
    (fill calls nil :end (fill-pointer calls))
    (fill results nil :end (fill-pointer results))
    (setf (fill-pointer calls) 0
          (fill-pointer results) 0)
    (incf (mock-state-generation state))))

(defun clear-mock-state (state)
  (with-mock-state-lock (state) (clear-mock-history-unlocked state)))

(defun clear-mock (mock)
  (clear-mock-state (mock-state-for mock))
  mock)

(defun dispose-mock (mock)
  (let ((state nil)
        (registered-p nil)
        (frame nil)
        (disposed-p nil))
    (with-mock-registry-lock
      (multiple-value-setq (state registered-p) (gethash mock *mock-states*))
      (when registered-p
        (setf frame (mock-state-resident-spy-frame state))
        (unless frame
          (with-state-unless-disposed (state disposed-p)
            (setf (mock-state-disposed-p state) t
                  (mock-state-implementation state) #'default-mock-implementation)
            (clear-mock-history-unlocked state)
            (remhash mock *mock-states*)))))
    (cond
      ((not registered-p) (error "Value is not a cl-weave mock function: ~S" mock))
      (frame
        (error 'active-spy-disposal-error :mock mock :symbol (spy-frame-symbol frame)))
      (disposed-p (error 'mock-disposed-error :mock mock)))
    mock))

(defun reset-mock (mock)
  (mock-implementation mock #'default-mock-implementation)
  (clear-mock mock)
  mock)

(defun mock-restore (mock)
  (let ((state (mock-state-for mock)))
    (with-mock-registry-lock
      (let ((frame (mock-state-restore state)))
        (when frame
          (clear-mock-state state)
          (setf (spy-frame-restored-p frame) t
                (mock-state-restore state) nil)
          (collapse-restored-spies (spy-frame-symbol frame)))))
    mock))

(defun map-mocks (function)
  (dolist (entry (mock-registry-entries))
    (funcall function (car entry) (cdr entry)))
  t)

(defun clear-all-mocks ()
  (map-mocks
    (lambda (mock state)
      (declare (ignore state))
      (clear-mock mock))))

(defun reset-all-mocks ()
  (map-mocks
    (lambda (mock state)
      (declare (ignore state))
      (reset-mock mock))))

(defun restore-all-mocks ()
  (map-mocks
    (lambda (mock state)
      (when (mock-state-restore state)
        (mock-restore mock)))))

(defun mock-called-with-p (mock expected-arguments &optional report)
  (some
    (lambda (actual-arguments)
      (equal actual-arguments expected-arguments))
    (if report (getf report :calls)
      (mock-calls mock))))

(defun mock-returned-with-p (mock expected-values &optional report)
  (some
    (lambda (result)
      (and
        (eq (getf result :type) :return)
        (equal (getf result :values) expected-values)))
    (if report (getf report :results)
      (mock-results mock))))

(defun one-based-index-expected (index matcher)
  (unless (and (integerp index) (plusp index))
    (error "cl-weave: ~A expects a positive integer index, got ~S." matcher index))
  index)

(defun expected-index-and-tail (expected matcher)
  (unless expected
    (error "cl-weave: ~A expects an index followed by expected values." matcher))
  (values (one-based-index-expected (first expected) matcher) (rest expected)))

(defun nth-list-entry (entries index)
  (let ((tail (nthcdr (1- index) entries)))
    (values (first tail) (not (null tail)))))

(defun last-list-entry (entries)
  (let ((tail (last entries)))
    (values (first tail) (not (null tail)))))

(defun return-results (results)
  (remove-if-not
    (lambda (result)
      (eq (getf result :type) :return))
    results))

(defun mock-report (mock)
  (multiple-value-bind (calls results) (mock-history-snapshot mock)
    (list
      :call-count
      (length calls)
      :calls
      calls
      :result-count
      (length results)
      :results
      results
      :return-count
      (count
        :return
        results
        :key
        (lambda (result)
          (getf result :type)))
      :throw-count
      (count
        :throw
        results
        :key
        (lambda (result)
          (getf result :type))))))
