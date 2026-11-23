(in-package #:cl-weave/spec)

(defun bounded-report-value (value &optional (depth 0))
  (cond
    ((stringp value)
     (if (> (length value) 160)
         (concatenate 'string (subseq value 0 160) "...") value))
    ((bit-vector-p value)
     (if (> (length value) 160) (subseq value 0 160) value))
    ((consp value)
     (if (>= depth 6) :...
         (loop with tail = value for index below 20 while (consp tail)
               collect (bounded-report-value (pop tail) (1+ depth)) into items
               finally (return (nconc items (cond ((null tail) nil)
                                                 ((consp tail) (list :...))
                                                 (t (bounded-report-value tail (1+ depth)))))))))
    (t value)))

(defun report-value-string (value)
  (let ((*print-length* 20) (*print-level* 6) (*print-circle* t))
    (format nil "~S" (bounded-report-value value))))

(defun trace-step-payloads (steps)
  (loop for step in steps for index from 0
        collect (list :index index :action (trace-step-action step)
                      :params (trace-step-params step) :state (trace-step-state step))))

(defun trace-payload (trace)
  (if (lasso-p trace)
      (list :prefix (trace-step-payloads (lasso-prefix trace))
            :cycle (trace-step-payloads (lasso-cycle trace)))
      (trace-step-payloads trace)))

(defun write-trace-steps (steps stream)
  (let ((count (length steps)))
    (loop for step in steps for index from 0
          do (cond
               ((and (> count 20) (= index 10))
                (format stream "  ... (~D steps omitted)~%" (- count 20)))
               ((or (<= count 20) (< index 10) (>= index (- count 10)))
                (format stream "  ~D: ~A ~A => ~A~%" index
                        (report-value-string (trace-step-action step))
                        (report-value-string (trace-step-params step))
                        (report-value-string (trace-step-state step))))))))

(defun format-spec-trace (trace &optional stream)
  (flet ((emit (out)
           (if (lasso-p trace)
               (progn (write-line "Prefix:" out)
                      (write-trace-steps (lasso-prefix trace) out)
                      (write-line "Cycle:" out)
                      (write-trace-steps (lasso-cycle trace) out))
               (write-trace-steps trace out))))
    (if stream (emit stream) (with-output-to-string (out) (emit out)))))

(defun history-operation-summary (operation)
  (list :id (history-operation-id operation) :thread (history-operation-thread operation)
        :action (history-operation-action operation) :params (history-operation-params operation)
        :output (history-operation-output operation) :invoked (history-operation-invoked operation)
        :returned (history-operation-returned operation)))

(defun write-report-history (label operations stream)
  (format stream "~A:~%" label)
  (loop for operation in operations for index from 0
        do (when (= index 20)
             (write-line "  ... (remaining operations omitted)" stream) (return))
           (format stream "  ~D: ~A~%" index
                   (report-value-string (history-operation-summary operation)))))

(defun spec-result-condition (result)
  (let* ((violation (spec-result-violation result))
         (detail (and violation (spec-violation-detail violation))))
    (with-output-to-string (out)
      (when violation
        (format out "Violation ~A property ~A~%"
                (report-value-string (spec-violation-kind violation))
                (report-value-string (spec-violation-property violation)))
        (format-spec-trace (spec-violation-trace violation) out)
        (when (eq (spec-violation-kind violation) :linearizability)
          (write-report-history "History" (getf detail :history) out)
          (write-report-history "Longest prefix" (getf detail :longest-prefix) out)))
      (format out "States found: ~D; depth reached: ~D.~%"
              (spec-result-states-found result) (spec-result-depth-reached result))
      (when (spec-result-truncated result)
        (format out "Search truncated: ~A. " (report-value-string (spec-result-truncation-reason result)))
        (if (spec-result-liveness-requested result)
            (write-string "Temporal properties cannot pass a truncated search, even with :allow-bounded t." out)
            (write-string "Use :allow-bounded t to permit bounded checking (except temporal properties)." out))))))

(defun spec-result-payload (result &key form)
  (declare (ignore form))
  (let* ((violation (spec-result-violation result))
         (detail (and violation (spec-violation-detail violation)))
         (original (getf detail :original-trace)))
    (list :seed (or (getf detail :seed) (getf (spec-result-statistics result) :seed))
          :case-index (getf detail :case-index)
          :values (and original (trace-payload original))
          :minimal (and violation (trace-payload (spec-violation-trace violation)))
          :condition (spec-result-condition result)
          :spec (spec-result-spec-name result) :mode (spec-result-mode result)
          :kind (and violation (spec-violation-kind violation))
          :property (and violation (spec-violation-property violation))
          :stats (spec-result-statistics result))))

(defun record-spec-trace-steps (steps &key violation-p initial-p)
  (loop for rest on steps for step = (car rest) for first = initial-p then nil
        do (cl-weave:record-journal-frame
            :spec-step :form (if first :init
                                 (cons (trace-step-action step) (trace-step-params step)))
            :actual (trace-step-state step) :expected nil
            :pass (not (and violation-p (null (cdr rest)))))))

(defun record-spec-violation (violation)
  (let ((trace (spec-violation-trace violation)))
    (if (lasso-p trace)
        (progn (record-spec-trace-steps (lasso-prefix trace) :initial-p t)
               (record-spec-trace-steps (lasso-cycle trace) :violation-p t))
        (record-spec-trace-steps trace :initial-p t :violation-p t)))
  (when (eq (spec-violation-kind violation) :linearizability)
    (dolist (operation (getf (spec-violation-detail violation) :history))
      (cl-weave:record-journal-frame
       :spec-history :form (cons (history-operation-action operation) (history-operation-params operation))
       :actual (history-operation-output operation)
       :expected (list :invoked (history-operation-invoked operation)
                       :returned (history-operation-returned operation)
                       :thread (history-operation-thread operation)) :pass t))))

(defmethod cl-weave:journal-frame-line-for-kind ((kind (eql :spec-step)) frame)
  (format nil "#~D spec-step ~A => ~A ~:[FAIL~;ok~]"
          (cl-weave::journal-frame-index frame)
          (report-value-string (cl-weave::journal-frame-form frame))
          (report-value-string (cl-weave::journal-frame-actual frame))
          (cl-weave::journal-frame-pass frame)))

(defmethod cl-weave:journal-frame-line-for-kind ((kind (eql :spec-stats)) frame)
  (format nil "#~D spec-stats ~A ~A limits ~A ~:[FAIL~;ok~]"
          (cl-weave::journal-frame-index frame)
          (report-value-string (cl-weave::journal-frame-form frame))
          (report-value-string (cl-weave::journal-frame-actual frame))
          (report-value-string (cl-weave::journal-frame-expected frame))
          (cl-weave::journal-frame-pass frame)))

(defmethod cl-weave:journal-frame-line-for-kind ((kind (eql :spec-history)) frame)
  (format nil "#~D spec-history ~A => ~A ~A ~:[FAIL~;ok~]"
          (cl-weave::journal-frame-index frame)
          (report-value-string (cl-weave::journal-frame-form frame))
          (report-value-string (cl-weave::journal-frame-actual frame))
          (report-value-string (cl-weave::journal-frame-expected frame))
          (cl-weave::journal-frame-pass frame)))

(defun report-spec-result (result &key form)
  (let ((violation (spec-result-violation result))
        (pass (spec-result-passed-p result)))
    (when violation (record-spec-violation violation))
    (cl-weave:record-journal-frame
     :spec-stats :form (spec-result-spec-name result)
     :actual (append (list :states-found (spec-result-states-found result)
                           :depth-reached (spec-result-depth-reached result)
                           :truncated (spec-result-truncated result))
                     (spec-result-statistics result))
     :expected (spec-result-limits result) :pass pass)
    (if pass result
        (cl-weave::signal-assertion-failure
         (cl-weave::make-assertion-detail
          :form form :matcher :spec :actual (spec-result-payload result :form form)
          :expected (spec-result-checked-properties result) :negated nil :pass nil)))))
