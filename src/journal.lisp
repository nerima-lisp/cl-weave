(in-package #:cl-weave)

;;;; Execution Journal
;;;;
;;;; A chronological "flight recorder" of the observable events inside a
;;;; single test attempt. Today it captures every assertion (both passing
;;;; and failing) together with its source form and runtime operands; later
;;;; layers of the time-travel debugger will append fixture, mock, and
;;;; binding frames onto the same timeline.
;;;;
;;;; Journaling is OFF by default so the hot `expect` path pays nothing: the
;;;; recorder only allocates when *EXECUTION-JOURNAL* is bound to a live
;;;; accumulator, which the runner does per attempt when *JOURNAL-ENABLED*
;;;; is true. Because the toggle rides in *RUNNER-DYNAMIC-ENVIRONMENT-
;;;; VARIABLES*, concurrent worker threads inherit it too.

(defvar *journal-enabled* nil
  "When true, each executed test attempt records an EXECUTION-JOURNAL of the
assertions it runs. Off by default; bind it (or the runner binds it for you)
to opt into time-travel-style timelines in reporters.")

(defvar *execution-journal* nil
  "The accumulator bound per test attempt while journaling is active, else NIL.
Never bind this directly in user code; enable *JOURNAL-ENABLED* instead.")

(defstruct (execution-journal
            (:constructor %make-execution-journal (start-internal-time)))
  "Mutable accumulator gathering JOURNAL-FRAMEs for one test attempt.
Frames are pushed onto FRAMES-REVERSED so recording stays O(1); callers read
them back in chronological order via CURRENT-JOURNAL-FRAMES."
  (start-internal-time 0)
  (count 0 :type fixnum)
  (frames-reversed nil :type list))

(defun make-execution-journal ()
  "Allocate a fresh, empty EXECUTION-JOURNAL stamped with the current clock."
  (%make-execution-journal (get-internal-real-time)))

(define-record-class journal-frame
  (index kind form matcher actual expected pass elapsed-internal-time))

(defun journaling-active-p ()
  "Return true when a live EXECUTION-JOURNAL is collecting frames."
  (not (null *execution-journal*)))

(defvar *journal-breakpoint* nil
  "When bound to an integer JOURNAL-FRAME index or a function of one FRAME
argument, RECORD-JOURNAL-FRAME signals JOURNAL-BREAKPOINT-HIT the instant a
matching frame is recorded -- an interactive time-travel breakpoint. NIL
(default) never breaks, so the hot path pays nothing. Pair with REPLAY-TEST's
:BREAKPOINT argument and JOURNAL-DIFF: diff two timelines to find the
diverging frame index, then rerun with the breakpoint set to that index to
land in a live debugger with the test's dynamic environment -- locals,
closures, call stack -- still intact at the exact point of divergence.")

(define-condition journal-breakpoint-hit (condition)
  ((frame :initarg :frame :reader journal-breakpoint-hit-frame))
  (:documentation
   "Signalled by a matched *JOURNAL-BREAKPOINT*. Left unhandled,
RECORD-JOURNAL-FRAME falls through to a real BREAK, so an interactive session
stops there. Tooling can instead HANDLER-BIND this condition and invoke its
CONTINUE restart to intercept breakpoint hits programmatically -- exactly how
this feature is exercised without a live debugger in tests."))

(defun journal-breakpoint-match-p (breakpoint frame)
  "Return true when FRAME matches BREAKPOINT: an integer JOURNAL-FRAME index,
or a function of one FRAME argument."
  (etypecase breakpoint
    (integer (eql breakpoint (journal-frame-index frame)))
    (function (funcall breakpoint frame))))

(defun normalize-journal-breakpoint (breakpoint)
  (cond
    ((null breakpoint) nil)
    ((or (integerp breakpoint) (functionp breakpoint)) breakpoint)
    (t (error "cl-weave: breakpoint must be NIL, an integer frame index, or a ~
               function of one JOURNAL-FRAME argument, got ~S."
              breakpoint))))

(defun invoke-journal-breakpoint (frame)
  "Signal JOURNAL-BREAKPOINT-HIT for FRAME; fall through to a real BREAK when
nothing handles it and invokes the CONTINUE restart."
  (restart-case
      (signal 'journal-breakpoint-hit :frame frame)
    (continue ()
      :report "Continue past this cl-weave time-travel breakpoint."
      (return-from invoke-journal-breakpoint (values))))
  (break "cl-weave time-travel breakpoint hit:~%  ~A" (journal-frame-line frame)))

(defun record-journal-frame (kind &key form matcher actual expected pass)
  "Append a frame describing a KIND event to the active journal, if any.
Returns the new JOURNAL-FRAME, or NIL when journaling is inactive."
  (let ((journal *execution-journal*))
    (when journal
      (let* ((index (execution-journal-count journal))
             (frame (make-journal-frame
                     :index index
                     :kind kind
                     :form form
                     :matcher matcher
                     :actual actual
                     :expected expected
                     :pass pass
                     :elapsed-internal-time
                     (- (get-internal-real-time)
                        (execution-journal-start-internal-time journal)))))
        (setf (execution-journal-count journal) (the fixnum (1+ index)))
        (push frame (execution-journal-frames-reversed journal))
        (when (and *journal-breakpoint*
                   (journal-breakpoint-match-p *journal-breakpoint* frame))
          (invoke-journal-breakpoint frame))
        frame))))

(defun record-assertion-frame (detail)
  "Record a journal frame from an ASSERTION-DETAIL (matcher-style expects)."
  (when (and *execution-journal* detail)
    (record-journal-frame
     :assertion
     :form (assertion-detail-form detail)
     :matcher (assertion-detail-matcher detail)
     :actual (assertion-detail-actual detail)
     :expected (assertion-detail-expected detail)
     :pass (assertion-detail-pass detail))))

(defun record-smart-assertion-frame (form matcher actual expected pass)
  "Record a journal frame for a smart-predicate/truthy assertion.
ACTUAL carries the operand report list (or the truthy value) and EXPECTED the
original source form, mirroring the failure ASSERTION-DETAIL these produce."
  (when *execution-journal*
    (record-journal-frame
     :assertion
     :form form
     :matcher matcher
     :actual actual
     :expected expected
     :pass pass)))

(defun current-journal-frames ()
  "Return the active journal's frames in chronological order, or NIL."
  (let ((journal *execution-journal*))
    (when journal
      (reverse (execution-journal-frames-reversed journal)))))

(defun journal-note (label value)
  "Record VALUE under LABEL as a :NOTE frame on the active journal, then return
VALUE. A structured, timeline-aware alternative to a debugging print: wrap any
expression with it and the value lands on the time-travel timeline. A no-op
(still returning VALUE) when journaling is inactive."
  (when *execution-journal*
    (record-journal-frame :note :form label :actual value :pass t))
  value)

(defun call-with-execution-journal (thunk)
  "Run THUNK with a fresh execution journal active and return the frames it
recorded, in chronological order. Intended for REPL-driven inspection."
  (let ((*execution-journal* (make-execution-journal)))
    (funcall thunk)
    (current-journal-frames)))

(defmacro with-execution-journal (&body body)
  "Evaluate BODY with journaling active and return the recorded journal frames.
Handy for exploring a sequence of expectations at the REPL:

  (with-execution-journal
    (expect 1 :to-be 1)
    (journal-note :total (+ 1 1)))"
  `(call-with-execution-journal (lambda () ,@body)))

(defun journal-frames-equivalent-p (a b)
  "Return true when two JOURNAL-FRAMEs describe the same behavioural step,
ignoring wall-clock timing. Compares kind, form, matcher, actual, expected, and
pass/fail outcome."
  (and (eq (journal-frame-kind a) (journal-frame-kind b))
       (equal (journal-frame-form a) (journal-frame-form b))
       (eql (journal-frame-matcher a) (journal-frame-matcher b))
       (equal (journal-frame-actual a) (journal-frame-actual b))
       (equal (journal-frame-expected a) (journal-frame-expected b))
       (eq (and (journal-frame-pass a) t)
           (and (journal-frame-pass b) t))))

(defun journal-diff (frames-a frames-b)
  "Compare two journal timelines frame by frame and return a plist describing the
FIRST behavioural divergence, or NIL when the timelines are equivalent. The
result is (:index N :a FRAME-A :b FRAME-B :reason REASON) where REASON is
:mismatch when aligned frames differ, or :length when one timeline ran out of
frames first (the missing side's frame is NIL). Timing is ignored, so this
isolates *what* diverged between two runs of the same test — the root-cause
question behind a flaky failure. Pair it with REPLAY-TEST to run a test twice
and diff the timelines."
  (loop for index from 0
        for a-cell = frames-a then (cdr a-cell)
        for b-cell = frames-b then (cdr b-cell)
        do (cond
             ((and (null a-cell) (null b-cell))
              (return nil))
             ((or (null a-cell) (null b-cell))
              (return (list :index index
                            :a (car a-cell)
                            :b (car b-cell)
                            :reason :length)))
             ((not (journal-frames-equivalent-p (car a-cell) (car b-cell)))
              (return (list :index index
                            :a (car a-cell)
                            :b (car b-cell)
                            :reason :mismatch))))))

(defgeneric journal-frame-line-for-kind (kind frame)
  (:documentation
   "Render FRAME, whose kind is the eql-specialized KIND, as one human-readable
line. JOURNAL-FRAME-LINE dispatches here, so recording your own frame kind
through RECORD-JOURNAL-FRAME -- for domain events beyond the built-in
:assertion, :mock-call, :hook, :shrink-step, and :note -- is a two-step
extension: call RECORD-JOURNAL-FRAME with your keyword, then DEFMETHOD an
EQL-specialized renderer for it. Unspecialized kinds fall through to the
default method below, so extending never requires modifying cl-weave.")
  (:method (kind frame)
    (format nil "#~D ~(~A~) ~S -> ~:[FAIL~;ok~]"
            (journal-frame-index frame)
            kind
            (journal-frame-form frame)
            (journal-frame-pass frame))))

(defmethod journal-frame-line-for-kind ((kind (eql :note)) frame)
  (format nil "#~D note ~S = ~S"
          (journal-frame-index frame)
          (journal-frame-form frame)
          (journal-frame-actual frame)))

(defmethod journal-frame-line-for-kind ((kind (eql :mock-call)) frame)
  (format nil "#~D mock-call ~S"
          (journal-frame-index frame)
          (journal-frame-actual frame)))

(defmethod journal-frame-line-for-kind ((kind (eql :hook)) frame)
  (format nil "#~D hook ~(~A~) -> ~:[FAIL~;ok~]"
          (journal-frame-index frame)
          (journal-frame-form frame)
          (journal-frame-pass frame)))

(defmethod journal-frame-line-for-kind ((kind (eql :shrink-step)) frame)
  (format nil "#~D shrink-step arg ~D -> ~S ~:[rejected~;accepted~]"
          (journal-frame-index frame)
          (journal-frame-expected frame)
          (journal-frame-form frame)
          (journal-frame-pass frame)))

(defun journal-frame-line (frame)
  "Return a one-line human-readable description of FRAME. Shared by the spec
reporter and EXPLAIN-JOURNAL so terminal and REPL output stay identical.
Dispatches on FRAME's kind through JOURNAL-FRAME-LINE-FOR-KIND."
  (journal-frame-line-for-kind (journal-frame-kind frame) frame))

(defun explain-journal (frames &optional (stream nil stream-supplied-p))
  "Render the timeline FRAMES as human-readable text, one line per frame.
Returns a string when STREAM is omitted; otherwise writes to STREAM and returns
no values. Handy for printing REPLAY-TEST output or inspecting a JOURNAL-DIFF at
the REPL."
  (flet ((emit (out)
           (loop for frame in frames
                 for first = t then nil
                 do (unless first (terpri out))
                    (write-string (journal-frame-line frame) out))))
    (if stream-supplied-p
        (progn (emit stream) (values))
        (with-output-to-string (out) (emit out)))))

(defun journal-diff-side-line (label frame)
  (if frame
      (format nil "~A: ~A" label (journal-frame-line frame))
      (format nil "~A: (no frame recorded -- this run's timeline ended first)"
              label)))

(defun explain-journal-diff (diff &optional (stream nil stream-supplied-p))
  "Render a JOURNAL-DIFF result as human-readable text. Returns a string when
STREAM is omitted; otherwise writes to STREAM and returns no values. A NIL
DIFF (the timelines matched) renders as a one-line confirmation; otherwise
prints the divergence index and reason, then both sides via JOURNAL-FRAME-LINE
-- the same terminal-friendly rendering EXPLAIN-JOURNAL and the spec reporter
already share, extended to a divergence's two frames. Handy for turning a
flaky test's root cause into copy-pasteable output at the REPL or in CI logs."
  (flet ((emit (out)
           (if (null diff)
               (write-string "no divergence: both timelines matched" out)
               (progn
                 (format out "diverged at frame #~D (~(~A~))~%"
                         (getf diff :index) (getf diff :reason))
                 (write-string (journal-diff-side-line "  a" (getf diff :a)) out)
                 (terpri out)
                 (write-string (journal-diff-side-line "  b" (getf diff :b)) out)))))
    (if stream-supplied-p
        (progn (emit stream) (values))
        (with-output-to-string (out) (emit out)))))

;;;; Rehydrating a saved timeline
;;;;
;;;; The sexp reporter emits each frame as a readable plist (see
;;;; SERIALIZABLE-JOURNAL-FRAME in reporter-results.lisp), and the whole
;;;; results artifact is one READ-able Lisp form. These inverses rebuild
;;;; JOURNAL-FRAME objects from that data, so a timeline captured in CI can be
;;;; read back on a developer's machine and handed to the same offline analysis
;;;; tools that work on a live run -- EXPLAIN-JOURNAL, JOURNAL-DIFF,
;;;; EXPLAIN-JOURNAL-DIFF, and JOURNAL-WHERE. Homoiconicity closes the loop for
;;;; free: no bespoke parser, just READ plus this reconstruction.

(defun journal-frame-from-plist (plist)
  "Reconstruct a JOURNAL-FRAME from PLIST, the exact inverse of the sexp
reporter's SERIALIZABLE-JOURNAL-FRAME. Missing keys default to NIL, matching
MAKE-JOURNAL-FRAME. Signals an error when PLIST is not an even-length property
list. This is the entry point for offline time-travel analysis: READ a saved
sexp results artifact, navigate to an event's :TIMELINE, and rebuild its frames
here to feed EXPLAIN-JOURNAL, JOURNAL-DIFF, or JOURNAL-WHERE."
  (unless (and (listp plist) (evenp (length plist)))
    (error "cl-weave: journal frame plist must be an even-length property list, got ~S."
           plist))
  (make-journal-frame
   :index (getf plist :index)
   :kind (getf plist :kind)
   :form (getf plist :form)
   :matcher (getf plist :matcher)
   :actual (getf plist :actual)
   :expected (getf plist :expected)
   :pass (getf plist :pass)
   :elapsed-internal-time (getf plist :elapsed-internal-time)))

(defun journal-frames-from-plists (plists)
  "Reconstruct a whole timeline by applying JOURNAL-FRAME-FROM-PLIST to each
element of PLISTS -- typically the :TIMELINE list read back from a sexp results
artifact. Returns the frames in their recorded order."
  (mapcar #'journal-frame-from-plist plists))
