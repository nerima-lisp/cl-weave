(in-package #:cl-weave)

(defun suite-lineage (suite)
  (loop for current = suite then (suite-parent current)
        while current
        collect current into suites
        finally (return (nreverse suites))))

(progn
  (defun effective-before-hooks/from-lineage (lineage)
    (loop for current in lineage
          append (suite-hook current before-each)))

  (defun effective-around-hooks/from-lineage (lineage)
    (loop for current in lineage
          append (suite-hook current around-each)))

  (defun effective-after-hooks/from-lineage (lineage)
    (loop for current in (reverse lineage)
          append (reverse (suite-hook current after-each))))

  (defun effective-test-hooks (suite)
    (let ((lineage (suite-lineage suite)))
      (values (effective-before-hooks/from-lineage lineage)
              (effective-around-hooks/from-lineage lineage)
              (effective-after-hooks/from-lineage lineage))))

  (defun effective-before-hooks (suite)
    (effective-before-hooks/from-lineage (suite-lineage suite))))

(defun effective-around-hooks (suite)
  (effective-around-hooks/from-lineage (suite-lineage suite)))

(defun effective-after-hooks (suite)
  (effective-after-hooks/from-lineage (suite-lineage suite)))

(defun call-hooks/collect-errors (hooks &optional phase)
  "Run each hook, collecting the conditions any of them signal. When PHASE is
given and journaling is active, record one :HOOK frame per hook so the lifecycle
appears on the time-travel timeline."
  (let ((errors '()))
    (dolist (hook hooks (nreverse errors))
      (let ((error (handler-case
                       (progn (funcall hook) nil)
                     ;; Collect hook conditions and continue cleanup, but let a
                     ;; platform timeout interrupt firing inside a hook
                     ;; propagate so it reaches the platform timeout handler and
                     ;; is reported as a proper test-timeout rather than a
                     ;; spurious hook failure carrying a leaked internal
                     ;; condition.
                     (serious-condition (condition)
                       (when (platform-timeout-interrupt-p condition)
                         (error condition))
                       condition))))
        (when (and phase *execution-journal*)
          (record-journal-frame :hook :form phase :pass (null error)))
        (when error
          (push error errors))))))

(defun call-around-hooks/k (hooks continue)
  (if (null hooks)
      (funcall continue)
      (let ((continuation-errors nil))
        (handler-case
            (funcall
             (first hooks)
             (lambda ()
               (handler-bind
                   ((error (lambda (condition)
                             (pushnew condition continuation-errors :test #'eq))))
                 (call-around-hooks/k (rest hooks) continue))))
          (error (condition)
            (if (member condition continuation-errors :test #'eq)
                (error condition)
                (error 'hook-failure
                       :phase :around-each
                       :causes (list condition))))))))

(defun call-test-case/k (suite test continue)
  (let ((*test-context* (make-hash-table :test #'equal))
        (*assertion-count* 0)
        (*expected-assertion-count* nil)
        (*expected-assertion-count-form* nil)
        (*has-assertions-required* nil)
        (*has-assertions-form* nil))
    (let ((lineage (suite-lineage suite))
          (primary-condition nil)
          (result nil)
          (cleanup-errors nil))
      ;; SERIOUS-CONDITION includes both ERROR and implementation conditions that
      ;; cannot be classified portably as ERROR, such as SBCL timeout conditions.
      ;; UNWIND-PROTECT guarantees after-each cleanup runs even on non-local exit.
      (unwind-protect
           (handler-case
               (setf result
                     (let ((before-errors
                             (call-hooks/collect-errors
                              (effective-before-hooks/from-lineage lineage)
                              :before-each)))
                       (when before-errors
                         (error 'hook-failure
                                :phase :before-each
                                :causes before-errors))
                       (call-around-hooks/k
                        (effective-around-hooks/from-lineage lineage)
                        (lambda ()
                          (funcall (test-case-function test))
                          (verify-assertion-counts)
                          (funcall continue)))))
             (serious-condition (condition)
               (setf primary-condition condition)))
        (setf cleanup-errors
              (call-hooks/collect-errors
               (effective-after-hooks/from-lineage lineage)
               :after-each)))
      (cond
        (primary-condition
         (setf *attempt-secondary-conditions* cleanup-errors)
         (error primary-condition))
        (cleanup-errors
         (error 'hook-failure :phase :after-each :causes cleanup-errors))
        (t result)))))
