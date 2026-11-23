(in-package #:cl-weave/spec-test)

;;;; Self-verification of the watch cycle (FR-014).
;;;;
;;;; The abstract specification WATCH-CYCLE describes one pass of the loop in
;;;; WATCH-SYSTEM (src/watch.lisp): detect changes against the previous file
;;;; state, reload, rerun, and merge the file state for the next pass. The
;;;; four-file universe is a model, not the real file set:
;;;;
;;;;   SRC  an implementation file, not a registered test file
;;;;   TST  a registered test file
;;;;   ASD  the ASDF definition file; editing it makes the next reload full
;;;;   NEW  a file the ASDF graph only contains once ASD has been reloaded
;;;;        at version 1 or later (a component added to the system)
;;;;
;;;; A file signature is abstracted to a version number: an edit bumps it. DISK
;;;; holds the current version of every file, LOADED the version the registered
;;;; tests were last reloaded from (-1: never), SNAP the signature the cycle
;;;; detected, and STATE the previous file state the loop carries over.

(defparameter *wm-universe* '(src tst asd new))

(defparameter *wm-core-files* '(src tst asd)
  "The files the ASDF graph contains from the start.")

(defun wm-ver (alist file)
  (cdr (assoc file alist)))

(defun wm-initial-disk ()
  (mapcar (lambda (file) (cons file 0)) *wm-universe*))

(defun wm-initial-loaded ()
  (mapcar (lambda (file) (cons file -1)) *wm-universe*))

(defun wm-bump (alist file)
  (mapcar (lambda (entry)
            (if (eq (car entry) file) (cons file (1+ (cdr entry))) entry))
          alist))

(defun wm-snapshot (disk files)
  (mapcar (lambda (file) (cons file (wm-ver disk file))) files))

(defun wm-changed (old new)
  "Files whose signature differs between OLD and NEW, in universe order. A NIL
OLD is the first pass: every file counts as changed."
  (if (null old)
      (mapcar #'car new)
      (remove-if-not (lambda (file)
                       (let ((before (assoc file old)) (after (assoc file new)))
                         (and (or before after) (not (equal before after)))))
                     *wm-universe*)))

(defun wm-detect (state disk files)
  (wm-changed state (wm-snapshot disk files)))

(defun wm-scope (state changed)
  (if (and state changed (every (lambda (file) (eq file 'tst)) changed))
      :changed-tests
      :full-suite))

(defun wm-reload-kind (state changed bug)
  (cond ((null state) :full)
        ((eq bug :incremental-asd) :incremental)
        ((member 'asd changed) :full)
        (t :incremental)))

(defun wm-graph-files (asd-version)
  (if (>= asd-version 1) '(src tst asd new) '(src tst asd)))

(defun wm-reload (loaded disk kind changed)
  (let ((targets (if (eq kind :full)
                     (wm-graph-files (wm-ver disk 'asd))
                     changed)))
    (mapcar (lambda (entry)
              (if (member (car entry) targets)
                  (cons (car entry) (wm-ver disk (car entry)))
                  entry))
            loaded)))

(defun wm-merge (snap refreshed)
  "MERGE-REFRESHED-WATCH-STATE: keep the pre-run signature of a file the cycle
already watched, take the refreshed one for a file the reload added."
  (mapcar (lambda (entry)
            (cons (car entry)
                  (if (assoc (car entry) snap) (wm-ver snap (car entry)) (cdr entry))))
          refreshed))

(defun wm-stale-p (disk loaded)
  (some (lambda (file) (/= (wm-ver disk file) (wm-ver loaded file)))
        *wm-core-files*))

(defun wm-terminal-p (phase)
  (and (member phase '(:done :stopped :aborted)) t))

;;; BUG selects a deliberately broken variant; NIL is the specification. Each
;;; broken variant breaks exactly one property (see the tests below).
(defspec watch-cycle ((once nil) (bug nil) (max-edits 2) (reload-can-fail t))
  (:variables disk files state phase snap changed scope kind result loaded edits)
  (:init (disk (wm-initial-disk))
         (files (list 'src 'tst 'asd))
         (state nil)
         (phase :idle)
         (snap nil)
         (changed nil)
         (scope nil)
         (kind nil)
         (result nil)
         (loaded (wm-initial-loaded))
         (edits 0))
  ;; The environment edits a file at any point of a live watcher.
  (:action edit
    (:for (file (list 'src 'tst 'asd 'new)))
    (:guard (and (< edits max-edits) (not (wm-terminal-p phase))))
    (:next (disk (wm-bump disk file))
           (edits (1+ edits))))
  ;; A pass that finds no change runs nothing and keeps all state.
  (:action detect-idle
    (:guard (and (eq phase :idle)
                 state
                 (null (wm-detect state disk files)))))
  (:action detect
    (:guard (and (eq phase :idle)
                 (or (null state)
                     (wm-detect state disk files)
                     (eq bug :rerun-unchanged))))
    (:next (phase :detected)
           (snap (wm-snapshot disk files))
           (changed (wm-detect state disk files))
           (scope (wm-scope state (wm-detect state disk files)))
           (kind nil)
           (result nil))
    (:output (null state)))
  ;; A failed reload ends the loop with the error: nothing runs, state stays.
  (:action reload
    (:for (outcome (if reload-can-fail (list :ok :fail) (list :ok))))
    (:guard (eq phase :detected))
    (:next (phase (cond ((eq outcome :ok) :reloaded)
                        ((eq bug :run-after-failed-reload) :reloaded)
                        (t :aborted)))
           (kind (wm-reload-kind state changed bug))
           (loaded (if (and (eq outcome :ok) (not (eq bug :skip-reload)))
                       (wm-reload loaded disk (wm-reload-kind state changed bug) changed)
                       loaded)))
    ;; The reload kind and, for an incremental reload, the exact changed set.
    (:output (list (next kind) (if (eq (next kind) :incremental) changed nil))))
  (:action run
    (:for (outcome (list :pass :fail)))
    (:guard (eq phase :reloaded))
    (:next (phase :ran)
           (result outcome))
    ;; The scope handed to RUN-ALL: a location filter, never a test-path filter.
    (:output (list scope (if (eq scope :changed-tests) changed nil) nil)))
  ;; REFRESH-WATCH-STATE and MERGE-REFRESHED-WATCH-STATE: re-read the watched
  ;; file set from the reloaded ASDF graph, then fold the pre-run state over it.
  (:action merge-state
    (:guard (and (eq phase :ran)
                 (not once)
                 (not (and (eq bug :stop-on-failure) (eq result :fail)))))
    (:next (files (wm-graph-files (wm-ver loaded 'asd)))
           (state (let ((refreshed (wm-snapshot disk (wm-graph-files (wm-ver loaded 'asd)))))
                    (if (eq bug :merge-refreshed) refreshed (wm-merge snap refreshed))))
           (phase :idle)
           (snap nil)
           (changed nil)
           (scope nil)
           (kind nil)
           (result nil)))
  ;; The final (ONCE) pass: success returns T, failure stops. STATE is dead
  ;; after the loop returns, so the abstract state keeps it unchanged.
  (:action finish
    (:guard (and (eq phase :ran)
                 (or once (and (eq bug :stop-on-failure) (eq result :fail)))))
    (:next (phase (if (eq result :pass) :done :stopped))))

  (:invariant run-follows-detected-change
    (or (not (member phase '(:detected :reloaded :ran))) (not (null changed))))
  (:invariant changed-is-snapshot-diff
    (or (eq phase :idle) (equal changed (wm-changed state snap))))
  (:invariant selective-rerun-only-for-test-files
    (or (not (eq scope :changed-tests))
        (and state changed (every (lambda (file) (eq file 'tst)) changed))))
  (:invariant rerun-uses-reloaded-code
    (or (not (eq phase :ran))
        (every (lambda (file) (>= (wm-ver loaded file) (wm-ver snap file))) changed)))
  (:invariant reload-kind-matches-change
    (or (null kind)
        (eq kind (if (or (null state) (member 'asd changed)) :full :incremental))))
  (:invariant state-not-ahead-of-loaded
    (every (lambda (entry)
             (or (not (member (car entry) *wm-core-files*))
                 (<= (cdr entry) (wm-ver loaded (car entry)))))
           state))
  (:invariant merged-state-covers-watched-files
    (or (null state) (not (eq phase :idle)) (equal (mapcar #'car state) files)))
  (:invariant terminal-phases-only-in-once-mode
    (or once (not (member phase '(:done :stopped)))))

  (:action-property cycle-order
    (or (eq phase (next phase))
        (member (next phase)
                (case phase
                  (:idle '(:detected))
                  (:detected '(:reloaded :aborted))
                  (:reloaded '(:ran))
                  (:ran '(:idle :done :stopped))))))
  (:action-property watcher-state-advances-only-at-cycle-end
    (or (and (equal state (next state)) (equal files (next files)))
        (and (eq phase :ran) (eq (next phase) :idle))))
  (:action-property loaded-changes-only-at-reload
    (or (equal loaded (next loaded))
        (and (eq phase :detected) (eq (next phase) :reloaded))))

  (:temporal edits-eventually-loaded
    (:leads-to (wm-stale-p disk loaded) (not (wm-stale-p disk loaded))))
  (:temporal watch-converges
    (:eventually-always (not (wm-stale-p disk loaded))))
  (:temporal once-terminates
    (:eventually (wm-terminal-p phase)))
  (:fairness (:weak detect reload run merge-state finish))
  (:deadlock-check nil))

;;;; ------------------------------------------------------------------
;;;; Harness: the real WATCH-SYSTEM loop driven from outside.
;;;;
;;;; The loop keeps its state in local variables and has no step API, so each
;;;; SUT operation appends to a script and replays the whole script from a fresh
;;;; WATCH-SYSTEM call. Nothing depends on time or the file system:
;;;;
;;;;   * FILE-STATE and WATCHED-SYSTEM-FILES read a fake disk and a fake ASDF
;;;;     graph held in the replay environment;
;;;;   * the two atomic reloads and RUN-ALL are replaced, so RUN-SYSTEM's own
;;;;     choice between a full and an incremental reload is the real one;
;;;;   * WATCH-SLEEP does nothing;
;;;;   * WATCH-CYCLE-PLAN and REFRESH-WATCH-STATE are wrapped, not replaced: the
;;;;     wrapper records the arguments and results of the real function.
;;;;
;;;; Every hook first applies the scripted edits that precede it, then consumes
;;;; the scripted operation it stands for (a different next operation is a
;;;; mismatch and stops the replay), and after its effect stops the replay
;;;; when the script is exhausted. The abstraction function reads only what the
;;;; hooks observed, never the script.

(defparameter *wm-paths*
  (mapcar (lambda (file)
            (cons file (pathname (if (eq file 'asd)
                                     "/watch-model/model.asd"
                                     (format nil "/watch-model/~(~A~).lisp" file)))))
          *wm-universe*))

(defun wm-path (file)
  (cdr (assoc file *wm-paths*)))

(defun wm-file-of (path)
  (car (rassoc path *wm-paths* :test #'equal)))

(defun wm-sort-files (files)
  (remove-if-not (lambda (file) (member file files)) *wm-universe*))

(defun wm-files-from-paths (paths)
  (wm-sort-files (mapcar #'wm-file-of paths)))

(defun wm-state-from-alist (alist)
  (loop for file in *wm-universe*
        for entry = (find file alist :key (lambda (e) (wm-file-of (car e))))
        when entry collect (cons file (cdr entry))))

(define-condition wm-reload-failure (error) ())

(defstruct (wm-env (:conc-name we-))
  pending disk loaded (edits 0)
  (files-obs (list 'src 'tst 'asd)) state-obs snap-obs changed-obs scope-obs
  kind-obs result-obs initialp-obs reload-paths run-args last-event
  returned return-value mismatch aborted in-refresh
  (run-count 0) (reload-count 0))

(defun wm-drain (env)
  (loop while (eq (car (first (we-pending env))) :edit)
        do (let ((op (pop (we-pending env))))
             (setf (we-disk env) (wm-bump (we-disk env) (second op)))
             (incf (we-edits env)))))

(defun wm-take (env &rest kinds)
  (let ((op (first (we-pending env))))
    (cond ((and op (member (first op) kinds)) (pop (we-pending env)))
          (t (setf (we-mismatch env) (list kinds op))
             (throw 'wm-stop nil)))))

(defun wm-checkpoint (env)
  (wm-drain env)
  (unless (we-pending env)
    (throw 'wm-stop nil)))

(defun wm-on-reload (env kind paths)
  (wm-drain env)
  (let ((op (wm-take env :reload)))
    (incf (we-reload-count env))
    (setf (we-kind-obs env) kind
          (we-reload-paths env) paths
          (we-last-event env) :reload)
    (when (eq (second op) :fail)
      (error 'wm-reload-failure))
    (setf (we-loaded env)
          (wm-reload (we-loaded env) (we-disk env) kind (mapcar #'wm-file-of paths)))
    (wm-checkpoint env)
    t))

(defun wm-mocks (env defect)
  (let ((original-plan (symbol-function 'cl-weave::watch-cycle-plan))
        (original-refresh (symbol-function 'cl-weave::refresh-watch-state)))
    (append
     (list
      (cons 'cl-weave::watched-system-files
            (lambda (system &key include-dependencies)
              (declare (ignore system include-dependencies))
              (mapcar #'wm-path (wm-graph-files (wm-ver (we-loaded env) 'asd)))))
      (cons 'cl-weave::file-state
            (lambda (pathnames)
              (unless (we-in-refresh env)
                (wm-drain env)
                (wm-take env :detect :detect-idle)
                (setf (we-files-obs env) (wm-files-from-paths pathnames)))
              (mapcar (lambda (path)
                        (cons path (wm-ver (we-disk env) (wm-file-of path))))
                      pathnames)))
      (cons 'cl-weave::watch-cycle-plan
            (lambda (state new-state)
              (let ((plan (funcall original-plan state new-state)))
                (setf (we-state-obs env) (wm-state-from-alist state)
                      (we-snap-obs env) (wm-state-from-alist (getf plan :new-state))
                      (we-changed-obs env) (wm-files-from-paths (getf plan :changed))
                      (we-scope-obs env) (getf plan :scope)
                      (we-initialp-obs env) (getf plan :initialp)
                      (we-kind-obs env) nil
                      (we-result-obs env) nil
                      (we-last-event env) :plan)
                (wm-checkpoint env)
                plan)))
      (cons 'cl-weave::atomic-full-system-reload
            (lambda (system)
              (declare (ignore system))
              (wm-on-reload env :full nil)))
      (cons 'cl-weave::atomic-incremental-system-reload
            (lambda (system changed-pathnames)
              (declare (ignore system))
              (wm-on-reload env :incremental changed-pathnames)))
      (cons 'cl-weave:run-all
            (lambda (&rest arguments)
              (wm-drain env)
              (let ((op (wm-take env :run)))
                (incf (we-run-count env))
                (setf (we-result-obs env) (second op)
                      (we-run-args env) (list (getf arguments :location-filter)
                                              (getf arguments :test-path-filter))
                      (we-last-event env) :run)
                (wm-checkpoint env)
                (eq (second op) :pass))))
      (cons 'cl-weave::refresh-watch-state
            (lambda (system include-dependencies next-state)
              (wm-drain env)
              (wm-take env :merge-state)
              (setf (we-in-refresh env) t)
              (multiple-value-bind (files merged)
                  (unwind-protect
                       (funcall original-refresh system include-dependencies next-state)
                    (setf (we-in-refresh env) nil))
                (setf (we-files-obs env) (wm-files-from-paths files)
                      (we-state-obs env) (wm-state-from-alist merged)
                      (we-last-event env) :refresh)
                (wm-checkpoint env)
                (values files merged))))
      (cons 'cl-weave::watch-sleep
            (lambda (seconds) (declare (ignore seconds)) nil)))
     ;; DEFECT injects exactly one bug into the real code, to prove the
     ;; conformance check can fail.
     (ecase defect
       ((nil) nil)
       (:merge-takes-refreshed
        (list (cons 'cl-weave::merge-refreshed-watch-state
                    (lambda (next-state refreshed-state)
                      (declare (ignore next-state))
                      refreshed-state))))
       (:asd-treated-as-source
        (list (cons 'cl-weave::asdf-definition-pathname-p
                    (lambda (pathname) (declare (ignore pathname)) nil))))
       (:stop-on-failed-run
        (list (cons 'cl-weave::call-with-watch-run-attempt/k
                    (lambda (succeededp once new-state on-continue on-stop)
                      (declare (ignore once))
                      (if succeededp
                          (funcall on-continue new-state)
                          (funcall on-stop))))))))))

(defun wm-call-with-mocks (mocks thunk)
  (let ((saved (mapcar (lambda (mock) (cons (car mock) (symbol-function (car mock))))
                       mocks)))
    (unwind-protect
         (progn (dolist (mock mocks)
                  (setf (symbol-function (car mock)) (cdr mock)))
                (funcall thunk))
      (dolist (entry saved)
        (setf (symbol-function (car entry)) (cdr entry))))))

(defun wm-drive (env once defect)
  ;; The registry holds one registered test in TST, so a change confined to TST
  ;; narrows the rerun. The index caches are rebound so the live registry of
  ;; the running test session is neither read nor cached.
  (let ((root (cl-weave::make-suite :name "root")))
    (cl-weave::add-child
     root
     (cl-weave::make-test-case :name "registered"
                               :location (list :file (namestring (wm-path 'tst)))
                               :function (lambda () t)))
    (let ((cl-weave::*root-suite* root)
          (cl-weave::*watch-test-dependency-index* nil)
          (cl-weave::*watch-registered-test-files* nil)
          (cl-weave::*watch-index-suite* nil)
          (cl-weave::*watch-index-generation* -1))
      (wm-call-with-mocks
       (wm-mocks env defect)
       (lambda ()
         (catch 'wm-stop
           (handler-case
               (let ((value (cl-weave:watch-system "wm-system"
                                                   :stream (make-broadcast-stream)
                                                   :status-stream (make-broadcast-stream)
                                                   :once once)))
                 (setf (we-returned env) t
                       (we-return-value env) value)
                 (if (equal (we-pending env) '((:finish)))
                     (pop (we-pending env))
                     (setf (we-mismatch env) (list :return (we-pending env)))))
             (wm-reload-failure ()
               (setf (we-aborted env) t)))))))))

(defun wm-replay (ops once defect)
  (let ((env (make-wm-env :pending (reverse ops)
                          :disk (wm-initial-disk)
                          :loaded (wm-initial-loaded))))
    (wm-drain env)
    (when (we-pending env)
      (wm-drive env once defect))
    env))

(defun wm-observation (env)
  (let* ((phase (cond ((we-mismatch env) :mismatch)
                      ((we-aborted env) :aborted)
                      ((we-returned env) (if (we-return-value env) :done :stopped))
                      (t (ecase (we-last-event env)
                           ((nil :refresh) :idle)
                           (:plan (if (we-changed-obs env) :detected :idle))
                           (:reload :reloaded)
                           (:run :ran)))))
         (cycle-p (member phase '(:detected :reloaded :ran :aborted :done :stopped))))
    (list 'disk (we-disk env)
          'files (we-files-obs env)
          'state (we-state-obs env)
          'phase phase
          'snap (and cycle-p (we-snap-obs env))
          'changed (and cycle-p (we-changed-obs env))
          'scope (and cycle-p (we-scope-obs env))
          'kind (and cycle-p (we-kind-obs env))
          'result (and cycle-p (we-result-obs env))
          'loaded (we-loaded env)
          'edits (we-edits env))))

(defstruct (wm-sut (:constructor %make-wm-sut (once defect)))
  once defect (ops nil) env)

(defun wm-new-sut (&key once defect)
  (let ((sut (%make-wm-sut once defect)))
    (setf (wm-sut-env sut) (wm-replay nil once defect))
    sut))

(defun wm-step (sut op)
  (push op (wm-sut-ops sut))
  (setf (wm-sut-env sut)
        (wm-replay (wm-sut-ops sut) (wm-sut-once sut) (wm-sut-defect sut)))
  (wm-sut-env sut))

(defun wm-abstraction (sut)
  (wm-observation (wm-sut-env sut)))

(defun wm-operations ()
  (list (cons 'edit (lambda (sut file) (wm-step sut (list :edit file)) nil))
        (cons 'detect (lambda (sut)
                        (we-initialp-obs (wm-step sut (list :detect)))))
        (cons 'detect-idle (lambda (sut) (wm-step sut (list :detect-idle)) nil))
        (cons 'reload (lambda (sut outcome)
                        (let ((env (wm-step sut (list :reload outcome))))
                          (list (we-kind-obs env)
                                (and (eq (we-kind-obs env) :incremental)
                                     (wm-files-from-paths (we-reload-paths env)))))))
        (cons 'run (lambda (sut outcome)
                     (let* ((env (wm-step sut (list :run outcome)))
                            (arguments (we-run-args env)))
                       (list (if (first arguments) :changed-tests :full-suite)
                             (wm-files-from-paths (first arguments))
                             (second arguments)))))
        (cons 'merge-state (lambda (sut) (wm-step sut (list :merge-state)) nil))
        (cons 'finish (lambda (sut) (wm-step sut (list :finish)) nil))))

(defun wm-conformance (spec &rest keys &key once defect &allow-other-keys)
  (let ((rest (loop for (key value) on keys by #'cddr
                    unless (member key '(:once :defect)) append (list key value))))
    (apply #'check-sequential-conformance spec
           :reset (lambda () (wm-new-sut :once once :defect defect))
           :operations (wm-operations)
           :abstraction #'wm-abstraction
           rest)))

(defun wm-run-script (spec calls &key once defect)
  "Run CALLS, a list of (ACTION . PARAMS), through SPEC and the real loop.
Return (values spec-states observed-states spec-outputs observed-outputs sut)."
  (multiple-value-bind (trace valid-p failed-index)
      (replay-action-sequence spec (first (spec-initial-states spec)) calls)
    (unless valid-p
      (error "Script step ~D is not enabled in the specification." failed-index))
    (let ((sut (wm-new-sut :once once :defect defect))
          (operations (wm-operations))
          (observed (list)) (observed-outputs (list)) (expected-outputs (list)))
      (loop for call in calls
            for (previous step) on trace
            for action = (spec-find-action spec (car call))
            do (push (apply (cdr (assoc (car call) operations)) sut (cdr call))
                     observed-outputs)
               (push (and (spec-action-output action)
                          (apply (spec-action-output action)
                                 (trace-step-state previous) (trace-step-state step)
                                 (cdr call)))
                     expected-outputs)
               (push (make-state spec (wm-abstraction sut)) observed))
      (values (mapcar #'trace-step-state (rest trace)) (nreverse observed)
              (nreverse expected-outputs) (nreverse observed-outputs) sut))))

(defun wm-final (states variable)
  (state-ref (car (last states)) variable))

;;;; ------------------------------------------------------------------
;;;; Helpers for the checks below.

(defun wm-explore (spec &rest keys)
  (apply #'explore-spec spec :temporal nil :max-states 100000 keys))

(defun wm-wipe-invariants (spec)
  "SPEC without invariants, so a temporal property is the first thing to fail."
  (make-spec :name (spec-name spec) :constants (spec-constants spec)
             :variables (spec-variables spec) :init (spec-init spec)
             :actions (spec-actions spec)
             :temporal-properties (spec-temporal-properties spec)
             :fairness-conditions (spec-fairness-conditions spec)
             :check-deadlock nil))

(defun wm-without-fairness (spec)
  (make-spec :name (spec-name spec) :constants (spec-constants spec)
             :variables (spec-variables spec) :init (spec-init spec)
             :actions (spec-actions spec) :invariants (spec-invariants spec)
             :temporal-properties (spec-temporal-properties spec)
             :check-deadlock nil))

(defun wm-trace-actions (violation)
  (mapcar (lambda (step) (cons (trace-step-action step) (trace-step-params step)))
          (spec-violation-trace violation)))

(defun wm-expect-violation (result property kind length)
  (let ((violation (spec-result-violation result)))
    (expect (spec-result-passed-p result) :to-be nil)
    (expect (not (null violation)) :to-be t)
    (expect (spec-violation-property violation) :to-be property)
    (expect (spec-violation-kind violation) :to-be kind)
    (expect (length (spec-violation-trace violation)) :to-be length)
    violation))

;;;; ------------------------------------------------------------------
;;;; 1. Exhaustive check of the abstract specification.

(describe "watch cycle specification"
  (it-spec "keeps every safety property while watching continuously"
    (explore-spec (watch-cycle :max-edits 3) :temporal nil :max-states 100000))
  (it-spec "keeps every safety property in the final (once) pass"
    (explore-spec (watch-cycle :once t :max-edits 3) :temporal nil :max-states 100000))
  (it-spec "reloads every edit of a watched file once the edits stop"
    (explore-spec (watch-cycle :reload-can-fail nil)
                  :temporal '(edits-eventually-loaded watch-converges)
                  :max-states 100000))
  (it-spec "ends the final pass, whether the run passes, fails or the reload fails"
    (explore-spec (watch-cycle :once t)
                  :temporal '(once-terminates) :max-states 100000))

  (it "reaches the hand-counted states when no edit is possible"
    ;; Continuous: init, detected, aborted, reloaded, ran-pass, ran-fail and
    ;; the idle state after the merge. Once: the merge becomes a finish, which
    ;; adds done and stopped and drops the idle state.
    (let ((watching (wm-explore (watch-cycle :max-edits 0)))
          (once (wm-explore (watch-cycle :once t :max-edits 0))))
      (expect (spec-result-states-found watching) :to-be 7)
      (expect (spec-result-depth-reached watching) :to-be 4)
      (expect (spec-result-truncated watching) :to-be nil)
      (expect (spec-result-states-found once) :to-be 8)
      (expect (spec-result-depth-reached once) :to-be 4)
      (expect (spec-result-truncated once) :to-be nil)))
  (it "checks every declared invariant, action property and the requested liveness"
    (let ((result (explore-spec (watch-cycle :reload-can-fail nil :max-edits 1)
                                :temporal '(watch-converges) :max-states 100000)))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-checked-properties result)
              :to-equal '(run-follows-detected-change changed-is-snapshot-diff
                          selective-rerun-only-for-test-files rerun-uses-reloaded-code
                          reload-kind-matches-change state-not-ahead-of-loaded
                          merged-state-covers-watched-files
                          terminal-phases-only-in-once-mode
                          cycle-order watcher-state-advances-only-at-cycle-end
                          loaded-changes-only-at-reload watch-converges)))))

;;;; ------------------------------------------------------------------
;;;; 2. Broken variants. Each breaks one property; the lengths are the
;;;; shortest path to the violation, counted in trace steps with the initial
;;;; state first.

(describe "watch cycle specification, broken variants"
  (it "rejects a detected change that is never reloaded"
    ;; init, detect, reload (does nothing), run: the first pass runs stale code.
    (let ((violation (wm-expect-violation
                      (wm-explore (watch-cycle :bug :skip-reload))
                      'rerun-uses-reloaded-code :invariant 4)))
      (expect (wm-trace-actions violation)
              :to-equal '((nil) (detect) (reload :ok) (run :pass)))))
  (it "rejects a run after a failed reload"
    ;; The failed reload is ignored and the run follows it.
    (let ((violation (wm-expect-violation
                      (wm-explore (watch-cycle :bug :run-after-failed-reload))
                      'rerun-uses-reloaded-code :invariant 4)))
      (expect (wm-trace-actions violation)
              :to-equal '((nil) (detect) (reload :fail) (run :pass)))))
  (it "rejects a rerun when no file changed"
    ;; init, detect, reload, run, merge, then a detect with nothing changed.
    (wm-expect-violation (wm-explore (watch-cycle :bug :rerun-unchanged))
                         'run-follows-detected-change :invariant 6))
  (it "rejects a merge that adopts the post-run signature of a watched file"
    ;; An edit after the reload is then recorded as already seen: init, detect,
    ;; reload, edit, run, merge.
    (let ((violation (wm-expect-violation
                      (wm-explore (watch-cycle :bug :merge-refreshed))
                      'state-not-ahead-of-loaded :invariant 6)))
      (expect (spec-violation-detail violation)
              :to-satisfy (lambda (detail) (not (null (getf detail :state)))))))
  (it "rejects a watcher that stops on a failing run"
    ;; init, detect, reload, run (fail), then the stop.
    (wm-expect-violation (wm-explore (watch-cycle :bug :stop-on-failure))
                         'terminal-phases-only-in-once-mode :invariant 5))
  (it "rejects an incremental reload after the definition file changed"
    ;; First pass (full), edit ASD, then the second pass reloads incrementally:
    ;; init, detect, reload, run, merge, edit, detect, reload.
    (let ((violation (wm-expect-violation
                      (wm-explore (watch-cycle :bug :incremental-asd))
                      'reload-kind-matches-change :invariant 8)))
      ;; The shortest path may place the ASD edit before or after the first
      ;; reload; either way the second pass is the one reloaded wrongly.
      (expect (wm-trace-actions violation)
              :to-satisfy (lambda (actions)
                            (and (member '(edit asd) actions :test #'equal)
                                 (equal (car (last actions)) '(reload :ok)))))))

  (it "shows the lost edit as a lasso when only liveness is checked"
    ;; Same bug as the merge variant, without the invariant that names it: the
    ;; loop settles in an idle state whose recorded file state hides the edit.
    (let* ((spec (wm-wipe-invariants
                  (watch-cycle :bug :merge-refreshed :reload-can-fail nil)))
           (result (explore-spec spec :temporal '(edits-eventually-loaded)
                                      :max-states 100000))
           (violation (spec-result-violation result))
           (lasso (spec-violation-trace violation)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :temporal)
      (expect (spec-violation-property violation) :to-be 'edits-eventually-loaded)
      (expect (lasso-p lasso) :to-be t)
      ;; init, detect, reload, edit, run, merge; then the idle state repeats.
      (expect (length (lasso-prefix lasso)) :to-be 6)
      (expect (length (lasso-cycle lasso)) :to-be 1)))
  (it "needs weak fairness: without it the loop may stall after a detected change"
    (let* ((result (explore-spec
                    (wm-without-fairness (watch-cycle :reload-can-fail nil))
                    :temporal '(edits-eventually-loaded) :max-states 100000))
           (violation (spec-result-violation result)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :temporal)
      (expect (lasso-p (spec-violation-trace violation)) :to-be t))))

;;;; ------------------------------------------------------------------
;;;; 3. Conformance of the real loop.

(describe "watch cycle conformance, directed scenarios"
  (it "leaves the real functions it replaced exactly as they were"
    (let* ((names '(cl-weave::file-state cl-weave::watch-cycle-plan cl-weave::refresh-watch-state
                    cl-weave::watch-sleep cl-weave:run-all cl-weave::watched-system-files
                    cl-weave::atomic-full-system-reload cl-weave::merge-refreshed-watch-state))
           (before (mapcar #'symbol-function names)))
      (wm-run-script (watch-cycle) '((detect) (reload :ok) (run :pass) (merge-state))
                     :defect :merge-takes-refreshed)
      (expect (mapcar #'symbol-function names) :to-satisfy
              (lambda (after) (every #'eq before after)))))
  (it "matches the specification when no change means no rerun"
    (multiple-value-bind (expected observed expected-outputs observed-outputs sut)
        (wm-run-script (watch-cycle)
                       '((detect) (reload :ok) (run :pass) (merge-state)
                         (detect-idle) (detect-idle)))
      (expect observed :to-equal expected)
      (expect observed-outputs :to-equal expected-outputs)
      ;; One initial pass ran the tests; the two idle passes ran nothing.
      (expect (we-run-count (wm-sut-env sut)) :to-be 1)
      (expect (we-reload-count (wm-sut-env sut)) :to-be 1)
      (expect (wm-final observed 'phase) :to-be :idle)
      (expect (wm-final observed 'state) :to-equal '((src . 0) (tst . 0) (asd . 0)))))
  (it "matches the specification when several files change at once"
    (multiple-value-bind (expected observed expected-outputs observed-outputs)
        (wm-run-script (watch-cycle)
                       '((detect) (reload :ok) (run :pass) (merge-state)
                         (edit src) (edit tst) (detect) (reload :ok) (run :pass)))
      (expect observed :to-equal expected)
      (expect observed-outputs :to-equal expected-outputs)
      (expect (wm-final observed 'changed) :to-equal '(src tst))
      (expect (wm-final observed 'scope) :to-be :full-suite)
      (expect (wm-final observed 'kind) :to-be :incremental)
      (expect (car (last observed-outputs)) :to-equal '(:full-suite nil nil))))
  (it "narrows the rerun when only the registered test file changed"
    (multiple-value-bind (expected observed expected-outputs observed-outputs)
        (wm-run-script (watch-cycle)
                       '((detect) (reload :ok) (run :pass) (merge-state)
                         (edit tst) (detect) (reload :ok) (run :pass)))
      (expect observed :to-equal expected)
      (expect observed-outputs :to-equal expected-outputs)
      (expect (wm-final observed 'scope) :to-be :changed-tests)
      (expect (car (last observed-outputs)) :to-equal '(:changed-tests (tst) nil))))
  (it "reloads fully and starts watching a new file after the definition changed"
    (multiple-value-bind (expected observed expected-outputs observed-outputs)
        (wm-run-script (watch-cycle)
                       '((detect) (reload :ok) (run :pass) (merge-state)
                         (edit asd) (detect) (reload :ok) (run :pass) (merge-state)
                         (edit new) (detect) (reload :ok)))
      (expect observed :to-equal expected)
      (expect observed-outputs :to-equal expected-outputs)
      ;; The merge baselined NEW at its current version, so only the later
      ;; edit counts as a change, and it reloads incrementally.
      (expect (nth 7 observed-outputs) :to-equal '(:full-suite nil nil))
      (expect (state-ref (nth 8 observed) 'files) :to-equal '(src tst asd new))
      (expect (state-ref (nth 8 observed) 'state)
              :to-equal '((src . 0) (tst . 0) (asd . 1) (new . 0)))
      (expect (wm-final observed 'changed) :to-equal '(new))
      (expect (car (last observed-outputs)) :to-equal '(:incremental (new)))))
  (it "keeps an edit made while the tests run for the next pass"
    (multiple-value-bind (expected observed expected-outputs observed-outputs)
        (wm-run-script (watch-cycle)
                       '((detect) (reload :ok) (edit src) (run :pass) (merge-state)
                         (detect) (reload :ok) (run :pass) (merge-state)
                         (detect-idle)))
      (expect observed :to-equal expected)
      (expect observed-outputs :to-equal expected-outputs)
      ;; The merge kept the pre-run signature, so the second pass sees SRC.
      (expect (state-ref (nth 4 observed) 'state)
              :to-equal '((src . 0) (tst . 0) (asd . 0)))
      (expect (state-ref (nth 5 observed) 'changed) :to-equal '(src))
      (expect (wm-final observed 'state) :to-equal '((src . 1) (tst . 0) (asd . 0)))))
  (it "ends the loop on a failed reload without running or advancing the state"
    (multiple-value-bind (expected observed expected-outputs observed-outputs sut)
        (wm-run-script (watch-cycle)
                       '((detect) (reload :ok) (run :pass) (merge-state)
                         (edit src) (detect) (reload :fail)))
      (expect observed :to-equal expected)
      (expect observed-outputs :to-equal expected-outputs)
      (expect (wm-final observed 'phase) :to-be :aborted)
      (expect (wm-final observed 'state) :to-equal '((src . 0) (tst . 0) (asd . 0)))
      (expect (we-run-count (wm-sut-env sut)) :to-be 1)))
  (it "keeps watching after a failing run and does not rerun it unchanged"
    (multiple-value-bind (expected observed expected-outputs observed-outputs sut)
        (wm-run-script (watch-cycle)
                       '((detect) (reload :ok) (run :fail) (merge-state)
                         (detect-idle)))
      (expect observed :to-equal expected)
      (expect observed-outputs :to-equal expected-outputs)
      (expect (wm-final observed 'phase) :to-be :idle)
      (expect (we-run-count (wm-sut-env sut)) :to-be 1)))
  (it "returns true from the final pass when the run passes"
    (multiple-value-bind (expected observed expected-outputs observed-outputs sut)
        (wm-run-script (watch-cycle :once t)
                       '((detect) (reload :ok) (run :pass) (finish)) :once t)
      (expect observed :to-equal expected)
      (expect observed-outputs :to-equal expected-outputs)
      (expect (wm-final observed 'phase) :to-be :done)
      (expect (we-return-value (wm-sut-env sut)) :to-be t)))
  (it "returns false from the final pass when the run fails"
    (multiple-value-bind (expected observed expected-outputs observed-outputs sut)
        (wm-run-script (watch-cycle :once t)
                       '((detect) (reload :ok) (run :fail) (finish)) :once t)
      (expect observed :to-equal expected)
      (expect observed-outputs :to-equal expected-outputs)
      (expect (wm-final observed 'phase) :to-be :stopped)
      (expect (we-return-value (wm-sut-env sut)) :to-be nil))))

(describe "watch cycle conformance, searched"
  (it-spec "follows the specification over random action sequences"
    (wm-conformance (watch-cycle :max-edits 3)
                    :mode :random :seed 20261123 :runs 300 :max-steps 30))
  (it-spec "follows the specification over random sequences of the final pass"
    (wm-conformance (watch-cycle :once t :max-edits 2) :once t
                    :mode :random :seed 7 :runs 60 :max-steps 10))
  (it "visits every reachable state of the specification tree up to a depth"
    ;; Paths longer than the depth stay unchecked, so the bound is stated with
    ;; :allow-bounded; the depth is enough to reach every state, which the
    ;; exhaustive count confirms.
    (let ((spec (watch-cycle :max-edits 1 :reload-can-fail nil)))
      (let ((result (wm-conformance spec :mode :tree :depth 8 :max-states 100000
                                         :allow-bounded t)))
        (expect (spec-result-passed-p result) :to-be t)
        (expect (spec-result-states-found result)
                :to-be (spec-result-states-found (wm-explore spec))))))
  (it "visits every reachable state of the final pass tree"
    (let ((spec (watch-cycle :once t :max-edits 1)))
      (let ((result (wm-conformance spec :once t :mode :tree :depth 6 :max-states 100000
                                         :allow-bounded t)))
        (expect (spec-result-passed-p result) :to-be t)
        (expect (spec-result-states-found result)
                :to-be (spec-result-states-found (wm-explore spec)))))))

(describe "watch cycle conformance, defects in the real code"
  (it "reports a merge that adopts the post-run signature"
    ;; The shortest exposing script edits a file during the run: detect,
    ;; reload, edit, run, merge. The check shrinks to exactly those steps.
    (let* ((result (wm-conformance (watch-cycle :max-edits 3)
                                   :defect :merge-takes-refreshed
                                   :mode :random :seed 20261123 :runs 60 :max-steps 22))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (getf detail :action) :to-be 'merge-state)
      (expect (getf detail :what) :to-be :state)
      (expect (length (spec-violation-trace violation)) :to-be 6)
      (expect (getf (getf detail :actual) 'state)
              :to-satisfy (lambda (state)
                            (not (equal state (getf (getf detail :expected) 'state)))))))
  (it "reports a definition-file change reloaded incrementally"
    (let* ((result (wm-conformance (watch-cycle :max-edits 3)
                                   :defect :asd-treated-as-source
                                   :mode :random :seed 20261123 :runs 60 :max-steps 22))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (getf detail :action) :to-be 'reload)
      (expect (getf (getf detail :actual) 'kind) :to-be :incremental)
      (expect (getf (getf detail :expected) 'kind) :to-be :full)
      ;; detect, reload, run, merge, edit asd, detect, reload.
      (expect (length (spec-violation-trace violation)) :to-be 8)))
  (it "reports a watcher that stops after a failing run"
    (let* ((result (wm-conformance (watch-cycle :max-edits 3)
                                   :defect :stop-on-failed-run
                                   :mode :random :seed 20261123 :runs 60 :max-steps 22))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (getf detail :action) :to-be 'merge-state)
      ;; detect, reload, run (fail), merge-state: the loop returned instead.
      (expect (length (spec-violation-trace violation)) :to-be 5))))
