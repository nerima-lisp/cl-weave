(in-package #:cl-weave/test)

(defun run-journaled-test (thunk &key (enabled t))
  "Run THUNK as a one-off test case and return its event, journaling per ENABLED."
  (let ((cl-weave::*journal-enabled* enabled)
        (test (cl-weave::make-test-case
               :name "journal subject"
               :function thunk)))
    (cl-weave::run-test-case (cl-weave::root-suite) test)))

(defun event-journal (event)
  (cl-weave::test-event-journal event))

(defmethod cl-weave:journal-frame-line-for-kind
    ((kind (eql :test-suite-custom-frame-kind)) frame)
  (format nil "custom frame #~D" (cl-weave:journal-frame-index frame)))

(describe "execution journal"
  (it "does not record a timeline unless journaling is enabled"
    (let ((event (run-journaled-test
                  (lambda () (expect 1 :to-be 1))
                  :enabled nil)))
      (expect (cl-weave::test-event-status event) :to-be :pass)
      (expect (event-journal event) :to-be nil)))

  (it "is inactive outside of a journaled attempt"
    (expect (cl-weave::journaling-active-p) :to-be nil))

  (it "records passing matcher assertions when enabled"
    (let* ((event (run-journaled-test (lambda () (expect 1 :to-be 1))))
           (frames (event-journal event)))
      (expect (cl-weave::test-event-status event) :to-be :pass)
      (expect (length frames) :to-be 1)
      (let ((frame (first frames)))
        (expect (cl-weave:journal-frame-index frame) :to-be 0)
        (expect (cl-weave:journal-frame-kind frame) :to-be :assertion)
        (expect (cl-weave:journal-frame-matcher frame) :to-be :to-be)
        (expect (cl-weave:journal-frame-pass frame) :to-be t))))

  (it "records failing assertions before the failure unwinds"
    (let* ((event (run-journaled-test (lambda () (expect 1 :to-be 2))))
           (frames (event-journal event)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (length frames) :to-be 1)
      (expect (cl-weave:journal-frame-pass (first frames)) :to-be nil)))

  (it "records a chronological, index-ordered timeline"
    (let* ((event (run-journaled-test
                   (lambda ()
                     (expect 1 :to-be 1)
                     (expect 2 :to-be 2)
                     (expect 3 :to-be 3))))
           (frames (event-journal event)))
      (expect (length frames) :to-be 3)
      (expect (mapcar #'cl-weave:journal-frame-index frames)
              :to-equal '(0 1 2))
      (expect (every #'cl-weave:journal-frame-pass frames) :to-be t)))

  (it "records smart predicate assertions with their operands"
    (let* ((event (run-journaled-test (lambda () (expect (= 2 2)))))
           (frame (first (event-journal event))))
      (expect (cl-weave::test-event-status event) :to-be :pass)
      (expect (cl-weave:journal-frame-matcher frame) :to-be '=)
      (expect (cl-weave:journal-frame-pass frame) :to-be t)))

  (it "records failing smart predicate assertions"
    (let* ((event (run-journaled-test (lambda () (expect (= 1 2)))))
           (frame (first (event-journal event))))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave:journal-frame-matcher frame) :to-be '=)
      (expect (cl-weave:journal-frame-pass frame) :to-be nil)))

  (it "records truthy assertions"
    (let* ((event (run-journaled-test (lambda () (expect 42))))
           (frame (first (event-journal event))))
      (expect (cl-weave:journal-frame-matcher frame) :to-be :truthy)
      (expect (cl-weave:journal-frame-pass frame) :to-be t))))

(describe "execution journal REPL helpers"
  (it "collects frames from a body via with-execution-journal"
    (let ((frames (cl-weave:with-execution-journal
                    (expect 1 :to-be 1)
                    (expect (= 2 2)))))
      (expect (length frames) :to-be 2)
      (expect (cl-weave:journal-frame-index (first frames)) :to-be 0)
      (expect (cl-weave:journal-frame-index (second frames)) :to-be 1)))

  (it "records labelled notes and returns their value"
    (let* ((result nil)
           (frames (cl-weave:with-execution-journal
                     (setf result (cl-weave:journal-note :total 42)))))
      (expect result :to-be 42)
      (expect (length frames) :to-be 1)
      (let ((frame (first frames)))
        (expect (cl-weave:journal-frame-kind frame) :to-be :note)
        (expect (cl-weave:journal-frame-form frame) :to-be :total)
        (expect (cl-weave:journal-frame-actual frame) :to-be 42))))

  (it "treats journal-note as a transparent no-op when inactive"
    (expect (cl-weave:journal-note :ignored 7) :to-be 7)))

(describe "execution journal spec reporter"
  (it "renders the timeline and replay seed for failed events"
    (let* ((assertion (cl-weave::make-journal-frame
                       :index 0 :kind :assertion
                       :form '(expect total :to-be 3)
                       :matcher :to-be :actual 2 :expected 3 :pass nil))
           (note (cl-weave::make-journal-frame
                  :index 1 :kind :note :form :total :actual 2 :pass t))
           (output (with-output-to-string (stream)
                     (cl-weave::report-spec
                      (list (make-sample-event
                             :status :fail
                             :path '("journal" "spec")
                             :journal (list assertion note)
                             :replay-seed 7))
                      stream))))
      (expect output :to-contain "timeline (2 frames):")
      (expect output :to-contain "#0 assertion")
      (expect output :to-contain "-> FAIL")
      (expect output :to-contain "#1 note :TOTAL = 2")
      (expect output :to-contain "replay seed: 7")))

  (it "omits the timeline and seed for passing events"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-spec
                     (list (make-sample-event
                            :status :pass
                            :path '("journal" "clean")))
                     stream))))
      (expect output :not :to-contain "timeline")
      (expect output :not :to-contain "replay seed"))))

(describe "execution journal mock frames"
  (it "records mock invocations on the timeline"
    (let* ((frames (cl-weave:with-execution-journal
                     (let ((mock (make-mock-function)))
                       (funcall mock 1 2)
                       (expect t :to-be t))))
           (mock-frames (remove-if-not
                         (lambda (frame)
                           (eq (cl-weave:journal-frame-kind frame) :mock-call))
                         frames)))
      (expect (length frames) :to-be 2)
      (expect (length mock-frames) :to-be 1)
      (expect (cl-weave:journal-frame-actual (first mock-frames))
              :to-equal '(1 2))))

  (it "does not record mock calls when journaling is inactive"
    (let ((mock (make-mock-function)))
      (funcall mock :x)
      (expect (cl-weave::journaling-active-p) :to-be nil)))

  (it "renders mock-call frames in the spec reporter"
    (let* ((frame (cl-weave::make-journal-frame
                   :index 0 :kind :mock-call :actual '(1 2) :pass t))
           (output (with-output-to-string (stream)
                     (cl-weave::report-spec
                      (list (make-sample-event
                             :status :fail
                             :path '("mocks" "spec")
                             :journal (list frame)))
                      stream))))
      (expect output :to-contain "#0 mock-call (1 2)"))))

(describe "execution journal hook frames"
  (it "records before-each and after-each hooks around the body"
    (let* ((order '())
           (suite (cl-weave::make-suite
                   :name "root"
                   :before-each (list (lambda () (push :before order)))
                   :after-each (list (lambda () (push :after order)))))
           (test (cl-weave::make-test-case
                  :name "hooked"
                  :function (lambda () (expect t :to-be t))))
           (cl-weave::*journal-enabled* t)
           (event (cl-weave::run-test-case suite test))
           (frames (cl-weave::test-event-journal event)))
      (expect (cl-weave::test-event-status event) :to-be :pass)
      (expect (mapcar #'cl-weave:journal-frame-kind frames)
              :to-equal '(:hook :assertion :hook))
      (expect (cl-weave:journal-frame-form (first frames)) :to-be :before-each)
      (expect (cl-weave:journal-frame-form (third frames)) :to-be :after-each)
      (expect order :to-equal '(:after :before))))

  (it "flags a failing after-each hook on its frame"
    (let* ((suite (cl-weave::make-suite
                   :name "root"
                   :after-each (list (lambda () (error "cleanup boom")))))
           (test (cl-weave::make-test-case
                  :name "hooked"
                  :function (lambda () (expect t :to-be t))))
           (cl-weave::*journal-enabled* t)
           (event (cl-weave::run-test-case suite test))
           (hook-frame (find :hook (cl-weave::test-event-journal event)
                             :key #'cl-weave:journal-frame-kind)))
      (expect (cl-weave:journal-frame-form hook-frame) :to-be :after-each)
      (expect (cl-weave:journal-frame-pass hook-frame) :to-be nil)))

  (it "renders hook frames in the spec reporter"
    (let* ((frame (cl-weave::make-journal-frame
                   :index 0 :kind :hook :form :before-each :pass t))
           (output (with-output-to-string (stream)
                     (cl-weave::report-spec
                      (list (make-sample-event
                             :status :fail
                             :path '("hooks" "spec")
                             :journal (list frame)))
                      stream))))
      (expect output :to-contain "#0 hook before-each -> ok"))))

(describe "execution journal shrink frames"
  (it "records an accepted shrink-step frame for each step down to the minimal case"
    (let* ((generator
             (cl-weave::make-property-generator
              :name :ordered
              :produce #'identity
              :shrink (lambda (value)
                        (case value
                          (3 '(2))
                          (2 '(1))
                          (t nil)))))
           (frames
             (cl-weave:with-execution-journal
               (cl-weave::shrink-property-values
                (list generator)
                '(3)
                (lambda (value)
                  (when (>= value 1) (error "failure: ~S" value)))))))
      (expect (every (lambda (frame)
                       (eq (cl-weave:journal-frame-kind frame) :shrink-step))
                     frames)
              :to-be t)
      (expect (mapcar #'cl-weave:journal-frame-form frames) :to-equal '((2) (1)))
      (expect (mapcar #'cl-weave:journal-frame-expected frames) :to-equal '(0 0))
      (expect (every #'cl-weave:journal-frame-pass frames) :to-be t)))

  (it "records a rejected frame for a candidate that does not reproduce the failure"
    (let* ((generator
             (cl-weave::make-property-generator
              :name :binary
              :produce #'identity
              :shrink (lambda (value)
                        (if (= value 2) '(0 1) nil))))
           (frames
             (cl-weave:with-execution-journal
               (cl-weave::shrink-property-values
                (list generator)
                '(2)
                (lambda (value) (when (>= value 1) (error "failure: ~S" value)))))))
      (expect (mapcar (lambda (frame)
                        (list (cl-weave:journal-frame-form frame)
                              (cl-weave:journal-frame-pass frame)))
                      frames)
              :to-equal '(((0) nil) ((1) t)))))

  (it "does not record shrink frames when journaling is inactive"
    (let ((generator
            (cl-weave::make-property-generator
             :name :ordered
             :produce #'identity
             :shrink (lambda (value) (if (= value 2) '(1) nil)))))
      (cl-weave::shrink-property-values
       (list generator) '(2)
       (lambda (value) (error "failure: ~S" value)))
      (expect (cl-weave::journaling-active-p) :to-be nil)))

  (it "renders shrink-step frames in the spec reporter"
    (let* ((frame (cl-weave::make-journal-frame
                   :index 0 :kind :shrink-step :form '(1) :expected 0 :pass t))
           (output (with-output-to-string (stream)
                     (cl-weave::report-spec
                      (list (make-sample-event
                             :status :fail
                             :path '("shrink" "spec")
                             :journal (list frame)))
                      stream))))
      (expect output :to-contain "#0 shrink-step arg 0 -> (1) accepted"))))

(describe "journal logic queries"
  (it "turns a frame into keyed relation facts, omitting matcher when absent"
    (let* ((assertion (cl-weave::make-journal-frame
                       :index 0 :kind :assertion :form '(expect 1 :to-be 2)
                       :matcher :to-be :actual 1 :expected 2 :pass nil
                       :elapsed-internal-time 5))
           (note (cl-weave::make-journal-frame
                  :index 1 :kind :note :form :total :actual 42 :pass t)))
      (expect (cl-weave:journal-facts (list assertion))
              :to-equal
              '((:frame 0) (:kind 0 :assertion) (:form 0 (expect 1 :to-be 2))
                (:actual 0 1) (:expected 0 2) (:pass 0 nil)
                (:elapsed-internal-time 0 5) (:matcher 0 :to-be)))
      (expect (cl-weave:journal-facts (list note))
              :to-equal
              '((:frame 1) (:kind 1 :note) (:form 1 :total)
                (:actual 1 42) (:expected 1 nil) (:pass 1 t)
                (:elapsed-internal-time 1 nil)))))

  (it "queries a timeline for failing assertions with journal-where"
    (let* ((frames (cl-weave:with-execution-journal
                     (ignore-errors
                      (cl-weave:with-soft-assertions
                        (expect 1 :to-be 1)
                        (expect 2 :to-be 3)
                        (expect (= 4 5)))))))
      (expect (cl-weave:journal-where frames
                (:kind ?index :assertion)
                (:pass ?index nil))
              :to-contain-equal '((?index . 1)))
      (expect (cl-weave:journal-where frames
                (:kind ?index :assertion)
                (:pass ?index nil))
              :to-contain-equal '((?index . 2)))))

  (it "accepts an already-expanded fact program directly"
    (let ((program (cl-weave:journal-facts
                    (cl-weave:with-execution-journal
                      (ignore-errors (expect 1 :to-be 2))))))
      (expect (cl-weave:query-journal program '((:kind ?i :assertion)))
              :to-equal '(((?i . 0))))))

  (it "composes derived rules over the journal to find failing assertions"
    (let* ((frames (cl-weave:with-execution-journal
                     (ignore-errors
                      (cl-weave:with-soft-assertions
                        (expect 1 :to-be 1)
                        (expect 2 :to-be 1)
                        (expect 3 :to-be 1)))))
           (program (append
                     (cl-weave:journal-facts frames)
                     (cl-weave:logic-program
                      (:- (:failed-assertion ?index)
                          (:kind ?index :assertion)
                          (:pass ?index nil))))))
      (expect (cl-weave:journal-where program (:failed-assertion ?index))
              :to-equal '(((?index . 1)) ((?index . 2)))))))

(describe "journal breakpoints"
  (it "matches an integer breakpoint against a frame's index"
    (let ((frame (cl-weave::make-journal-frame :index 2 :kind :assertion :pass t)))
      (expect (cl-weave::journal-breakpoint-match-p 2 frame) :to-be t)
      (expect (cl-weave::journal-breakpoint-match-p 1 frame) :to-be nil)))

  (it "matches a function breakpoint by calling it with the frame"
    (let ((frame (cl-weave::make-journal-frame :index 0 :kind :assertion :pass nil)))
      (expect (cl-weave::journal-breakpoint-match-p
               (lambda (f) (not (cl-weave:journal-frame-pass f)))
               frame)
              :to-be t)))

  (it "normalizes nil, integers, and functions; rejects everything else"
    (expect (cl-weave::normalize-journal-breakpoint nil) :to-be nil)
    (expect (cl-weave::normalize-journal-breakpoint 3) :to-be 3)
    (let ((fn (lambda (frame) (declare (ignore frame)) t)))
      (expect (cl-weave::normalize-journal-breakpoint fn) :to-be fn))
    (signals error (cl-weave::normalize-journal-breakpoint "nope")))

  (it "signals journal-breakpoint-hit with the matched frame when a handler intercepts it"
    (let ((seen nil))
      (handler-bind ((cl-weave:journal-breakpoint-hit
                       (lambda (condition)
                         (setf seen (cl-weave:journal-breakpoint-hit-frame condition))
                         (invoke-restart 'continue))))
        (let* ((cl-weave::*journal-breakpoint* 0)
               (event (run-journaled-test (lambda () (expect 1 :to-be 1)))))
          (expect (cl-weave::test-event-status event) :to-be :pass)
          (expect (cl-weave:journal-frame-index seen) :to-be 0)))))

  (it "never signals when no frame matches the breakpoint"
    (let ((hit nil))
      (handler-bind ((cl-weave:journal-breakpoint-hit
                       (lambda (condition)
                         (declare (ignore condition))
                         (setf hit t)
                         (invoke-restart 'continue))))
        (let ((cl-weave::*journal-breakpoint* 99))
          (run-journaled-test (lambda () (expect 1 :to-be 1))))
        (expect hit :to-be nil))))

  (it "does nothing when *journal-breakpoint* is unbound"
    (let ((hit nil))
      (handler-bind ((cl-weave:journal-breakpoint-hit
                       (lambda (condition)
                         (declare (ignore condition))
                         (setf hit t)
                         (invoke-restart 'continue))))
        (run-journaled-test (lambda () (expect 1 :to-be 1)))
        (expect hit :to-be nil)))))

(describe "journal-diff"
  (it "returns nil for timelines that differ only in timing"
    (let ((a (list (cl-weave::make-journal-frame
                    :index 0 :kind :assertion :form '(expect 1 :to-be 1)
                    :matcher :to-be :actual 1 :expected 1 :pass t
                    :elapsed-internal-time 3)))
          (b (list (cl-weave::make-journal-frame
                    :index 0 :kind :assertion :form '(expect 1 :to-be 1)
                    :matcher :to-be :actual 1 :expected 1 :pass t
                    :elapsed-internal-time 99))))
      (expect (cl-weave:journal-diff a b) :to-be nil)))

  (it "reports the first mismatching frame"
    (let* ((a (list (cl-weave::make-journal-frame :index 0 :kind :assertion :actual 1 :pass t)
                    (cl-weave::make-journal-frame :index 1 :kind :assertion :actual 2 :pass t)))
           (b (list (cl-weave::make-journal-frame :index 0 :kind :assertion :actual 1 :pass t)
                    (cl-weave::make-journal-frame :index 1 :kind :assertion :actual 3 :pass nil)))
           (diff (cl-weave:journal-diff a b)))
      (expect (getf diff :index) :to-be 1)
      (expect (getf diff :reason) :to-be :mismatch)
      (expect (cl-weave:journal-frame-pass (getf diff :a)) :to-be t)
      (expect (cl-weave:journal-frame-pass (getf diff :b)) :to-be nil)))

  (it "reports length divergence when one timeline is shorter"
    (let* ((a (list (cl-weave::make-journal-frame :index 0 :kind :assertion :pass t)))
           (diff (cl-weave:journal-diff a nil)))
      (expect (getf diff :index) :to-be 0)
      (expect (getf diff :reason) :to-be :length)
      (expect (getf diff :b) :to-be nil)))

  (it "finds no divergence between two deterministic runs"
    (let ((a (cl-weave:with-execution-journal (expect 1 :to-be 1) (expect 2 :to-be 2)))
          (b (cl-weave:with-execution-journal (expect 1 :to-be 1) (expect 2 :to-be 2))))
      (expect (cl-weave:journal-diff a b) :to-be nil))))

(describe "explain-journal"
  (it "renders each frame kind on its own line as a string"
    (let* ((frames (list (cl-weave::make-journal-frame
                          :index 0 :kind :hook :form :before-each :pass t)
                         (cl-weave::make-journal-frame
                          :index 1 :kind :mock-call :actual '(42) :pass t)
                         (cl-weave::make-journal-frame
                          :index 2 :kind :assertion :form :truthy :pass nil)
                         (cl-weave::make-journal-frame
                          :index 3 :kind :note :form :total :actual 7 :pass t)))
           (text (cl-weave:explain-journal frames)))
      (expect text :to-contain "#0 hook before-each -> ok")
      (expect text :to-contain "#1 mock-call (42)")
      (expect text :to-contain "#2 assertion :TRUTHY -> FAIL")
      (expect text :to-contain "#3 note :TOTAL = 7")))

  (it "writes to a provided stream and returns no values"
    (let* ((frame (cl-weave::make-journal-frame
                   :index 0 :kind :assertion :form '(expect t :to-be t) :pass t))
           (values nil)
           (output (with-output-to-string (stream)
                     (setf values (multiple-value-list
                                   (cl-weave:explain-journal (list frame) stream))))))
      (expect output :to-contain "#0 assertion")
      (expect values :to-equal nil)))

  (it "returns an empty string for an empty timeline"
    (expect (cl-weave:explain-journal nil) :to-equal "")))

(describe "explain-journal-diff"
  (it "confirms no divergence for a nil diff"
    (expect (cl-weave:explain-journal-diff nil)
            :to-equal "no divergence: both timelines matched"))

  (it "renders a mismatch diff with both frames rendered by journal-frame-line"
    (let* ((a (cl-weave::make-journal-frame
              :index 1 :kind :assertion :form :truthy
              :matcher :to-be :actual 1 :expected 1 :pass t))
           (b (cl-weave::make-journal-frame
              :index 1 :kind :assertion :form :truthy
              :matcher :to-be :actual 2 :expected 1 :pass nil))
           (text (cl-weave:explain-journal-diff
                  (list :index 1 :a a :b b :reason :mismatch))))
      (expect text :to-contain "diverged at frame #1 (mismatch)")
      (expect text :to-contain "a: #1 assertion :TRUTHY -> ok")
      (expect text :to-contain "b: #1 assertion :TRUTHY -> FAIL")))

  (it "renders a missing side as a placeholder on a length divergence"
    (let* ((a (cl-weave::make-journal-frame :index 2 :kind :assertion :pass t))
           (text (cl-weave:explain-journal-diff
                  (list :index 2 :a a :b nil :reason :length))))
      (expect text :to-contain "diverged at frame #2 (length)")
      (expect text :to-contain "a: #2 assertion")
      (expect text :to-contain "b: (no frame recorded")))

  (it "writes to a provided stream and returns no values"
    (let* ((values nil)
           (output (with-output-to-string (stream)
                     (setf values (multiple-value-list
                                   (cl-weave:explain-journal-diff nil stream))))))
      (expect output :to-equal "no divergence: both timelines matched")
      (expect values :to-equal nil))))

(describe "journal frame line extensibility"
  (it "uses the default renderer for kinds without a specialized method"
    (let ((frame (cl-weave::make-journal-frame
                  :index 0 :kind :unspecialized-kind :form :payload :pass t)))
      (expect (cl-weave:journal-frame-line frame)
              :to-equal "#0 unspecialized-kind :PAYLOAD -> ok")))

  (it "dispatches to a user-defined eql-specialized method for a custom kind"
    (let ((frame (cl-weave::make-journal-frame
                  :index 5 :kind :test-suite-custom-frame-kind :pass t)))
      (expect (cl-weave:journal-frame-line frame) :to-equal "custom frame #5")))

  (it "records a custom-kind frame directly through the now-public record-journal-frame"
    (let ((frames (cl-weave:with-execution-journal
                    (cl-weave:record-journal-frame :custom-event :form :hello :pass t))))
      (expect (length frames) :to-be 1)
      (expect (cl-weave:journal-frame-kind (first frames)) :to-be :custom-event)
      (expect (cl-weave:journal-frame-form (first frames)) :to-be :hello)
      (expect (cl-weave:journal-frame-line (first frames))
              :to-equal "#0 custom-event :HELLO -> ok"))))

(describe "execution journal sexp reporter"
  (it "serializes journal frames and the replay seed"
    (let* ((frame (cl-weave::make-journal-frame
                   :index 0 :kind :assertion
                   :form '(expect x :to-be 1)
                   :matcher :to-be :actual 1 :expected 1 :pass t
                   :elapsed-internal-time 5))
           (output (with-output-to-string (stream)
                     (cl-weave::report-sexp
                      (list (make-sample-event
                             :status :pass
                             :path '("journal" "sexp")
                             :journal (list frame)
                             :replay-seed 99))
                      stream))))
      (expect output :to-contain ":TIMELINE")
      (expect output :to-contain ":KIND :ASSERTION")
      (expect output :to-contain ":REPLAY-SEED 99")))

  (it "emits an empty timeline and null seed by default"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-sexp
                     (list (make-sample-event
                            :status :pass
                            :path '("journal" "clean")))
                     stream))))
      (expect output :to-contain ":TIMELINE NIL")
      (expect output :to-contain ":REPLAY-SEED NIL"))))

(describe "journal timeline reconstruction"
  (it "round-trips every slot through serialize then deserialize"
    (let* ((frame (cl-weave::make-journal-frame
                   :index 3 :kind :shrink-step
                   :form '(4) :matcher :to-be :actual 2 :expected 0 :pass t
                   :elapsed-internal-time 17))
           (rebuilt (cl-weave:journal-frame-from-plist
                     (cl-weave::serializable-journal-frame frame))))
      (expect (cl-weave:journal-frame-index rebuilt) :to-be 3)
      (expect (cl-weave:journal-frame-kind rebuilt) :to-be :shrink-step)
      (expect (cl-weave:journal-frame-form rebuilt) :to-equal '(4))
      (expect (cl-weave:journal-frame-matcher rebuilt) :to-be :to-be)
      (expect (cl-weave:journal-frame-actual rebuilt) :to-be 2)
      (expect (cl-weave:journal-frame-expected rebuilt) :to-be 0)
      (expect (cl-weave:journal-frame-pass rebuilt) :to-be t)
      (expect (cl-weave:journal-frame-elapsed-internal-time rebuilt) :to-be 17)))

  (it "defaults missing keys to nil"
    (let ((frame (cl-weave:journal-frame-from-plist '(:index 0 :kind :assertion))))
      (expect (cl-weave:journal-frame-index frame) :to-be 0)
      (expect (cl-weave:journal-frame-kind frame) :to-be :assertion)
      (expect (cl-weave:journal-frame-form frame) :to-be nil)
      (expect (cl-weave:journal-frame-matcher frame) :to-be nil)))

  (it "rejects a malformed odd-length plist"
    (signals error (cl-weave:journal-frame-from-plist '(:index))))

  (it "reconstructs a whole timeline list in order"
    (let ((frames (cl-weave:journal-frames-from-plists
                   '((:index 0 :kind :assertion :pass t)
                     (:index 1 :kind :note :form :total :actual 7 :pass t)))))
      (expect (mapcar #'cl-weave:journal-frame-index frames) :to-equal '(0 1))
      (expect (cl-weave:journal-frame-kind (second frames)) :to-be :note)))

  (it "reads a saved sexp artifact back and analyzes it offline"
    (let* ((a-frame (cl-weave::make-journal-frame
                     :index 0 :kind :assertion :form '(expect total :to-be 3)
                     :matcher :to-be :actual 2 :expected 3 :pass nil))
           (artifact-string
             (with-output-to-string (stream)
               (cl-weave::report-sexp
                (list (make-sample-event
                       :status :fail
                       :path '("math" "adds")
                       :journal (list a-frame)))
                stream)))
           (artifact (read-from-string artifact-string))
           (event (first (getf (rest artifact) :events)))
           (frames (cl-weave:journal-frames-from-plists (getf event :timeline))))
      (expect (length frames) :to-be 1)
      ;; Package-agnostic fragments: READ-FROM-STRING re-interns the form's
      ;; symbols, so ~S may print them package-qualified.
      (expect (cl-weave:explain-journal frames) :to-contain "#0 assertion")
      (expect (cl-weave:explain-journal frames) :to-contain "-> FAIL")
      ;; A rebuilt timeline diffs identically against the live frames it came
      ;; from -- the strong semantic round-trip guarantee.
      (expect (cl-weave:journal-diff frames (list a-frame)) :to-be nil))))

(describe "execution journal JSON reporter"
  (it "emits an empty timeline for events without a journal"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-json
                     (list (make-sample-event
                            :status :pass
                            :path '("journal" "empty")))
                     stream))))
      (expect output :to-contain "\"timeline\":[]")))

  (it "serializes journal frames as timeline entries"
    (let* ((frame (cl-weave::make-journal-frame
                   :index 0
                   :kind :assertion
                   :form '(expect total :to-be 3)
                   :matcher :to-be
                   :actual 2
                   :expected 3
                   :pass nil
                   :elapsed-internal-time 7))
           (output (with-output-to-string (stream)
                     (cl-weave::report-json
                      (list (make-sample-event
                             :status :fail
                             :path '("journal" "timeline")
                             :journal (list frame)))
                      stream))))
      (expect output :to-contain "\"timeline\":[{\"index\":0")
      (expect output :to-contain "\"kind\":\"assertion\"")
      (expect output :to-contain "\"matcher\":\":TO-BE\"")
      (expect output :to-contain "\"pass\":false")
      (expect output :to-contain "\"elapsedInternalTime\":7"))))
