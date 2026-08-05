(in-package #:cl-weave)

(defmacro run-configuration-arguments ()
  "Expand to a call forwarding the run-configuration keyword arguments shared by
   RUN-SYSTEM and RUN-WATCH-CYCLE to RUN-SYSTEM-ARGUMENT-PAIRS. Relies on each
   caller's lambda list binding a same-named local for every keyword below --
   REPORTER, STREAM, and so on -- the way WITH-SLOTS binds its caller's slot
   names as locals; this is the same deliberate-capture contract, not an
   accident of hygiene."
  '(run-system-argument-pairs
    :reporter reporter
    :stream stream
    :name-filter name-filter
    :location-filter location-filter
    :test-path-filter test-path-filter
    :shard shard
    :order order
    :seed seed
    :bail bail
    :coverage coverage
    :coverage-output coverage-output
    :coverage-report-directory coverage-report-directory
    :coverage-include-pathnames coverage-include-pathnames
    :coverage-exclude-pathnames coverage-exclude-pathnames
    :coverage-minimum-expression coverage-minimum-expression
    :coverage-minimum-branch coverage-minimum-branch
    :pass-with-no-tests pass-with-no-tests
    :retry retry
    :timeout-ms timeout-ms
    :max-workers max-workers))

(defun run-system (system &key (reporter :spec)
                       (stream *standard-output*)
                       (name-filter *test-name-filter*)
                       location-filter
                       test-path-filter
                       shard
                       order
                       seed
                       bail
                       coverage
                       coverage-output
                       coverage-report-directory
                       coverage-include-pathnames coverage-exclude-pathnames
                       coverage-minimum-expression coverage-minimum-branch
                       pass-with-no-tests
                       retry
                       timeout-ms
                       max-workers)
  "Reload SYSTEM through ASDF, then run the currently registered cl-weave tests."
  (if (and *watch-incremental-reload-p*
           *watch-changed-pathnames*
           (notany #'asdf-definition-pathname-p *watch-changed-pathnames*))
      (atomic-incremental-system-reload system *watch-changed-pathnames*)
      (atomic-full-system-reload system))
  (apply #'run-all (run-configuration-arguments)))

(defun run-watched-system (system &rest arguments)
  "Reload SYSTEM with an isolated registry for a watch cycle."
  (let* ((changed-marker (member :changed-pathnames arguments))
         (changed-pathnames (and changed-marker (second changed-marker)))
         (run-arguments
           (if changed-marker
               (append (ldiff arguments changed-marker)
                       (cddr changed-marker))
               arguments)))
    (let ((*watch-incremental-reload-p* (not (null changed-marker)))
          (*watch-changed-pathnames* changed-pathnames))
      (apply #'run-system system run-arguments))))

(defun call-with-watch-run-attempt/k (succeededp once new-state on-continue on-stop)
  "Dispatch on one watch cycle's run outcome, the way CALL-WITH-SNAPSHOT-COMPARISON/K
   dispatches on a snapshot match: a successful run, or a non-final run under
   repeated watching, calls ON-CONTINUE with the state to carry into the next
   cycle; a failing run on the final (ONCE) pass calls ON-STOP instead."
  (if (or succeededp (not once))
      (funcall on-continue new-state)
      (funcall on-stop)))

(defun run-watch-cycle (system plan &key reporter stream status-stream
                            name-filter shard order seed bail
                            coverage coverage-output
                            coverage-report-directory
                            coverage-include-pathnames coverage-exclude-pathnames
                            coverage-minimum-expression coverage-minimum-branch
                            pass-with-no-tests retry timeout-ms
                            max-workers once)
  (let ((changed (getf plan :changed))
        (location-filter (getf plan :location-filter))
        (test-path-filter (getf plan :test-path-filter))
        (scope (getf plan :scope)))
    (if changed
        (progn
          (format status-stream "~&; cl-weave watch: ~D changed file~:P for ~A (~A)~%"
                  (length changed)
                  system
                  scope)
          (finish-output status-stream)
          (call-with-watch-run-attempt/k
           (apply #'run-watched-system
                  system
                  (append
                   (run-configuration-arguments)
                   (unless (getf plan :initialp)
                     (list :changed-pathnames changed))))
           once
           (getf plan :new-state)
           (lambda (new-state) (values new-state t))
           (lambda () (values nil nil))))
        (values nil t))))

(defun merge-refreshed-watch-state (next-state refreshed-state)
  (let ((next-write-dates (make-hash-table :test (function equal))))
    (dolist (entry next-state)
      (setf (gethash (car entry) next-write-dates) (cdr entry)))
    (mapcar (lambda (entry)
              (multiple-value-bind (write-date presentp)
                  (gethash (car entry) next-write-dates)
                (cons (car entry)
                      (if presentp write-date (cdr entry)))))
            refreshed-state)))

(defun valid-watch-interval-p (interval)
  (and (realp interval)
       #+sbcl
       (or (not (floatp interval))
           (and (not (sb-ext:float-nan-p interval))
                (not (sb-ext:float-infinity-p interval))))
       #-sbcl
       t
       (plusp interval)))

(defun refresh-watch-state (system include-dependencies next-state)
  "Recompute the watched file set after a cycle whose reload may have changed
   SYSTEM's ASDF component graph, then fold NEXT-STATE's post-run write-dates
   over the refreshed baseline via MERGE-REFRESHED-WATCH-STATE. Returns the
   refreshed file list and the merged state, for WATCH-SYSTEM to carry forward."
  (let* ((refreshed-files
           (watched-system-files system :include-dependencies include-dependencies))
         (refreshed-state (file-state refreshed-files)))
    (values refreshed-files (merge-refreshed-watch-state next-state refreshed-state))))

(defun watch-system (system &key (reporter :spec)
                            (stream *standard-output*)
                            (status-stream *error-output*)
                            (name-filter *test-name-filter*)
                            shard
                            order
                            seed
                            bail
                            coverage
                            coverage-output
                            coverage-report-directory
                            coverage-include-pathnames coverage-exclude-pathnames
                            coverage-minimum-expression coverage-minimum-branch
                            pass-with-no-tests
                            retry
                            timeout-ms
                            max-workers
                            include-dependencies
                            (interval 0.5)
                            once)
  "Run SYSTEM once, then rerun it when ASDF source or definition files change."
  (unless (valid-watch-interval-p interval)
    (error "cl-weave: watch interval must be a positive finite real number."))
  (let ((state nil)
        (files (watched-system-files
                system
                :include-dependencies include-dependencies)))
    (loop
      for new-state = (file-state files)
      for plan = (watch-cycle-plan state new-state)
      do (multiple-value-bind (next-state continuep)
             (run-watch-cycle
              system
              plan
              :reporter reporter
              :stream stream
              :status-stream status-stream
              :name-filter name-filter
              :shard shard
              :order order
              :seed seed
              :bail bail
              :coverage coverage
              :coverage-output coverage-output
              :coverage-report-directory coverage-report-directory
              :coverage-include-pathnames coverage-include-pathnames
              :coverage-exclude-pathnames coverage-exclude-pathnames
              :coverage-minimum-expression coverage-minimum-expression
              :coverage-minimum-branch coverage-minimum-branch
              :pass-with-no-tests pass-with-no-tests
              :retry retry
              :timeout-ms timeout-ms
              :max-workers max-workers
              :once once)
           (unless continuep
             (return))
           (when next-state
             (if once
                 (setf state next-state)
                 (multiple-value-bind (refreshed-files refreshed-state)
                     (refresh-watch-state system include-dependencies next-state)
                   (setf files refreshed-files
                         state refreshed-state)))))
      when once
        return t
      do (watch-sleep interval))))
