(in-package #:cl-weave/test)

(describe
  "watch state refresh"
  (it
    "keeps pre-run dates for existing files and initializes new files"
    (let* ((existing #P"/tmp/cl-weave/existing.lisp")
           (added #P"/tmp/cl-weave/added.lisp")
           (next-state (list (cons existing 2)))
           (refreshed-state (list (cons existing 3) (cons added 4))))
      (expect
        (cl-weave::merge-refreshed-watch-state next-state refreshed-state)
        :to-equal
        (list (cons existing 2) (cons added 4)))))
  (it
    "skips test selection when no files changed"
    (let ((state (list (cons #P"/tmp/cl-weave/unchanged.lisp" 1))))
      (with-mocked-functions
        (((symbol-function (quote cl-weave::watch-test-path-selection))
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "test selection must not run"))))
        (expect (getf (cl-weave::watch-cycle-plan state state) :changed) :to-be nil))))
  (it
    "reloads only a changed component and its transitive dependents"
    (let* ((directory (make-test-temporary-directory "watch-forward-dependencies"))
           (system-name (string-downcase (symbol-name (gensym "CL-WEAVE-WATCH-FORWARD-"))))
           (source-names (list "provider" "unrelated" "dependent" "leaf")))
      (unwind-protect (progn
          (dolist (source-name source-names)
            (with-open-file (stream
                (merge-pathnames (make-pathname :name source-name :type "lisp") directory)
                :direction
                :output
                :if-exists
                :supersede
                :if-does-not-exist
                :create)
              (format stream "(in-package #:cl-user)~%")))
          (eval
            (list
              (quote asdf:defsystem)
              system-name
              :pathname
              directory
              :serial
              nil
              :components
              (quote
                ((:file "provider")
                  (:file "unrelated")
                  (:file "dependent" :depends-on ("provider"))
                  (:file "leaf" :depends-on ("dependent"))))))
          (let* ((system (asdf:find-system system-name))
                 (provider (asdf:find-component system "provider")))
            (multiple-value-bind (components pathnames) (cl-weave::incremental-system-reload-plan
                system
                (list (asdf:component-pathname provider)))
              (expect
                (mapcar (function asdf:component-name) components)
                :to-equal
                (list "provider" "dependent" "leaf"))
              (expect
                pathnames
                :to-equal
                (mapcar (function asdf:component-pathname) components)))))
        (when (asdf:find-system system-name nil)
          (asdf:clear-system system-name))
        (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))
  (progn
(it
  "restores changed registrations between foreign sibling slots"
  (let* ((changed-pathname #P"/tmp/cl-weave/watch-changed-registration.lisp")
         (changed (cl-weave::changed-pathname-table (list changed-pathname)))
         (location (list :file changed-pathname))
         (root (cl-weave::make-suite :name "root"))
         (foreign-before
           (cl-weave::make-suite :name "foreign-before" :parent root))
         (old-changed
           (cl-weave::make-suite :name "old-changed" :parent root))
         (foreign-after
           (cl-weave::make-suite :name "foreign-after" :parent root))
         (new-changed
           (cl-weave::make-suite :name "new-changed" :parent root))
         (foreign-before-hook (lambda () :foreign-before))
         (old-changed-hook (lambda () :old-changed))
         (foreign-after-hook (lambda () :foreign-after))
         (new-changed-hook (lambda () :new-changed)))
    (let ((cl-weave::*root-suite* root)
          (cl-weave::*current-suite* root)
          (cl-weave::*registration-owners* (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (dolist (child (list foreign-before old-changed foreign-after))
        (cl-weave::add-child root child))
      (cl-weave::record-registration-owner old-changed location)
      (cl-weave::register-before-each foreign-before-hook)
      (cl-weave::register-before-each old-changed-hook :location location)
      (cl-weave::register-before-each foreign-after-hook)
      (let ((records
              (cl-weave::collect-suite-preservation-records root changed)))
        (cl-weave::prune-changed-registrations root changed)
        (cl-weave::add-child root new-changed)
        (cl-weave::record-registration-owner new-changed location)
        (cl-weave::register-before-each new-changed-hook :location location)
        (cl-weave::merge-suite-preservation-records root records))
      (expect
        (cl-weave::suite-children root)
        :to-equal
        (list foreign-before new-changed foreign-after))
      (expect
        (cl-weave::suite-before-each root)
        :to-equal
        (list foreign-before-hook new-changed-hook foreign-after-hook))
      (expect
        (count old-changed (cl-weave::suite-children root) :test (function eq))
        :to-be
        0)
      (expect
        (count new-changed (cl-weave::suite-children root) :test (function eq))
        :to-be
        1)
      (expect
        (count
          old-changed-hook
          (cl-weave::suite-before-each root)
          :test
          (function eq))
        :to-be
        0)
      (expect
        (count
          new-changed-hook
          (cl-weave::suite-before-each root)
          :test
          (function eq))
        :to-be
        1)
      (expect
        (cl-weave::suite-children-tail root)
        :to-be
        (last (cl-weave::suite-children root)))
      (expect
        (cl-weave::suite-before-each-tail root)
        :to-be
        (last (cl-weave::suite-before-each root))))))
(it
  "preserves duplicate suite identity when an earlier changed sibling is renamed"
  (let* ((changed-pathname
           #P"/tmp/cl-weave/watch-duplicate-suite-rename.lisp")
         (changed
           (cl-weave::changed-pathname-table
            (list changed-pathname)))
         (location (list :file changed-pathname))
         (root (cl-weave::make-suite :name "root"))
         (foreign-before
           (cl-weave::make-suite
            :name "duplicate" :parent root))
         (old-changed
           (cl-weave::make-suite
            :name "duplicate" :parent root))
         (foreign-after
           (cl-weave::make-suite
            :name "duplicate" :parent root))
         (renamed
           (cl-weave::make-suite
            :name "renamed" :parent root))
         (old-hook (lambda () :old))
         (new-hook (lambda () :new)))
    (let ((cl-weave::*root-suite* root)
          (cl-weave::*current-suite* root)
          (cl-weave::*registration-owners*
            (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (dolist
          (child
            (list foreign-before old-changed foreign-after))
        (cl-weave::add-child root child))
      (cl-weave::record-registration-owner
       old-changed location)
      (let ((cl-weave::*current-suite* foreign-after))
        (cl-weave::register-before-each
         old-hook :location location))
      (multiple-value-bind (records collection-visits)
          (cl-weave::collect-suite-preservation-records
           root changed)
        (expect collection-visits :to-be 4)
        (let ((preserved-node
                (car
                 (cl-weave::suite-preservation-node-children
                  records))))
          (expect
            (cl-weave::suite-preservation-node-segment
             preserved-node)
            :to-equal
            (cons "duplicate" 2))
          (expect
            (cl-weave::suite-preservation-node-suite
             preserved-node)
            :to-be
            foreign-after))
        (cl-weave::prune-changed-registrations
         root changed)
        (cl-weave::add-child root renamed)
        (cl-weave::record-registration-owner renamed location)
        (let ((cl-weave::*current-suite* foreign-after))
          (cl-weave::register-before-each
           new-hook :location location))
        (multiple-value-bind (merged-root merge-visits)
            (cl-weave::merge-suite-preservation-records
             root records)
          (expect merged-root :to-be root)
          (expect merge-visits :to-be 3)))
      (expect
        (cl-weave::suite-children root)
        :to-equal
        (list foreign-before renamed foreign-after))
      (expect (cl-weave::suite-parent foreign-before)
        :to-be root)
      (expect (cl-weave::suite-parent renamed)
        :to-be root)
      (expect (cl-weave::suite-parent foreign-after)
        :to-be root)
      (expect
        (cl-weave::suite-before-each foreign-after)
        :to-equal
        (list new-hook))
      (expect
        (cl-weave::suite-children-tail root)
        :to-be
        (last (cl-weave::suite-children root)))
      (expect
        (cl-weave::suite-before-each-tail foreign-after)
        :to-be
        (last
         (cl-weave::suite-before-each foreign-after))))))
(it
  "preserves every duplicate sibling ordinal with linear visits"
  (let* ((width 2048)
         (changed-pathname
           #P"/tmp/cl-weave/watch-duplicate-suite.lisp")
         (changed
           (cl-weave::changed-pathname-table
            (list changed-pathname)))
         (location (list :file changed-pathname))
         (root (cl-weave::make-suite :name "root")))
    (let ((cl-weave::*root-suite* root)
          (cl-weave::*current-suite* root)
          (cl-weave::*registration-owners*
            (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (dotimes (index width)
        (let ((suite
                (cl-weave::make-suite
                 :name "duplicate" :parent root))
              (hook (lambda () index)))
          (cl-weave::add-child root suite)
          (cl-weave::record-registration-owner suite location)
          (let ((cl-weave::*current-suite* suite))
            (cl-weave::register-before-each
             hook :location location))))
      (multiple-value-bind (tree collection-visits)
          (cl-weave::collect-suite-preservation-records
           root changed)
        (expect collection-visits :to-be (1+ width))
        (expect
          (mapcar
            (function cl-weave::suite-preservation-node-segment)
            (cl-weave::suite-preservation-node-children tree))
          :to-equal
          (loop for ordinal below width
                collect (cons "duplicate" ordinal)))
        (let ((replacement-root
                (cl-weave::make-suite :name "root"))
              (replacement-hooks nil))
          (setf cl-weave::*root-suite* replacement-root
                cl-weave::*current-suite* replacement-root)
          (dotimes (index width)
            (let ((suite
                    (cl-weave::make-suite
                     :name "duplicate"
                     :parent replacement-root))
                  (hook (lambda () index)))
              (cl-weave::add-child replacement-root suite)
              (cl-weave::record-registration-owner suite location)
              (let ((cl-weave::*current-suite* suite))
                (cl-weave::register-before-each
                 hook :location location))
              (push hook replacement-hooks)))
          (setf replacement-hooks (nreverse replacement-hooks))
          (multiple-value-bind (merged-root merge-visits)
              (cl-weave::merge-suite-preservation-records
               replacement-root tree)
            (expect merged-root :to-be replacement-root)
            (expect merge-visits :to-be width)
            (let ((children
                    (cl-weave::suite-children replacement-root)))
              (expect (length children) :to-be width)
              (expect
                (every
                  (lambda (suite)
                    (equal (cl-weave::suite-name suite)
                           "duplicate"))
                  children)
                :to-be
                t)
              (expect
                (every
                  (lambda (suite)
                    (eq (cl-weave::suite-parent suite)
                        replacement-root))
                  children)
                :to-be
                t)
              (expect
                (mapcar
                  (lambda (suite)
                    (first
                      (cl-weave::suite-before-each suite)))
                  children)
                :to-equal
                replacement-hooks)
              (expect
                (every
                  (lambda (suite)
                    (eq
                      (cl-weave::suite-before-each-tail suite)
                      (last
                        (cl-weave::suite-before-each suite))))
                  children)
                :to-be
                t)
              (expect
                (cl-weave::suite-children-tail replacement-root)
                :to-be
                (last children)))))))))
  (it
    "deduplicates dependency edges and terminates dependency cycles"
    (let* ((provider (gensym "PROVIDER-"))
           (unrelated (gensym "UNRELATED-"))
           (dependent (gensym "DEPENDENT-"))
           (cycle-peer (gensym "CYCLE-PEER-"))
           (components (list provider unrelated dependent cycle-peer))
           (pathnames (make-hash-table :test (function eq))))
      (setf
        (gethash provider pathnames) #P"/tmp/cl-weave/provider.lisp"
        (gethash unrelated pathnames) #P"/tmp/cl-weave/unrelated.lisp"
        (gethash dependent pathnames) #P"/tmp/cl-weave/dependent.lisp"
        (gethash cycle-peer pathnames) #P"/tmp/cl-weave/cycle-peer.lisp")
      (with-mocked-functions
        (((symbol-function (quote asdf:find-system))
            (lambda (system)
              system))
          ((symbol-function (quote asdf:required-components))
            (lambda (system)
              (declare (ignore system))
              components))
          ((symbol-function (quote asdf:make-operation))
            (lambda (operation-class)
              operation-class))
          ((symbol-function (quote asdf/plan:direct-dependencies))
            (lambda (operation component)
              (cond
                ((eq component dependent)
                  (list
                    (cons operation provider)
                    (cons operation cycle-peer)))
                ((eq component cycle-peer)
                  (list (cons operation dependent)))
                (t nil))))
          ((symbol-function (quote asdf:component-parent))
            (lambda (component)
              (declare (ignore component))
              nil))
          ((symbol-function (quote cl-weave::component-source-pathname))
            (lambda (component)
              (gethash component pathnames))))
        (multiple-value-bind (reload-components reload-pathnames)
            (cl-weave::incremental-system-reload-plan
              (gensym "SYSTEM-")
              (list (gethash provider pathnames)))
          (expect
            reload-components
            :to-equal
            (list provider dependent cycle-peer))
          (expect
            reload-pathnames
            :to-equal
            (list
              (gethash provider pathnames)
              (gethash dependent pathnames)
              (gethash cycle-peer pathnames)))))))
  (it
    "snapshots only the generation before a full system reload"
    (let* ((system (gensym "SYSTEM-"))
           (old-root (cl-weave::make-suite :name "old-root"))
           (clone-calls 0)
           (observed-load nil)
           (cl-weave::*root-suite* old-root)
           (cl-weave::*current-suite* old-root)
           (cl-weave::*named-suites* (make-hash-table :test (function equal)))
           (cl-weave::*registration-owners*
             (make-hash-table :test (function eq)))
           (cl-weave::*test-registry-generation* 11))
      (with-mocked-functions
        (((symbol-function (quote cl-weave::clone-test-registry-state))
            (lambda ()
              (incf clone-calls)
              (values
                cl-weave::*root-suite*
                (make-hash-table :test (function equal))
                (make-hash-table :test (function eq))
                cl-weave::*test-registry-generation*)))
          ((symbol-function (quote asdf:load-system))
            (lambda (loaded-system &key force)
              (setf observed-load (list loaded-system force))
              (cl-weave::register-suite "replacement" (lambda () nil))
              t)))
        (expect
          (cl-weave::atomic-full-system-reload system)
          :to-be
          t)
        (expect clone-calls :to-be 0)
        (expect observed-load :to-equal (list system t))
        (expect
          (eq cl-weave::*root-suite* old-root)
          :to-be
          nil)
        (expect
          cl-weave::*test-registry-generation*
          :to-be-greater-than
          11))))
))
(it
  "excludes module-containment and self-referential ASDF plan edges from the reload set"
  (let* ((directory
           (make-test-temporary-directory "watch-ancestor-self-dependency"))
         (system-name
           (string-downcase
            (symbol-name (gensym "CL-WEAVE-WATCH-ANCESTOR-")))))
    (unwind-protect
         (progn
           (dolist (source-name (list "inner-a" "inner-b" "leaf"))
             (with-open-file (stream
                 (merge-pathnames
                  (make-pathname :name source-name :type "lisp")
                  directory)
                 :direction :output
                 :if-exists :supersede
                 :if-does-not-exist :create)
               (format stream "(in-package #:cl-user)~%")))
           (eval
             (list
               (quote asdf:defsystem)
               system-name
               :pathname directory
               :components
               (quote
                 ((:module "inner"
                   :pathname ""
                   :serial t
                   :components ((:file "inner-a") (:file "inner-b")))
                  (:file "leaf" :depends-on ("inner"))))))
           (let* ((system (asdf:find-system system-name))
                  (module (asdf:find-component system "inner"))
                  (inner-a (asdf:find-component module "inner-a")))
             ;; MODULE is its own component with children INNER-A/INNER-B, and
             ;; the system itself both appear in REQUIRED-COMPONENTS. ASDF's
             ;; own plan graph reports containment edges between a module and
             ;; its children (e.g. INNER's COMPILE-OP depends on INNER-A) and
             ;; self edges (e.g. the system's COMPILE-OP "depends on" itself)
             ;; alongside the real cross-file dependency edges. Without the
             ;; ANCESTOR-P and self-dependency guards in
             ;; INCREMENTAL-SYSTEM-RELOAD-PLAN, changing INNER-A would ripple
             ;; through the MODULE containment edge up to LEAF (which only
             ;; really depends on the MODULE component, not on INNER-A
             ;; directly) and spuriously reload it too.
             (multiple-value-bind (components pathnames)
                 (cl-weave::incremental-system-reload-plan
                   system
                   (list (asdf:component-pathname inner-a)))
               (expect
                 (mapcar (function asdf:component-name) components)
                 :to-equal
                 (list "inner-a" "inner-b"))
               (expect
                 pathnames
                 :to-equal
                 (mapcar (function asdf:component-pathname) components)))))
      (when (asdf:find-system system-name nil)
        (asdf:clear-system system-name))
      (uiop:delete-directory-tree directory
                                  :validate t
                                  :if-does-not-exist :ignore))))
