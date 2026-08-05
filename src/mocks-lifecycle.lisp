(in-package #:cl-weave)

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
