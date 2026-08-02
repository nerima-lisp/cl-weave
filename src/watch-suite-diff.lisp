(in-package #:cl-weave)

(defun clone-named-suite-table-unlocked (suite-map)
  (let ((cloned (make-hash-table :test #'equal)))
    (maphash
     (lambda (key suite)
       (multiple-value-bind (clone presentp)
           (gethash suite suite-map)
         (when presentp
           (setf (gethash key cloned) clone))))
     *named-suites*)
    cloned))

(defun suite-sibling-ordinal (suite)
  (let ((parent (suite-parent suite))
        (ordinal 0))
    (unless parent
      (return-from suite-sibling-ordinal 0))
    (dolist (child (suite-children parent))
      (when (and (suite-p child)
                 (equal (suite-name child) (suite-name suite)))
        (when (eq child suite)
          (return-from suite-sibling-ordinal ordinal))
        (incf ordinal)))
    (error "cl-weave: suite is not present in its parent: ~S." suite)))

(defun suite-stable-path (suite)
  (let ((path nil)
        (current suite))
    (loop for parent = (suite-parent current)
          while parent
          do (push (cons (suite-name current)
                         (suite-sibling-ordinal current))
                   path)
             (setf current parent))
    path))

(defun changed-pathname-table (pathnames)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (pathname pathnames table)
      (setf (gethash (uiop:ensure-absolute-pathname pathname) table) t))))

(defun changed-registration-p (registration changed-pathnames)
  (let ((owner (gethash registration *registration-owners*)))
    (and owner (gethash owner changed-pathnames))))

(defun foreign-registrations (registrations changed-pathnames)
  (remove-if (lambda (registration)
               (changed-registration-p registration changed-pathnames))
             registrations))

(defun merge-suite-preservation-record (suite record)
  (labels ((merge-pattern (registrations pattern)
             (let ((anchors (make-hash-table :test (function eq)))
                   (merged nil))
               (dolist (slot pattern)
                 (when slot
                   (setf (gethash (car slot) anchors) t)))
               (let ((remaining
                       (remove-if (lambda (registration)
                                    (gethash registration anchors))
                                  registrations)))
                 (dolist (slot pattern)
                   (cond
                     (slot
                      (push (car slot) merged))
                     (remaining
                      (push (pop remaining) merged))))
                 (nconc (nreverse merged) remaining)))))
    (let ((children
            (merge-pattern (suite-children suite)
                           (getf record :children-pattern)))
          (before-all
            (merge-pattern (suite-before-all suite)
                           (getf record :before-all-pattern)))
          (after-all
            (merge-pattern (suite-after-all suite)
                           (getf record :after-all-pattern)))
          (before-each
            (merge-pattern (suite-before-each suite)
                           (getf record :before-each-pattern)))
          (around-each
            (merge-pattern (suite-around-each suite)
                           (getf record :around-each-pattern)))
          (after-each
            (merge-pattern (suite-after-each suite)
                           (getf record :after-each-pattern))))
      (dolist (slot (getf record :children-pattern))
        (when (and slot (suite-p (car slot)))
          (setf (suite-parent (car slot)) suite)))
      (set-suite-hook-lists suite children before-all after-all
                            before-each around-each after-each)
      suite)))

(defun clone-suite-registry-unlocked (root)
  (clone-suite-tree-unlocked root))
(defun clone-registration-owner-table-unlocked (suite-map)
  (let ((cloned (make-hash-table :test #'eq)))
    (maphash
     (lambda (registration pathname)
       (multiple-value-bind (clone suitep)
           (gethash registration suite-map)
         (setf (gethash (if suitep clone registration) cloned)
               pathname)))
     *registration-owners*)
    cloned))
(defun clone-test-registry-state ()
  (with-test-registry-lock
    (multiple-value-bind (root suite-map)
        (clone-suite-registry-unlocked *root-suite*)
      (values root
              (clone-named-suite-table-unlocked suite-map)
              (clone-registration-owner-table-unlocked suite-map)
              *test-registry-generation*))))
(defun test-registry-generation-snapshot ()
  (with-test-registry-lock
    *test-registry-generation*))
(defun publish-test-registry-state
    (expected-generation root named-suites owners generation)
  (with-test-registry-lock
    (when (= expected-generation *test-registry-generation*)
      (setf *root-suite* root
            *current-suite* nil
            *named-suites* named-suites
            *registration-owners* owners
            *test-registry-generation* generation)
      t)))

(defstruct (suite-preservation-node
           (:constructor make-suite-preservation-node (segment suite)))
  segment
  suite
  record
  children)

(defun suite-preservation-record (suite changed-pathnames)
  (labels ((pattern (registrations)
             (mapcar (lambda (registration)
                       (unless (changed-registration-p
                                registration changed-pathnames)
                         (list registration)))
                     registrations)))
    (let ((children (pattern (suite-children suite)))
          (before-all (pattern (suite-before-all suite)))
          (after-all (pattern (suite-after-all suite)))
          (before-each (pattern (suite-before-each suite)))
          (around-each (pattern (suite-around-each suite)))
          (after-each (pattern (suite-after-each suite))))
      (when (or (some (function null) children)
                (some (function null) before-all)
                (some (function null) after-all)
                (some (function null) before-each)
                (some (function null) around-each)
                (some (function null) after-each))
        (list :children-pattern children
              :before-all-pattern before-all
              :after-all-pattern after-all
              :before-each-pattern before-each
              :around-each-pattern around-each
              :after-each-pattern after-each)))))

(defun collect-suite-preservation-records-unlocked
    (root changed-pathnames)
  (let ((tree
          (when root
            (make-suite-preservation-node nil root)))
        (visits 0))
    (when tree
      (let ((stack (list (list :enter root tree))))
        (loop while stack
              do (destructuring-bind (phase suite node)
                     (pop stack)
                   (ecase phase
                     (:enter
                      (incf visits)
                      (setf (suite-preservation-node-record node)
                            (suite-preservation-record
                             suite changed-pathnames))
                      (let ((sibling-ordinals
                              (make-hash-table
                               :test (function equal)))
                            (children nil)
                            (child-work nil))
                        (dolist (child (suite-children suite))
                          (when (suite-p child)
                            (let* ((name (suite-name child))
                                   (ordinal
                                     (gethash
                                      name sibling-ordinals 0))
                                   (child-node
                                     (make-suite-preservation-node
                                      (cons name ordinal)
                                      child)))
                              (setf (gethash name sibling-ordinals)
                                    (1+ ordinal))
                              (push child-node children)
                              (push (list :enter child child-node)
                                    child-work))))
                        (setf (suite-preservation-node-children node)
                              (nreverse children))
                        (push (list :exit suite node) stack)
                        (dolist (work child-work)
                          (push work stack))))
                     (:exit
                      (setf (suite-preservation-node-children node)
                            (delete-if-not
                             (lambda (child)
                               (or
                                (suite-preservation-node-record
                                 child)
                                (suite-preservation-node-children
                                 child)))
                             (suite-preservation-node-children
                              node)))))))))
    (values
     (and tree
          (or (suite-preservation-node-record tree)
              (suite-preservation-node-children tree))
          tree)
     visits)))

(defun collect-suite-preservation-records
    (root changed-pathnames)
  (with-test-registry-lock
    (collect-suite-preservation-records-unlocked
     root changed-pathnames)))

(defun prune-changed-registrations-unlocked
    (root changed-pathnames)
  (let ((stack (when root (list (list :enter root)))))
    (loop while stack
          do (destructuring-bind (phase suite)
                 (pop stack)
               (ecase phase
                 (:enter
                  (push (list :exit suite) stack)
                  (let ((children nil))
                    (dolist (child (suite-children suite))
                      (when (suite-p child)
                        (push child children)))
                    (dolist (child children)
                      (push (list :enter child) stack))))
                 (:exit
                  (let ((children
                          (foreign-registrations
                           (suite-children suite)
                           changed-pathnames))
                        (before-all
                          (foreign-registrations
                           (suite-before-all suite)
                           changed-pathnames))
                        (after-all
                          (foreign-registrations
                           (suite-after-all suite)
                           changed-pathnames))
                        (before-each
                          (foreign-registrations
                           (suite-before-each suite)
                           changed-pathnames))
                        (around-each
                          (foreign-registrations
                           (suite-around-each suite)
                           changed-pathnames))
                        (after-each
                          (foreign-registrations
                           (suite-after-each suite)
                           changed-pathnames)))
                    (set-suite-hook-lists suite children before-all after-all
                                          before-each around-each after-each)))))))
  (note-test-registry-change-unlocked)
  root)

(defun prune-changed-registrations
    (root changed-pathnames)
  (with-test-registry-lock
    (prune-changed-registrations-unlocked
     root changed-pathnames)))

(defun merge-suite-preservation-records-unlocked (root tree)
  (let ((stack (when tree (list (list root tree))))
        (visits 0))
    (loop while stack
          do (destructuring-bind (suite node)
                 (pop stack)
               (let ((record
                       (suite-preservation-node-record node))
                     (child-nodes
                       (suite-preservation-node-children node)))
                 (when record
                   (merge-suite-preservation-record suite record))
                 (when child-nodes
                   (let ((child-index
                           (make-hash-table
                            :test (function equal)))
                         (suite-index
                           (make-hash-table
                            :test (function eq)))
                         (sibling-ordinals
                           (make-hash-table
                            :test (function equal)))
                         (child-work nil))
                     (dolist (child (suite-children suite))
                       (incf visits)
                       (when (suite-p child)
                         (let* ((name (suite-name child))
                                (ordinal
                                  (gethash
                                   name sibling-ordinals 0))
                                (segment (cons name ordinal)))
                           (setf (gethash name sibling-ordinals)
                                 (1+ ordinal)
                                 (gethash segment child-index)
                                 child
                                 (gethash child suite-index)
                                 child))))
                     (dolist (child-node child-nodes)
                       (let* ((segment
                                (suite-preservation-node-segment
                                 child-node))
                              (original-suite
                                (suite-preservation-node-suite
                                 child-node))
                              (child
                                (or
                                 (gethash original-suite suite-index)
                                 (gethash segment child-index))))
                         (unless child
                           (error
                            "Suite path segment not found: ~S"
                            segment))
                         (push (list child child-node)
                               child-work)))
                     (dolist (work child-work)
                       (push work stack)))))))
    (when tree
      (note-test-registry-change-unlocked))
    (values root visits)))

(defun merge-suite-preservation-records (root tree)
  (with-test-registry-lock
    (merge-suite-preservation-records-unlocked
     root tree)))

(defun registry-reachable-objects-unlocked (root)
  (let ((registrations (make-hash-table :test #'eq))
        (suites (make-hash-table :test #'eq))
        (stack (when root (list root))))
    (flet ((record-list (values)
             (dolist (value values)
               (setf (gethash value registrations) t))))
      (loop while stack
            for suite = (pop stack)
            unless (gethash suite suites)
              do (setf (gethash suite registrations) t
                       (gethash suite suites) t)
                 (record-list (suite-before-all suite))
                 (record-list (suite-after-all suite))
                 (record-list (suite-before-each suite))
                 (record-list (suite-around-each suite))
                 (record-list (suite-after-each suite))
                 (dolist (child (suite-children suite))
                   (setf (gethash child registrations) t)
                   (when (suite-p child)
                     (push child stack)))))
    (values registrations suites)))

(defun registry-reachable-objects (root)
  (with-test-registry-lock
    (registry-reachable-objects-unlocked root)))

(defun compact-registration-owner-table-unlocked (root)
  (multiple-value-bind (reachable suites)
      (registry-reachable-objects-unlocked root)
    (declare (ignore suites))
    (let ((compacted (make-hash-table :test #'eq)))
      (maphash
       (lambda (registration pathname)
         (when (gethash registration reachable)
           (setf (gethash registration compacted) pathname)))
       *registration-owners*)
      compacted)))
(defun compact-named-suite-table-unlocked (root)
  (multiple-value-bind (registrations reachable-suites)
      (registry-reachable-objects-unlocked root)
    (declare (ignore registrations))
    (let ((compacted (make-hash-table :test #'equal)))
      (maphash
       (lambda (key suite)
         (when (gethash suite reachable-suites)
           (setf (gethash key compacted) suite)))
       *named-suites*)
      compacted)))
