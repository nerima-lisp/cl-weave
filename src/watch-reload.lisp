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
