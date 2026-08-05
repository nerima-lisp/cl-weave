(in-package #:cl-weave)

(defun component-ancestor-p (ancestor component)
  "True when ANCESTOR is a proper parent of COMPONENT in the ASDF component tree."
  (loop for parent = (asdf:component-parent component)
          then (asdf:component-parent parent)
        while parent
        thereis (eq parent ancestor)))

(defun seed-reload-queue (components changed component-set reload-set)
  "Populate COMPONENT-SET with every component in COMPONENTS, mark RELOAD-SET
   for each whose source pathname appears in CHANGED, and return the initial
   breadth-first queue of directly-changed components."
  (let ((queue nil))
    (dolist (component components queue)
      (setf (gethash component component-set) t)
      (let ((source (component-source-pathname component)))
        (when (and source (gethash source changed))
          (setf (gethash component reload-set) t)
          (push component queue))))))

(defun reload-plan-operations ()
  "The ASDF operations whose direct dependencies determine incremental reload order."
  (list (asdf:make-operation (quote asdf:prepare-op))
        (asdf:make-operation (quote asdf:compile-op))
        (asdf:make-operation (quote asdf:load-op))))

(defun component-reverse-dependencies (components component-set)
  "Return a table mapping each component in COMPONENT-SET to the components,
   among COMPONENTS, that directly depend on it. Ancestor/descendant pairs are
   excluded: ASDF's own component tree already reloads those together."
  (let ((reverse-dependencies (make-hash-table :test (function eq)))
        (reverse-dependency-membership (make-hash-table :test (function eq)))
        (operations (reload-plan-operations)))
    (dolist (component components reverse-dependencies)
      (dolist (operation operations)
        (dolist (dependency (asdf/plan:direct-dependencies operation component))
          (let ((dependency-component (cdr dependency)))
            (when (and (gethash dependency-component component-set)
                       (not (eq dependency-component component))
                       (not (component-ancestor-p dependency-component component))
                       (not (component-ancestor-p component dependency-component)))
              (let ((dependents
                      (or (gethash dependency-component reverse-dependency-membership)
                          (setf (gethash dependency-component reverse-dependency-membership)
                                (make-hash-table :test (function eq))))))
                (unless (gethash component dependents)
                  (setf (gethash component dependents) t)
                  (push component (gethash dependency-component reverse-dependencies)))))))))))

(defun propagate-reload-set (queue reverse-dependencies reload-set)
  "Breadth-first expand RELOAD-SET to every transitive dependent reachable from QUEUE."
  (loop while queue
        for component = (pop queue)
        do (dolist (dependent (gethash component reverse-dependencies))
             (unless (gethash dependent reload-set)
               (setf (gethash dependent reload-set) t)
               (push dependent queue)))))

(defun reload-plan-results (components reload-set)
  "Return the members of RELOAD-SET, in COMPONENTS order, as parallel component
   and source-pathname lists."
  (let ((reload-components nil)
        (reload-pathnames nil))
    (dolist (component components)
      (let ((source (component-source-pathname component)))
        (when (and source (gethash component reload-set))
          (push component reload-components)
          (push source reload-pathnames))))
    (values (nreverse reload-components) (nreverse reload-pathnames))))

(defun incremental-system-reload-plan (system changed-pathnames)
  (let* ((system (asdf:find-system system))
         (components (asdf:required-components system))
         (component-set (make-hash-table :test (function eq)))
         (changed (changed-pathname-table changed-pathnames))
         (reload-set (make-hash-table :test (function eq)))
         (queue (seed-reload-queue components changed component-set reload-set)))
    (propagate-reload-set
     queue
     (component-reverse-dependencies components component-set)
     reload-set)
    (reload-plan-results components reload-set)))

  (defun asdf-definition-pathname-p (pathname)
    (let ((type (pathname-type pathname)))
      (and type (string-equal type "asd"))))

  (defun atomic-full-system-reload (system)
  (let ((expected-generation
          (test-registry-generation-snapshot)))
    (multiple-value-bind (root named-suites owners generation)
        (let ((*root-suite* nil)
              (*current-suite* nil)
              (*named-suites* (make-hash-table :test #'equal))
              (*registration-owners* (make-hash-table :test #'eq))
              (*test-registry-generation*
                (1+ expected-generation)))
          (asdf:load-system system :force t)
          (values *root-suite*
                  *named-suites*
                  *registration-owners*
                  *test-registry-generation*))
      (unless
          (publish-test-registry-state
           expected-generation
           root
           named-suites
           owners
           generation)
        (error
         "cl-weave: test registry changed during full reload; reload result was discarded."))))
  t)

(defun compile-and-load-components (components)
  "Compile then load each component in COMPONENTS, in the order an incremental
   reload requires: every dependency compiled and loaded before its dependents."
  (let ((compile-op (asdf:make-operation (quote asdf:compile-op)))
        (load-op (asdf:make-operation (quote asdf:load-op))))
    (dolist (component components)
      (asdf:perform compile-op component)
      (asdf:perform load-op component))))

(defun reload-components-into-cloned-registry-unlocked
    (reload-components reload-pathnames)
  "Run within the dynamic bindings ATOMIC-INCREMENTAL-SYSTEM-RELOAD establishes
   over a cloned registry: preserve the changed suites' foreign registrations,
   prune and reload just those suites, then return the updated *ROOT-SUITE*,
   *NAMED-SUITES*, *REGISTRATION-OWNERS*, and generation."
  (let* ((changed (changed-pathname-table reload-pathnames))
         (records (collect-suite-preservation-records-unlocked *root-suite* changed)))
    (prune-changed-registrations-unlocked *root-suite* changed)
    (compile-and-load-components reload-components)
    (merge-suite-preservation-records-unlocked *root-suite* records)
    (setf *registration-owners*
          (compact-registration-owner-table-unlocked *root-suite*)
          *named-suites*
          (compact-named-suite-table-unlocked *root-suite*))
    (values *root-suite* *named-suites* *registration-owners*
            *test-registry-generation*)))

(defun atomic-incremental-system-reload (system changed-pathnames)
  (multiple-value-bind (reload-components reload-pathnames)
      (incremental-system-reload-plan system changed-pathnames)
    (when reload-components
      (multiple-value-bind
            (cloned-root cloned-named-suites cloned-owners expected-generation)
          (clone-test-registry-state)
        (multiple-value-bind (root named-suites owners generation)
            (let ((*root-suite* cloned-root)
                  (*current-suite* nil)
                  (*named-suites* cloned-named-suites)
                  (*registration-owners* cloned-owners)
                  (*test-registry-generation* expected-generation))
              (reload-components-into-cloned-registry-unlocked
               reload-components
               reload-pathnames))
          (unless
              (publish-test-registry-state
               expected-generation
               root
               named-suites
               owners
               generation)
            (error
             "cl-weave: test registry changed during incremental reload; ~
              reload result was discarded.")))))
    t))

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
