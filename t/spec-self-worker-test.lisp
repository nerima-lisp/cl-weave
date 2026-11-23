(in-package #:cl-weave/spec-test)

;;;; Self-verification of the concurrent worker pool (FR-014, area "worker").
;;;;
;;;; The model below abstracts RUN-CONCURRENT-TEST-CASES/THREADED in
;;;; src/runner-concurrency.lisp. One state variable stands for each shared
;;;; object of the real code:
;;;;
;;;;   claimed   index part of WORK-STATE (the next job to hand out)
;;;;   cancel    the cancel bit of WORK-STATE
;;;;   sem       count of START-GATE
;;;;   released  RELEASED-WORKER-COUNT (main thread only)
;;;;   joined    how many worker threads the main thread has joined
;;;;   locals    per worker (PC ARG): ARG is the word the worker last read
;;;;             while at :CAS, and the claimed job index at :RUN and :STORE
;;;;   execs     how many times each job body ran
;;;;   results   RESULTS vector; :UNSET or (:JOB i), the result of job i
;;;;
;;;; Every step of the model is one atomic access of the real code: a word
;;;; read, a CAS, running a job, one vector store, one semaphore operation. The
;;;; claim is split into READ-STATE and TRY-CLAIM so that a CAS can fail.
;;;;
;;;; Abstracted away, so not covered by this model:
;;;;   - thread creation (WORKERS is the number of threads that were created);
;;;;   - a worker that dies inside RUN-TEST-CASE/INTERNAL. The real code only
;;;;     reaches the cancel bit through such a death or a failed thread
;;;;     creation; the model lets CANCEL-RUN fire at any time instead, which
;;;;     covers both entry points. A dying worker would leave its job
;;;;     unfinished, and the model never does that;
;;;;   - dynamic environment capture and the sequential path for one worker.
;;;; The checks need WORKERS >= 2 and JOBS >= WORKERS, which is exactly when
;;;; WORKER-BATCH-SIZE sends the real code down the threaded path.
;;;;
;;;; The variants select a deliberate deviation from the real code through the
;;;; constants CLAIM, CAS-COMPARES-CANCEL, STORE and ON-CANCEL.

(defun wp-replace-nth (list index value)
  (append (subseq list 0 index) (list value) (nthcdr (1+ index) list)))

(defun wp-pc (locals worker)
  (first (nth worker locals)))

(defun wp-arg (locals worker)
  (second (nth worker locals)))

(defun wp-set-local (locals worker pc &optional argument)
  (wp-replace-nth locals worker (list pc argument)))

(defun wp-held (locals pc)
  (loop for (local-pc argument) in locals
        when (eq local-pc pc) collect argument))

(defun wp-all-done-p (locals)
  (every (lambda (local) (eq (first local) :done)) locals))

(defun wp-claim-succeeds-p (claim compares-cancel seen-cancel seen-claimed cancel claimed)
  "Whether the CAS of the real CLAIM-JOB would succeed. The real code compares
the whole word, so the cancel bit takes part in the comparison."
  (ecase claim
    (:blind t)
    (:cas (and (= seen-claimed claimed)
               (or (not compares-cancel)
                   (eq (and seen-cancel t) (and cancel t)))))))

(defun wp-worker-indexes (count)
  (loop for index below count collect index))

(defspec worker-pool ((jobs 3) (workers 2)
                      (claim :cas)
                      (cas-compares-cancel t)
                      (store :in-place)
                      (on-cancel :exit))
  (:variables claimed cancel sem released joined locals execs results)
  (:init (claimed 0) (cancel nil) (sem 0) (released 0) (joined 0)
         (locals (loop repeat workers collect (list :wait nil)))
         (execs (make-list jobs :initial-element 0))
         (results (make-list jobs :initial-element :unset)))

  ;; RELEASE-WORKERS: one SIGNAL-SEMAPHORE per created worker.
  (:action release
    (:guard (< released workers))
    (:next (released (1+ released))
           (sem (1+ sem))))

  ;; WAIT-ON-SEMAPHORE START-GATE at the top of RUN-WORKER.
  (:action wait-sem
    (:for (w (wp-worker-indexes workers)))
    (:guard (and (eq (wp-pc locals w) :wait) (plusp sem)))
    (:next (sem (1- sem))
           (locals (wp-set-local locals w :read))))

  ;; The first half of CLAIM-JOB: read WORK-STATE and test the exit condition.
  (:action read-state
    (:for (w (wp-worker-indexes workers)))
    (:guard (eq (wp-pc locals w) :read))
    (:next (locals
            (cond ((and cancel (eq on-cancel :spin)) locals)
                  ((and cancel (eq on-cancel :rewait)) (wp-set-local locals w :wait))
                  ((or cancel (>= claimed jobs)) (wp-set-local locals w :done))
                  (t (wp-set-local locals w :cas (list cancel claimed)))))))

  ;; The second half of CLAIM-JOB: COMPARE-AND-SWAP WORK-STATE to STATE + 1.
  ;; A failed CAS goes back to the read; a blind store overwrites the word.
  (:action try-claim
    (:for (w (wp-worker-indexes workers)))
    (:guard (eq (wp-pc locals w) :cas))
    (:next (claimed
            (destructuring-bind (seen-cancel seen-claimed) (wp-arg locals w)
              (if (wp-claim-succeeds-p claim cas-compares-cancel seen-cancel
                                       seen-claimed cancel claimed)
                  (1+ seen-claimed)
                  claimed)))
           (locals
            (destructuring-bind (seen-cancel seen-claimed) (wp-arg locals w)
              (if (wp-claim-succeeds-p claim cas-compares-cancel seen-cancel
                                       seen-claimed cancel claimed)
                  (wp-set-local locals w :run seen-claimed)
                  (wp-set-local locals w :read))))))

  ;; RUN-TEST-CASE/INTERNAL.
  (:action run-job
    (:for (w (wp-worker-indexes workers)))
    (:guard (eq (wp-pc locals w) :run))
    (:next (execs (let ((job (wp-arg locals w)))
                    (wp-replace-nth execs job (1+ (nth job execs)))))
           (locals (wp-set-local locals w :store (wp-arg locals w)))))

  ;; (SETF (AREF RESULTS INDEX) ...)
  (:action store-result
    (:for (w (wp-worker-indexes workers)))
    (:guard (eq (wp-pc locals w) :store))
    (:next (results
            (let* ((job (wp-arg locals w))
                   (slot (if (eq store :shifted) (mod (1+ job) jobs) job)))
              (wp-replace-nth results slot (list :job job))))
           (locals (wp-set-local locals w :read))))

  ;; JOIN-CREATED-THREADS runs after RELEASE-WORKERS and joins in creation
  ;; order; JOIN-THREAD blocks until that worker has finished.
  (:action join-worker
    (:guard (and (= released workers) (< joined workers)
                 (eq (wp-pc locals joined) :done)))
    (:next (joined (1+ joined))))

  ;; CANCEL-WORKERS sets the bit with a CAS loop; the model treats it as one
  ;; atomic step. The remaining RELEASE-WORKERS is the RELEASE action again.
  (:action cancel-run
    (:guard (and (not cancel) (< joined workers)))
    (:next (cancel t)))

  ;; The finished state is not a deadlock.
  (:action finished
    (:guard (= joined workers)))

  (:invariant claimed-in-range (<= 0 claimed jobs))
  (:invariant claims-exclusive
    (let ((held (append (wp-held locals :run) (wp-held locals :store))))
      (= (length held) (length (remove-duplicates held)))))
  (:invariant executed-at-most-once
    (every (lambda (count) (<= count 1)) execs))
  ;; Exactly the jobs below CLAIMED have been handed out. A job that is handed
  ;; out has run once, or is still waiting to run in its worker.
  (:invariant handed-out-jobs-are-a-prefix
    (let ((waiting (wp-held locals :run))
          (held (append (wp-held locals :run) (wp-held locals :store))))
      (loop for job below jobs
            always (if (< job claimed)
                       (= (nth job execs) (if (member job waiting) 0 1))
                       (and (= (nth job execs) 0)
                            (not (member job held)))))))
  ;; A result sits in its own index and only after its job ran.
  (:invariant results-in-place
    (loop for job below jobs
          for result in results
          always (or (eq result :unset)
                     (and (equal result (list :job job))
                          (>= (nth job execs) 1)))))
  ;; When every worker has been joined, each handed-out job ran exactly once
  ;; with its result in place, and without cancel every job was handed out.
  (:invariant finished-state-complete
    (or (< joined workers)
        (and (wp-all-done-p locals)
             (or cancel (= claimed jobs))
             (loop for job below jobs
                   for result in results
                   always (if (< job claimed)
                              (and (= (nth job execs) 1) (equal result (list :job job)))
                              (and (= (nth job execs) 0) (eq result :unset)))))))

  (:action-property claimed-monotone (>= (next claimed) claimed))
  (:action-property no-claim-after-cancel
    (or (= (next claimed) claimed) (not cancel)))
  (:action-property cancel-sticky (or (not cancel) (next cancel)))

  (:temporal terminates (:eventually (= joined workers)))
  (:temporal cancel-terminates (:leads-to cancel (wp-all-done-p locals)))

  (:fairness (:weak release wait-sem read-state try-claim run-job store-result
              join-worker)))

(defparameter *wp-weak-actions*
  '(release wait-sem read-state try-claim run-job store-result join-worker))

(defparameter *wp-property-names*
  '(claimed-in-range claims-exclusive executed-at-most-once
    handed-out-jobs-are-a-prefix results-in-place finished-state-complete
    claimed-monotone no-claim-after-cancel cancel-sticky
    terminates cancel-terminates :deadlock))

(defun wp-derive (spec &key (invariants :all) (action-properties :all)
                         (temporal :all) (fairness :all))
  "Copy SPEC keeping only the named properties; FAIRNESS lists the actions that
keep their weak fairness condition."
  (flet ((keep (items name-function names)
           (if (eq names :all)
               items
               (remove-if-not (lambda (item) (member (funcall name-function item) names))
                              items))))
    (make-spec :name (spec-name spec) :constants (spec-constants spec)
               :variables (spec-variables spec) :init (spec-init spec)
               :actions (spec-actions spec)
               :invariants (keep (spec-invariants spec) #'spec-invariant-name invariants)
               :action-properties (keep (spec-action-properties spec)
                                        #'spec-action-property-name action-properties)
               :temporal-properties (keep (spec-temporal-properties spec)
                                          #'spec-temporal-property-name temporal)
               :fairness-conditions (keep (spec-fairness-conditions spec)
                                          #'spec-fairness-condition-action fairness)
               :symmetry (spec-symmetry spec)
               :check-deadlock (spec-check-deadlock spec))))

(defun wp-trace-actions (trace)
  (mapcar #'trace-step-action (rest trace)))

(defun wp-violation-state (violation)
  (trace-step-state (car (last (spec-violation-trace violation)))))

(defun wp-valid-lasso-p (spec lasso)
  "True when LASSO is a real run of SPEC: it starts in an initial state, each
step is an enabled transition (or a stutter) and the cycle returns to where the
prefix ends."
  (flet ((step-ok-p (from step)
           (let ((to (trace-step-state step)))
             (if (null (trace-step-action step))
                 (equal from to)
                 (some (lambda (transition)
                         (and (eq (spec-transition-action transition) (trace-step-action step))
                              (equal (spec-transition-params transition) (trace-step-params step))
                              (equal (spec-transition-to transition) to)))
                       (spec-successors spec from))))))
    (let* ((prefix (lasso-prefix lasso))
           (cycle (lasso-cycle lasso))
           (entry (trace-step-state (car (last prefix)))))
      (and prefix cycle
           (member (trace-step-state (first prefix)) (spec-initial-states spec) :test #'equal)
           (loop for (from to) on prefix while to
                 always (step-ok-p (trace-step-state from) to))
           (loop with from = entry
                 for step in cycle
                 always (prog1 (step-ok-p from step)
                          (setf from (trace-step-state step))))
           (equal entry (trace-step-state (car (last cycle))))))))

(defun wp-state-value (state variable)
  (state-ref state variable))

;;; ------------------------------------------------------------------------
;;; The abstract model, checked exhaustively.

(describe "worker pool model"
  ;; Where the graph fits the default limits they stay as they are: a run that
  ;; truncates fails instead of passing, so the pass means a complete search.
  (it-spec "2 workers, 2 jobs: every property holds in the whole state graph"
    (explore-spec (worker-pool :jobs 2 :workers 2)))

  (it-spec "2 workers, 3 jobs: every property holds in the whole state graph"
    (explore-spec (worker-pool :jobs 3 :workers 2)))

  ;; Liveness on 3 workers is left out: the lasso search is quadratic in the
  ;; state graph and takes seconds there. Safety covers the extra interleavings.
  (it-spec "3 workers, 3 jobs: every safety property holds in the whole state graph"
    (explore-spec (worker-pool :jobs 3 :workers 3) :max-states 200000 :temporal nil))

  (it-spec "2 workers, 4 jobs: every property holds in the whole state graph"
    (explore-spec (worker-pool :jobs 4 :workers 2)))

  (it "checks every declared property and the whole graph, without truncation"
    (let ((result (explore-spec (worker-pool :jobs 3 :workers 2))))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-truncated result) :to-be nil)
      (expect (spec-result-checked-properties result)
              :to-equal *wp-property-names*)
      (expect (spec-result-liveness-requested result)
              :to-equal '(terminates cancel-terminates))))

  (it "does not decide liveness on a truncated graph, even when bounded checking is allowed"
    (let ((bounded (explore-spec (worker-pool :jobs 3 :workers 2)
                                 :max-states 40 :allow-bounded t))
          (safety-only (explore-spec (worker-pool :jobs 3 :workers 2)
                                     :max-states 40 :allow-bounded t :temporal nil)))
      (expect (spec-result-truncated bounded) :to-be t)
      (expect (spec-result-passed-p bounded) :to-be nil)
      (expect (spec-result-truncated safety-only) :to-be t)
      (expect (spec-result-passed-p safety-only) :to-be t)))

  (it "reaches a state in which every job ran and, with cancel set, one in which not every job ran"
    ;; Guards against a vacuous model: a pool that can never finish, or that
    ;; can never be cancelled midway, would pass the invariants trivially.
    (let ((spec (worker-pool :jobs 3 :workers 2))
          (all-ran nil) (cancelled-early nil))
      (let ((graph (make-state-graph :spec spec
                                     :initial-states (spec-initial-states spec))))
        (let ((queue (copy-list (state-graph-initial-states graph))))
          (loop while queue
                for state = (pop queue)
                unless (nth-value 1 (state-table-ref (state-graph-edges graph) state))
                  do (let ((transitions (spec-successors spec state)))
                       (setf (state-table-ref (state-graph-edges graph) state) transitions)
                       (when (= (wp-state-value state 'joined) 2)
                         (if (wp-state-value state 'cancel)
                             (when (< (wp-state-value state 'claimed) 3)
                               (setf cancelled-early t))
                             (when (equal (wp-state-value state 'execs) '(1 1 1))
                               (setf all-ran t))))
                       (dolist (transition transitions)
                         (push (spec-transition-to transition) queue))))))
      (expect all-ran :to-be t)
      (expect cancelled-early :to-be t))))

;;; ------------------------------------------------------------------------
;;; Broken variants. Each differs from the real code in one place; the check
;;; must fail, name the property, and return a shortest trace.

(describe "worker pool model, broken variants"
  (it "detects a claim without compare-and-swap: two workers take the same job"
    ;; release x2, wait-sem x2, read-state x2, try-claim x2: both workers hold
    ;; job 0. The action properties are dropped: an unconditional store also
    ;; ignores the cancel bit, which no-claim-after-cancel reports sooner (see
    ;; the next test).
    (let* ((spec (wp-derive (worker-pool :jobs 3 :workers 2 :claim :blind)
                            :action-properties nil :temporal nil))
           (result (explore-spec spec))
           (violation (spec-result-violation result)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :invariant)
      (expect (spec-violation-property violation) :to-be 'claims-exclusive)
      (expect (length (spec-violation-trace violation)) :to-be 9)
      (expect (wp-trace-actions (spec-violation-trace violation))
              :to-satisfy (lambda (actions)
                            (and (= 2 (count 'try-claim actions))
                                 (eq (first (last actions)) 'try-claim))))
      (expect (wp-held (wp-state-value (wp-violation-state violation) 'locals) :run)
              :to-equal '(0 0))))

  (it "reports a claim without compare-and-swap through the cancel bit first"
    ;; release, wait-sem, read-state, cancel-run, try-claim: the store succeeds
    ;; although the cancel bit was set after the read.
    (let* ((result (explore-spec (worker-pool :jobs 3 :workers 2 :claim :blind)
                                 :temporal nil))
           (violation (spec-result-violation result)))
      (expect (spec-violation-kind violation) :to-be :action-property)
      (expect (spec-violation-property violation) :to-be 'no-claim-after-cancel)
      (expect (length (spec-violation-trace violation)) :to-be 6)))

  (it "detects a job that runs twice, as the property about executions alone"
    ;; The same trace as above, then run-job on both workers.
    (let* ((spec (wp-derive (worker-pool :jobs 3 :workers 2 :claim :blind)
                            :invariants '(executed-at-most-once)
                            :action-properties nil :temporal nil))
           (result (explore-spec spec))
           (violation (spec-result-violation result)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-property violation) :to-be 'executed-at-most-once)
      (expect (length (spec-violation-trace violation)) :to-be 11)
      (expect (wp-state-value (wp-violation-state violation) 'execs)
              :to-equal '(2 0 0))))

  (it "detects a result stored under the wrong index"
    ;; release, wait-sem, read-state, try-claim, run-job, store-result.
    (let* ((result (explore-spec (worker-pool :jobs 3 :workers 2 :store :shifted)
                                 :temporal nil))
           (violation (spec-result-violation result)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :invariant)
      (expect (spec-violation-property violation) :to-be 'results-in-place)
      (expect (length (spec-violation-trace violation)) :to-be 7)
      (expect (wp-state-value (wp-violation-state violation) 'results)
              :to-equal '(:unset (:job 0) :unset))))

  (it "detects a claim that succeeds after the cancel bit is set"
    ;; A CAS that compares only the index would let this through: release,
    ;; wait-sem, read-state, cancel-run, try-claim.
    (let* ((result (explore-spec (worker-pool :jobs 3 :workers 2 :cas-compares-cancel nil)
                                 :temporal nil))
           (violation (spec-result-violation result)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :action-property)
      (expect (spec-violation-property violation) :to-be 'no-claim-after-cancel)
      (expect (spec-violation-detail violation)
              :to-satisfy (lambda (detail) (eq (getf detail :action) 'try-claim)))
      (expect (wp-trace-actions (spec-violation-trace violation))
              :to-equal '(release wait-sem read-state cancel-run try-claim))))

  (it "detects a worker that blocks again after cancel as a deadlock"
    ;; release x2, wait-sem x2, cancel-run, read-state x2: both workers wait on
    ;; a gate nobody signals again.
    (let* ((spec (worker-pool :jobs 3 :workers 2 :on-cancel :rewait))
           (result (explore-spec spec :temporal nil))
           (violation (spec-result-violation result)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :deadlock)
      (expect (length (spec-violation-trace violation)) :to-be 8)
      (expect (spec-deadlock-p spec (wp-violation-state violation)) :to-be t)
      (expect (wp-held (wp-state-value (wp-violation-state violation) 'locals) :done)
              :to-be nil)))

  (it "reports a lasso for a worker that spins after cancel, although every action is weakly fair"
    (let* ((spec (worker-pool :jobs 3 :workers 2 :on-cancel :spin))
           (result (explore-spec spec :temporal '(cancel-terminates)))
           (violation (spec-result-violation result))
           (lasso (spec-violation-trace violation)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-result-truncated result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :temporal)
      (expect (spec-violation-property violation) :to-be 'cancel-terminates)
      (expect (wp-valid-lasso-p spec lasso) :to-be t)
      ;; The cycle is a stutter in which cancel is set and some worker never finishes.
      (expect (length (lasso-cycle lasso)) :to-be 1)
      (expect (trace-step-action (first (lasso-cycle lasso))) :to-be nil)
      (let ((state (trace-step-state (first (lasso-cycle lasso)))))
        (expect (wp-state-value state 'cancel) :to-be t)
        (expect (wp-all-done-p (wp-state-value state 'locals)) :to-be nil))))

  (it "reports a lasso for the same model once weak fairness is removed"
    (let* ((spec (wp-derive (worker-pool :jobs 3 :workers 2) :fairness nil))
           (result (explore-spec spec :temporal '(terminates)))
           (violation (spec-result-violation result))
           (lasso (spec-violation-trace violation)))
      (expect (spec-result-passed-p result) :to-be nil)
      (expect (spec-violation-kind violation) :to-be :temporal)
      (expect (spec-violation-property violation) :to-be 'terminates)
      (expect (wp-valid-lasso-p spec lasso) :to-be t)
      ;; Without fairness the pool may stay in its initial state forever.
      (expect (length (lasso-prefix lasso)) :to-be 1)
      (expect (length (lasso-cycle lasso)) :to-be 1)))

  (it "needs weak fairness of release: without it the workers may never start"
    (let* ((spec (wp-derive (worker-pool :jobs 3 :workers 2)
                            :fairness (remove 'release *wp-weak-actions*)))
           (result (explore-spec spec :temporal '(terminates)))
           (violation (spec-result-violation result))
           (lasso (spec-violation-trace violation)))
      (expect (spec-violation-property violation) :to-be 'terminates)
      (expect (wp-valid-lasso-p spec lasso) :to-be t)
      (let ((state (trace-step-state (first (lasso-cycle lasso)))))
        (expect (wp-state-value state 'released) :to-be-less-than 2)
        (expect (wp-state-value state 'joined) :to-be-less-than 2))))

  (it "needs weak fairness of join-worker: the main thread may stop before it joins"
    (let* ((spec (wp-derive (worker-pool :jobs 3 :workers 2)
                            :fairness (remove 'join-worker *wp-weak-actions*)))
           (result (explore-spec spec :temporal '(terminates)))
           (violation (spec-result-violation result))
           (lasso (spec-violation-trace violation)))
      (expect (spec-violation-property violation) :to-be 'terminates)
      (expect (wp-valid-lasso-p spec lasso) :to-be t)
      (let ((state (trace-step-state (first (lasso-cycle lasso)))))
        (expect (wp-state-value state 'joined) :to-be-less-than 2)
        ;; Every worker is finished, so join-worker alone is still enabled.
        (expect (wp-all-done-p (wp-state-value state 'locals)) :to-be t)))))

;;; ------------------------------------------------------------------------
;;; The real worker pool, called from outside. The assertions hold under every
;;; schedule: no sleep, no timeout and no ordering between workers is assumed.
;;; What the model proves for all schedules, these checks sample.

#+sb-thread
(progn
  (defun wp-make-jobs (job-count body)
    "Return (values suite tests): JOB-COUNT concurrent test cases, job I calls
BODY with I."
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root (cl-weave::make-suite :name "pool" :parent root)))
           (tests (loop for index below job-count
                        collect (let ((index index))
                                  (cl-weave::add-child
                                   suite
                                   (cl-weave::make-test-case
                                    :name (format nil "job-~D" index)
                                    :execution-mode :concurrent
                                    :function (lambda () (funcall body index))))))))
      (values suite tests)))

  (defun wp-make-counters (count)
    (make-array count :element-type 'sb-ext:word :initial-element 0))

  (defun wp-count-run (counters index)
    (sb-ext:atomic-incf (aref (the (simple-array sb-ext:word (*)) counters) index)))

  (defun wp-call-with-thread-hooks (thunk &key make-thread join-thread)
    "Call THUNK with the runner's thread primitives routed through MAKE-THREAD
and JOIN-THREAD, which receive the original function first."
    (let ((original-make (symbol-function 'cl-weave::make-runner-worker-thread))
          (original-join (symbol-function 'cl-weave::join-runner-worker-thread)))
      (unwind-protect
           (progn
             (setf (symbol-function 'cl-weave::make-runner-worker-thread)
                   (lambda (function name)
                     (funcall make-thread original-make function name)))
             (setf (symbol-function 'cl-weave::join-runner-worker-thread)
                   (lambda (thread)
                     (funcall join-thread original-join thread)))
             (funcall thunk))
        (setf (symbol-function 'cl-weave::make-runner-worker-thread) original-make
              (symbol-function 'cl-weave::join-runner-worker-thread) original-join))))

  (defun wp-run-pool (suite tests worker-limit &key make-thread join-thread)
    (wp-call-with-thread-hooks
     (lambda ()
       (let ((cl-weave::*max-workers* worker-limit))
         (cl-weave::run-concurrent-test-cases suite tests)))
     :make-thread (or make-thread
                      (lambda (original function name)
                        (funcall original function name)))
     :join-thread (or join-thread
                      (lambda (original thread)
                        (funcall original thread)))))

  (defun wp-signalled-condition (thunk)
    "Return the serious condition THUNK signals, or :returned."
    (handler-case (progn (funcall thunk) :returned)
      (serious-condition (condition) condition)))

  (describe "worker pool implementation"
    (it "has the concurrency capability the model assumes"
      (expect (cl-weave::platform-capability-available-p :concurrency) :to-be t))

    (it "runs every job exactly once and returns each result at its own index"
      ;; (jobs workers): the worker count is min(limit, jobs), at least 2 so the
      ;; threaded path is taken, as in the model.
      (dolist (shape '((2 2) (3 2) (5 2) (5 3) (8 4) (64 2) (64 8) (200 7)))
        (destructuring-bind (job-count worker-limit) shape
          (let* ((counters (wp-make-counters job-count))
                 (threads '()))
            (multiple-value-bind (suite tests)
                (wp-make-jobs job-count (lambda (index) (wp-count-run counters index)))
              (let ((events (wp-run-pool
                             suite tests worker-limit
                             :make-thread (lambda (original function name)
                                            (let ((thread (funcall original function name)))
                                              (push thread threads)
                                              thread)))))
                ;; Each actual value carries SHAPE so a failure names the case.
                (expect (list shape (coerce counters 'list))
                        :to-equal (list shape (make-list job-count :initial-element 1)))
                (expect (list shape (mapcar #'cl-weave::test-event-status events))
                        :to-equal (list shape (make-list job-count :initial-element :pass)))
                (expect (list shape (mapcar #'cl-weave::test-event-path events))
                        :to-equal (list shape
                                        (loop for index below job-count
                                              collect (list "pool" (format nil "job-~D" index)))))
                (expect (list shape (length threads))
                        :to-equal (list shape (min worker-limit job-count)))
                (expect (list shape (some #'sb-thread:thread-alive-p threads))
                        :to-equal (list shape nil))))))))

    (it "runs no job and ends every created worker when thread creation fails, as the model's cancel before release"
      ;; Creation of the last requested worker fails after the others exist but
      ;; before any was released. The cleanup sets the cancel bit first, then
      ;; releases the start gate, so no worker can claim a job.
      (dolist (requested '(3 4 5))
        (let ((counters (wp-make-counters 8))
              (threads '())
              (calls 0)
              (injected (make-condition 'simple-error
                                        :format-control "injected worker creation failure")))
          (multiple-value-bind (suite tests)
              (wp-make-jobs 8 (lambda (index) (wp-count-run counters index)))
            (let ((signalled
                    (wp-signalled-condition
                     (lambda ()
                       (wp-run-pool
                        suite tests requested
                        :make-thread (lambda (original function name)
                                       (incf calls)
                                       (when (= calls requested)
                                         (error injected))
                                       (let ((thread (funcall original function name)))
                                         (push thread threads)
                                         thread)))))))
              (expect (list requested signalled) :to-equal (list requested injected))
              (expect (list requested (length threads))
                      :to-equal (list requested (1- requested)))
              (expect (list requested (some #'sb-thread:thread-alive-p threads))
                      :to-equal (list requested nil))
              (expect (list requested (coerce counters 'list))
                      :to-equal (list requested (make-list 8 :initial-element 0))))))))

    (it "returns, with every worker ended and no job run twice, when a join fails after the release"
      ;; The first join fails before joining. The code cancels the remaining
      ;; work and joins again. Which jobs ran before the cancel depends on the
      ;; schedule, so only the properties that hold for all schedules are asserted.
      (dolist (worker-limit '(2 3 4))
        (let ((counters (wp-make-counters 12))
              (threads '())
              (failed nil)
              (injected (make-condition 'simple-error
                                        :format-control "injected worker join failure")))
          (multiple-value-bind (suite tests)
              (wp-make-jobs 12 (lambda (index) (wp-count-run counters index)))
            (let ((signalled
                    (wp-signalled-condition
                     (lambda ()
                       (wp-run-pool
                        suite tests worker-limit
                        :make-thread (lambda (original function name)
                                       (let ((thread (funcall original function name)))
                                         (push thread threads)
                                         thread))
                        :join-thread (lambda (original thread)
                                       (if failed
                                           (funcall original thread)
                                           (progn (setf failed t)
                                                  (error injected)))))))))
              (expect (list worker-limit signalled) :to-equal (list worker-limit injected))
              (expect (list worker-limit (length threads)) :to-equal (list worker-limit worker-limit))
              (expect (list worker-limit (some #'sb-thread:thread-alive-p threads))
                      :to-equal (list worker-limit nil))
              (expect (list worker-limit (every (lambda (count) (<= count 1)) counters))
                      :to-equal (list worker-limit t)))))))

    (it "refuses to run without the concurrency capability and runs no job"
      (let ((counters (wp-make-counters 3)))
        (multiple-value-bind (suite tests)
            (wp-make-jobs 3 (lambda (index) (wp-count-run counters index)))
          (let ((cl-weave::*platform-capabilities* nil))
            (expect (lambda () (cl-weave::run-concurrent-test-cases suite tests))
                    :to-throw 'cl-weave::platform-capability-unavailable))
          (expect (coerce counters 'list) :to-equal '(0 0 0)))))))

#-sb-thread
(describe "worker pool implementation without threads"
  (it "reports the concurrency capability as unavailable and refuses to run"
    (expect (cl-weave::platform-capability-available-p :concurrency) :to-be nil)
    (expect (lambda ()
              (cl-weave::run-concurrent-test-cases (cl-weave::make-suite :name "pool") nil))
            :to-throw 'cl-weave::platform-capability-unavailable)))
