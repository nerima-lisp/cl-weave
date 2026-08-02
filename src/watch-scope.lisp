(in-package #:cl-weave)

(defvar *watch-test-dependency-index* nil)

(defvar *watch-registered-test-files* nil)

(defvar *watch-index-suite* nil)

(defvar *watch-index-generation* -1)

(defun selective-watch-location-filter (changed)
  (multiple-value-bind (index registered-files)
      (ensure-watch-test-index (root-suite))
    (declare (ignore index))
    (let ((registered (make-hash-table :test #'equal)))
      (dolist (pathname registered-files)
        (setf (gethash pathname registered) t))
      (when (and changed
                 registered-files
                 (every (lambda (pathname)
                          (gethash pathname registered))
                        changed))
        changed))))

(defun test-effective-watch-dependencies (test)
  (let ((seen (make-hash-table :test #'equal))
        (dependencies '()))
    (labels ((add-dependency (pathname)
               (unless (gethash pathname seen)
                 (setf (gethash pathname seen) t)
                 (push pathname dependencies))))
      (let ((source (test-location-pathname test)))
        (when source
          (add-dependency source)))
      (dolist (pathname (test-case-watch-dependencies test))
        (add-dependency pathname)))
    (nreverse dependencies)))

(defun watch-test-path-selection (suite changed)
  "Return selected test paths and true when every changed file is declared."
  (multiple-value-bind (index registered-files)
      (ensure-watch-test-index suite)
    (declare (ignore registered-files))
    (let ((selected (quote ()))
          (seen (make-hash-table :test (function equal))))
      (dolist (pathname changed (values (nreverse selected) t))
        (multiple-value-bind (matches presentp)
            (gethash pathname index)
          (unless presentp
            (return-from watch-test-path-selection (values nil nil)))
          (dolist (path matches)
            (unless (gethash path seen)
              (setf (gethash path seen) t)
              (push path selected))))))))

(defun watch-scope (location-filter test-path-filter)
  (if (or location-filter test-path-filter) :changed-tests :full-suite))

(defun watch-cycle-plan (state new-state)
  (let ((initialp (null state))
        (changed (if state
                     (changed-pathnames state new-state)
                     (mapcar (function car) new-state))))
    (when (and state (null changed))
      (return-from watch-cycle-plan
        (list :changed nil
              :location-filter nil
              :scope :full-suite
              :initialp nil
              :new-state new-state)))
    (let ((location-filter
            (and state (selective-watch-location-filter changed))))
      (multiple-value-bind (test-path-filter selectivep)
          (if (and state (null location-filter))
              (watch-test-path-selection (root-suite) changed)
              (values nil nil))
        (declare (ignore selectivep))
        (append (list :changed changed
                      :location-filter location-filter)
                (when test-path-filter
                  (list :test-path-filter test-path-filter))
                (list :scope (watch-scope location-filter test-path-filter)
                      :initialp initialp
                      :new-state new-state))))))

(defun watch-sleep (seconds)
  (sleep seconds))

(defun run-system-argument-pairs (&key reporter stream name-filter location-filter
                                  test-path-filter
                                  shard order seed bail coverage
                                  coverage-output coverage-report-directory
                                  coverage-include-pathnames coverage-exclude-pathnames
                                  coverage-minimum-expression coverage-minimum-branch
                                  pass-with-no-tests retry
                                  timeout-ms max-workers)
  (append (list :reporter reporter
                :stream stream
                :name-filter name-filter
                :location-filter location-filter
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
                :max-workers max-workers)
          (when test-path-filter
            (list :test-path-filter test-path-filter))))

(defvar *watch-incremental-reload-p* nil)

(defvar *watch-changed-pathnames* nil)

(defconstant +watch-test-index-build-attempts+ 3)

(defun copy-watch-index-designator (value)
  (if (stringp value)
      (copy-seq value)
      value))

(defun copy-watch-index-name (name)
  (unless (stringp name)
    (error "cl-weave: watch index name must be a string."))
  (copy-seq name))

(defun snapshot-watch-test-location (location)
  (when location
    (list :file
          (copy-watch-index-designator
           (getf location :file)))))

(defun snapshot-watch-test-suite-unlocked (suite)
  (flet ((snapshot-test (test)
           (make-test-case
            :name
            (copy-watch-index-name
             (test-case-name test))
            :location
            (snapshot-watch-test-location
             (test-case-location test))
            :watch-dependencies
            (mapcar (function copy-watch-index-designator)
                    (test-case-watch-dependencies test)))))
    (let* ((snapshot-root
             (make-suite
              :name
              (copy-watch-index-name
               (suite-name suite))))
           (worklist (list (cons suite snapshot-root))))
      (loop while worklist
            for entry = (pop worklist)
            for current-suite = (car entry)
            for snapshot-suite = (cdr entry)
            do
               (let ((children nil)
                     (tail nil))
                 (dolist (child (suite-children current-suite))
                   (let ((snapshot-child
                           (cond
                             ((suite-p child)
                              (make-suite
                               :name
                               (copy-watch-index-name
                                (suite-name child))
                               :parent snapshot-suite))
                             ((test-case-p child)
                              (snapshot-test child)))))
                     (when snapshot-child
                       (let ((cell (list snapshot-child)))
                         (if tail
                             (setf (cdr tail) cell)
                             (setf children cell))
                         (setf tail cell))
                       (when (suite-p child)
                         (push (cons child snapshot-child)
                               worklist)))))
                 (setf (suite-children snapshot-suite) children
                       (suite-children-tail snapshot-suite) tail))
            finally (return snapshot-root)))))

(defun snapshot-watch-test-index-input-unlocked (suite)
  (values (snapshot-watch-test-suite-unlocked suite)
          *test-registry-generation*))

(defun build-watch-test-index-unlocked (suite)
  (let ((index (make-hash-table :test (function equal)))
        (seen-files (make-hash-table :test (function equal)))
        (registered-files (quote ()))
        (worklist (list (cons nil suite))))
    (loop while worklist
          for entry = (pop worklist)
          for parent-suite = (car entry)
          for node = (cdr entry)
          do
             (cond
               ((suite-p node)
                (dolist (child
                         (reverse (copy-list (suite-children node))))
                  (push (cons node child) worklist)))
               ((test-case-p node)
                (let ((path (test-path parent-suite node))
                      (source (test-location-pathname node)))
                  (when (and source
                             (not (gethash source seen-files)))
                    (setf (gethash source seen-files) t)
                    (push source registered-files))
                  (dolist (dependency
                           (test-effective-watch-dependencies node))
                    (push path (gethash dependency index)))))))
    (values index registered-files)))

(defun watch-test-index-cache-valid-p-unlocked (suite)
  (and (eq suite *watch-index-suite*)
       (= *watch-index-generation*
          *test-registry-generation*)))

(defun cached-watch-test-index-unlocked (suite)
  (when (watch-test-index-cache-valid-p-unlocked suite)
    (values *watch-test-dependency-index*
            *watch-registered-test-files*
            t)))

(defun publish-watch-test-index-unlocked
    (suite generation index registered-files)
  (cond
    ((watch-test-index-cache-valid-p-unlocked suite)
     (values *watch-test-dependency-index*
             *watch-registered-test-files*
             t))
    ((= generation *test-registry-generation*)
     (setf *watch-test-dependency-index* index
           *watch-registered-test-files* registered-files
           *watch-index-suite* suite
           *watch-index-generation* generation)
     (values index registered-files t))
    (t
     (values nil nil nil))))

(defun ensure-watch-test-index-unlocked (suite)
  "Build without holding the registry lock; callers must not hold that lock."
  (loop repeat +watch-test-index-build-attempts+
        do
           (multiple-value-bind
                 (cached-index cached-files cached-p
                  snapshot generation)
               (with-test-registry-lock
                 (multiple-value-bind
                       (index registered-files valid-p)
                     (cached-watch-test-index-unlocked suite)
                   (if valid-p
                       (values index registered-files t nil nil)
                       (multiple-value-bind
                             (new-snapshot new-generation)
                           (snapshot-watch-test-index-input-unlocked
                            suite)
                         (values nil nil nil
                                 new-snapshot
                                 new-generation)))))
             (when cached-p
               (return-from ensure-watch-test-index-unlocked
                 (values cached-index cached-files)))
             (multiple-value-bind (index registered-files)
                 (build-watch-test-index-unlocked snapshot)
               (multiple-value-bind
                     (published-index published-files published-p)
                   (with-test-registry-lock
                     (publish-watch-test-index-unlocked
                      suite generation index registered-files))
                 (when published-p
                   (return-from ensure-watch-test-index-unlocked
                     (values published-index published-files)))))))
  (multiple-value-bind (index registered-files valid-p)
      (with-test-registry-lock
        (cached-watch-test-index-unlocked suite))
    (if valid-p
        (values index registered-files)
        (error
         "Test registry changed during ~D watch index build attempts."
         +watch-test-index-build-attempts+))))

(defun ensure-watch-test-index (suite)
  (ensure-watch-test-index-unlocked suite))
