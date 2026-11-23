(in-package #:cl-weave/spec-test)

(defun report-test-trace ()
  (list (make-trace-step :state '(x 0))
        (make-trace-step :action 'inc :params '(2) :state '(x 2))))

(defun report-test-result (&key (trace (report-test-trace)) (kind :invariant)
                                (property 'bounded) truncated liveness-requested)
  (make-spec-result
   :spec-name 'counter :mode :exhaustive :states-found 3 :depth-reached 2
   :statistics '(:transitions 2 :initial-states 1)
   :truncated truncated :truncation-reason (when truncated :max-depth)
   :liveness-requested liveness-requested
   :violation (make-spec-violation :kind kind :property property :trace trace)))

(defun report-test-detail (result)
  (handler-case (progn (report-spec-result result :form '(explore-spec counter)) nil)
    (assertion-failure (condition) (cl-weave::failure-detail condition))))

(defun report-test-contains-p (needle text)
  (not (null (search (string-upcase needle) (string-upcase text)))))

(describe "FR-013 spec report"
  (it "reports the full safety trace without a journal"
    (let* ((cl-weave::*execution-journal* nil)
           (detail (report-test-detail (report-test-result)))
           (actual (cl-weave::assertion-detail-actual detail))
           (message (getf actual :condition)))
      (expect (cl-weave::assertion-detail-matcher detail) :to-be :spec)
      (expect (cl-weave::assertion-detail-form detail) :to-equal '(explore-spec counter))
      (expect (cl-weave::assertion-detail-negated detail) :to-be nil)
      (expect (cl-weave::assertion-detail-pass detail) :to-be nil)
      (expect (getf actual :minimal)
              :to-equal '((:index 0 :action nil :params nil :state (x 0))
                          (:index 1 :action inc :params (2) :state (x 2))))
      (dolist (part '("bounded" "invariant" "X 0" "INC" "X 2" "3" "2"))
        (expect (report-test-contains-p part message) :to-be t))))

  (it "continues after a soft assertion failure"
    (let ((cl-weave::*soft-assertion-sink* (make-array 0 :adjustable t :fill-pointer 0))
          (continued nil))
      (report-spec-result (report-test-result))
      (setf continued t)
      (expect continued :to-be t)
      (expect (length cl-weave::*soft-assertion-sink*) :to-be 1)
      (expect (cl-weave::assertion-detail-matcher
               (aref cl-weave::*soft-assertion-sink* 0)) :to-be :spec)))

  (it "formats lasso prefix and cycle with the closing state"
    (let* ((lasso (make-lasso :prefix (report-test-trace)
                              :cycle (list (make-trace-step :action 'inc :params '(-1) :state '(x 1))
                                           (make-trace-step :action 'inc :params '(1) :state '(x 2)))))
           (actual (spec-result-payload (report-test-result :trace lasso :kind :temporal :property 'eventually)))
           (message (getf actual :condition)))
      (expect (getf actual :minimal)
              :to-equal '(:prefix ((:index 0 :action nil :params nil :state (x 0))
                                  (:index 1 :action inc :params (2) :state (x 2)))
                          :cycle ((:index 0 :action inc :params (-1) :state (x 1))
                                  (:index 1 :action inc :params (1) :state (x 2)))))
      (dolist (part '("prefix" "cycle" "X 0" "X 1" "X 2"))
        (expect (report-test-contains-p part message) :to-be t))))

  (it "keeps both violation and truncation information"
    (let ((message (getf (cl-weave::assertion-detail-actual
                          (report-test-detail (report-test-result :truncated t)))
                         :condition)))
      (dolist (part '("bounded" "invariant" "max-depth" "3" "2" "allow-bounded"))
        (expect (report-test-contains-p part message) :to-be t))))

  (it "explains why bounded checking cannot establish liveness"
    (let* ((result (make-spec-result :spec-name 'counter :mode :exhaustive
                                     :states-found 7 :depth-reached 4 :truncated t
                                     :truncation-reason :max-depth :allow-bounded t
                                     :liveness-requested '(eventually)))
           (message (getf (cl-weave::assertion-detail-actual (report-test-detail result))
                          :condition)))
      (dolist (part '("7" "4" "max-depth" "allow-bounded" "temporal"))
        (expect (report-test-contains-p part message) :to-be t))))

  (it "bounds output for a very long trace and a long state string"
    (let* ((long-text (make-string 10000 :initial-element #\z))
           (trace (loop for i below 1000 collect
                        (make-trace-step :action (unless (zerop i) 'step)
                                         :state (list 'x i 'text long-text))))
           (output (format-spec-trace trace)))
      (expect (< (length output) 10000) :to-be t)
      (expect (report-test-contains-p "..." output) :to-be t)))

  (it "records each safety step and the statistics and renders their frame kinds"
    (let* ((frames (cl-weave:with-execution-journal
                     (ignore-errors (report-spec-result (report-test-result)))))
           (steps (remove :spec-step frames :key #'cl-weave:journal-frame-kind :test-not #'eq))
           (stats (find :spec-stats frames :key #'cl-weave:journal-frame-kind)))
      (expect (length steps) :to-be 2)
      (expect (mapcar #'cl-weave:journal-frame-form steps) :to-equal '(:init (inc 2)))
      (expect (mapcar #'cl-weave:journal-frame-actual steps) :to-equal '((x 0) (x 2)))
      (expect (mapcar #'cl-weave:journal-frame-pass steps) :to-equal '(t nil))
      (expect (getf (cl-weave:journal-frame-actual stats) :states-found) :to-be 3)
      (expect (getf (cl-weave:journal-frame-actual stats) :depth-reached) :to-be 2)
      (expect (cl-weave:journal-frame-pass stats) :to-be nil)
      (dolist (frame (append steps (list stats)))
        (expect (stringp (cl-weave:journal-frame-line frame)) :to-be t)
        (expect (plusp (length (cl-weave:journal-frame-line frame))) :to-be t))))

  (it "records statistics even for a bounded passing result"
    (let* ((result (make-spec-result :spec-name 'counter :mode :exhaustive
                                     :states-found 4 :depth-reached 3 :truncated t
                                     :truncation-reason :max-depth :allow-bounded t))
           (returned nil)
           (frames (cl-weave:with-execution-journal
                     (setf returned (report-spec-result result))))
           (stats (find :spec-stats frames :key #'cl-weave:journal-frame-kind)))
      (expect returned :to-be result)
      (expect (cl-weave:journal-frame-pass stats) :to-be t)
      (expect (getf (cl-weave:journal-frame-actual stats) :truncated) :to-be t)))

  (it "retains JSON reporter schema version 6"
    (let ((output (with-output-to-string (stream) (cl-weave::report-json nil stream))))
      (expect output :to-contain "\"schemaVersion\":6"))))

(describe "FR-013 spec report metadata"
  (it "uses the checked properties and actual limits in failure and statistics"
    (let* ((result (make-spec-result :spec-name 'counter :mode :exhaustive
                                     :checked-properties '(bounded monotone :deadlock)
                                     :limits '(:max-states 17 :max-depth 4)
                                     :violation (make-spec-violation
                                                 :kind :invariant :property 'bounded
                                                 :trace (report-test-trace))))
           (detail (report-test-detail result))
           (frames (cl-weave:with-execution-journal
                     (ignore-errors (report-spec-result result))))
           (stats (find :spec-stats frames :key #'cl-weave:journal-frame-kind)))
      (expect (cl-weave::assertion-detail-expected detail)
              :to-equal '(bounded monotone :deadlock))
      (expect (cl-weave:journal-frame-expected stats)
              :to-equal '(:max-states 17 :max-depth 4))))

  (it "reports the original random trace separately from the minimal trace"
    (let* ((original (list (make-trace-step :state '(x 0))
                           (make-trace-step :action 'inc :params '(1) :state '(x 1))
                           (make-trace-step :action 'inc :params '(1) :state '(x 2))))
           (result (make-spec-result :spec-name 'counter :mode :random
                                     :statistics '(:seed 42 :runs 10 :steps 2)
                                     :violation (make-spec-violation
                                                 :kind :invariant :property 'bounded
                                                 :trace (report-test-trace)
                                                 :detail (list :seed 42 :case-index 3
                                                               :original-trace original))))
           (payload (spec-result-payload result)))
      (expect (getf payload :seed) :to-be 42)
      (expect (getf payload :case-index) :to-be 3)
      (expect (getf payload :values)
              :to-equal '((:index 0 :action nil :params nil :state (x 0))
                          (:index 1 :action inc :params (1) :state (x 1))
                          (:index 2 :action inc :params (1) :state (x 2))))
      (expect (getf payload :minimal)
              :to-equal '((:index 0 :action nil :params nil :state (x 0))
                          (:index 1 :action inc :params (2) :state (x 2))))))

  (it "bounds a single long string even in a short trace"
    (let* ((trace (list (make-trace-step :state (list 'text (make-string 10000 :initial-element #\z)))))
           (output (format-spec-trace trace)))
      (expect (< (length output) 1000) :to-be t)
      (expect (report-test-contains-p "..." output) :to-be t)))

  (it "prints a stuttering lasso and records its cycle step"
    (let* ((lasso (make-lasso :prefix (list (make-trace-step :state '(x 0)))
                              :cycle (list (make-trace-step :state '(x 0)))))
           (result (report-test-result :trace lasso :kind :temporal :property 'done))
           (frames (cl-weave:with-execution-journal (ignore-errors (report-spec-result result))))
           (steps (remove :spec-step frames :key #'cl-weave:journal-frame-kind :test-not #'eq))
           (text (getf (spec-result-payload result) :condition)))
      (expect (length steps) :to-be 2)
      (expect (mapcar #'cl-weave:journal-frame-pass steps) :to-equal '(t nil))
      (expect (report-test-contains-p "cycle" text) :to-be t)
      (expect (report-test-contains-p "X 0" text) :to-be t))))

(describe "FR-013 spec report integration"
  (it "collects a failure inside with-soft-assertions and continues the block"
    (let ((continued nil) (detail nil))
      (handler-case
          (cl-weave:with-soft-assertions
            (report-spec-result (report-test-result))
            (setf continued t))
        (assertion-failure (condition)
          (setf detail (cl-weave::failure-detail condition))))
      (expect continued :to-be t)
      (expect (cl-weave::assertion-detail-matcher detail) :to-be :soft-assertions)
      (expect (getf (cl-weave::assertion-detail-actual detail) :failures) :to-be 1)
      (expect (getf (first (getf (cl-weave::assertion-detail-actual detail) :details)) :matcher)
              :to-be :spec))))

(describe "FR-013 spec report rendering"
  (it "renders frame values in each specialized method"
    (let ((step (cl-weave::make-journal-frame :index 0 :kind :spec-step
                                               :form '(inc 2) :actual '(x 2) :pass nil))
          (stats (cl-weave::make-journal-frame :index 1 :kind :spec-stats
                                                :form 'counter :actual '(:states-found 3)
                                                :expected '(:max-states 17) :pass t))
          (history (cl-weave::make-journal-frame :index 2 :kind :spec-history
                                                  :form '(get) :actual 9
                                                  :expected '(:invoked 1 :returned 3 :thread b)
                                                  :pass t)))
      (dolist (part '("inc" "X 2" "fail"))
        (expect (report-test-contains-p part (cl-weave:journal-frame-line step)) :to-be t))
      (dolist (part '("counter" "states-found" "max-states" "17"))
        (expect (report-test-contains-p part (cl-weave:journal-frame-line stats)) :to-be t))
      (dolist (part '("get" "9" "invoked" "returned"))
        (expect (report-test-contains-p part (cl-weave:journal-frame-line history)) :to-be t))))

  (it "writes the trace to a supplied stream"
    (let* ((trace (report-test-trace))
           (rendered (with-output-to-string (stream) (format-spec-trace trace stream))))
      (expect rendered :to-equal (format-spec-trace trace)))))

(describe "FR-013 spec report long traces"
  (it "includes the final safety state and omitted count in the trace and failure message"
    (let* ((trace (loop for i below 50
                        collect (make-trace-step :action (unless (zerop i) 'advance)
                                                 :state (list 'position i))))
           (result (report-test-result :trace trace))
           (message (getf (cl-weave::assertion-detail-actual (report-test-detail result))
                          :condition)))
      (dolist (output (list (format-spec-trace trace) message))
        (expect (report-test-contains-p "POSITION 0" output) :to-be t)
        (expect (report-test-contains-p "POSITION 49" output) :to-be t)
        (expect (report-test-contains-p "30 steps omitted" output) :to-be t))))

  (it "retains the lasso entry and closing state with separate prefix and cycle counts"
    (let* ((prefix (loop for i below 25
                         collect (make-trace-step :action (unless (zerop i) 'advance)
                                                  :state (list 'position i))))
           (cycle (append (loop for i from 25 below 59
                                collect (make-trace-step :action 'advance
                                                         :state (list 'position i)))
                          (list (make-trace-step :action 'return
                                                 :state '(position 24)))))
           (trace (make-lasso :prefix prefix :cycle cycle))
           (output (format-spec-trace trace))
           (cycle-start (search "Cycle:" output :test #'char-equal))
           (prefix-output (subseq output 0 cycle-start))
           (cycle-output (subseq output cycle-start)))
      (expect (report-test-contains-p "POSITION 0" prefix-output) :to-be t)
      (expect (report-test-contains-p "POSITION 24" prefix-output) :to-be t)
      (expect (report-test-contains-p "5 steps omitted" prefix-output) :to-be t)
      (expect (report-test-contains-p "POSITION 25" cycle-output) :to-be t)
      (expect (report-test-contains-p "RETURN" cycle-output) :to-be t)
      (expect (report-test-contains-p "POSITION 24" cycle-output) :to-be t)
      (expect (report-test-contains-p "15 steps omitted" cycle-output) :to-be t))))
