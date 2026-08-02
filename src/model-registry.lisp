(in-package #:cl-weave)

;;;; The global test registry: the suite tree every registration mutates,
;;;; the lock and generation counter that make those mutations observable to
;;;; watch mode, and the copying primitives that hand a caller a stable view
;;;; of the tree while tests keep registering.

(defvar *root-suite* nil)
(defvar *current-suite* nil)
(defvar *named-suites* (make-hash-table :test #'equal))
(defvar *registration-owners* (make-hash-table :test (function eq)))

(defvar *test-registry-generation* 0)
#+sb-thread
(defvar *test-registry-lock*
  (sb-thread:make-mutex :name "cl-weave test registry"))
(define-conditional-lock-macro with-test-registry-lock () *test-registry-lock*)

(defun note-test-registry-change-unlocked ()
  (incf *test-registry-generation*))
(defun note-test-registry-change ()
  (with-test-registry-lock
    (note-test-registry-change-unlocked)))

(defun registration-location-pathname (location)
  (let ((file (and location (getf location :file))))
    (and file (uiop:ensure-absolute-pathname file))))

(defun record-registration-owner-unlocked (registration pathname)
  (when pathname
    (setf (gethash registration *registration-owners*) pathname))
  registration)
(defun record-registration-owner (registration location)
  (let ((pathname (registration-location-pathname location)))
    (with-test-registry-lock
      (record-registration-owner-unlocked registration pathname)
      (note-test-registry-change-unlocked)
      registration)))

(defun root-suite-unlocked ()
  (if *root-suite*
      (values *root-suite* nil)
      (values (setf *root-suite* (make-suite :name "root")) t)))
(defun root-suite ()
  (with-test-registry-lock
    (multiple-value-bind (root created-p)
        (root-suite-unlocked)
      (when created-p
        (note-test-registry-change-unlocked))
      root)))

(defun copy-list-with-tail (values)
  (loop with head = nil
        with tail = nil
        for value in values
        for cell = (list value)
        do (if tail
               (setf (cdr tail) cell
                     tail cell)
               (setf head cell
                     tail cell))
        finally (return (values head tail))))

(defun copy-suite-children-with-tail (children suite-map)
  (loop with head = nil
        with tail = nil
        for child in children
        for value = (if (suite-p child)
                        (gethash child suite-map)
                        child)
        for cell = (list value)
        do (if tail
               (setf (cdr tail) cell
                     tail cell)
               (setf head cell
                     tail cell))
        finally (return (values head tail))))

(defun clone-suite-tree-unlocked (root)
  (let ((suite-map (make-hash-table :test (function eq)))
        (pending (and root (list (cons root nil)))))
    ;; Allocate suite shells before rebuilding child and hook list spines.
    (loop while pending
          for entry = (pop pending)
          for suite = (car entry)
          for parent = (cdr entry)
          for clone = (make-suite :name (suite-name suite)
                                  :parent parent
                                  :focus (suite-focus suite)
                                  :skip-reason (suite-skip-reason suite)
                                  :todo-reason (suite-todo-reason suite)
                                  :execution-mode (suite-execution-mode suite))
          do (setf (gethash suite suite-map) clone)
             (dolist (child (suite-children suite))
               (when (suite-p child)
                 (push (cons child clone) pending))))
    (maphash
     (lambda (suite clone)
       (multiple-value-bind (children children-tail)
           (copy-suite-children-with-tail (suite-children suite) suite-map)
         (setf (suite-children clone) children
               (suite-children-tail clone) children-tail))
       (multiple-value-bind (before-each before-each-tail)
           (copy-list-with-tail (suite-before-each suite))
         (setf (suite-before-each clone) before-each
               (suite-before-each-tail clone) before-each-tail))
       (multiple-value-bind (after-each after-each-tail)
           (copy-list-with-tail (suite-after-each suite))
         (setf (suite-after-each clone) after-each
               (suite-after-each-tail clone) after-each-tail))
       (multiple-value-bind (before-all before-all-tail)
           (copy-list-with-tail (suite-before-all suite))
         (setf (suite-before-all clone) before-all
               (suite-before-all-tail clone) before-all-tail))
       (multiple-value-bind (after-all after-all-tail)
           (copy-list-with-tail (suite-after-all suite))
         (setf (suite-after-all clone) after-all
               (suite-after-all-tail clone) after-all-tail))
       (multiple-value-bind (around-each around-each-tail)
           (copy-list-with-tail (suite-around-each suite))
         (setf (suite-around-each clone) around-each
               (suite-around-each-tail clone) around-each-tail)))
     suite-map)
    (values (and root (gethash root suite-map)) suite-map)))
(defun snapshot-suite (suite)
  (with-test-registry-lock
    (let ((tree-root suite))
      (loop while (and tree-root (suite-parent tree-root))
            do (setf tree-root (suite-parent tree-root)))
      (multiple-value-bind (clone suite-map)
          (clone-suite-tree-unlocked tree-root)
        (or (gethash suite suite-map) clone)))))

(defun current-or-root-suite-unlocked ()
  (or *current-suite*
      (root-suite-unlocked)))
(defun clear-tests ()
  (with-test-registry-lock
    (setf *root-suite* nil
          *current-suite* nil
          *named-suites* (make-hash-table :test (function equal))
          *registration-owners* (make-hash-table :test (function eq)))
    (note-test-registry-change-unlocked)
    t))

(defmacro append-to-tail-list (suite head tail value)
  (let ((suite-var (gensym "SUITE"))
        (value-var (gensym "VALUE"))
        (cell-var (gensym "CELL")))
    `(let* ((,suite-var ,suite)
            (,value-var ,value)
            (,cell-var (list ,value-var)))
       (if (,tail ,suite-var)
           (setf (cdr (,tail ,suite-var)) ,cell-var
                 (,tail ,suite-var) ,cell-var)
           (setf (,head ,suite-var) ,cell-var
                 (,tail ,suite-var) ,cell-var))
       ,value-var)))

(defun set-suite-hook-lists
    (suite children before-all after-all before-each around-each after-each)
  "Replace SUITE's children and hook lists, recomputing each tail pointer."
  (setf (suite-children suite) children
        (suite-children-tail suite) (last children)
        (suite-before-all suite) before-all
        (suite-before-all-tail suite) (last before-all)
        (suite-after-all suite) after-all
        (suite-after-all-tail suite) (last after-all)
        (suite-before-each suite) before-each
        (suite-before-each-tail suite) (last before-each)
        (suite-around-each suite) around-each
        (suite-around-each-tail suite) (last around-each)
        (suite-after-each suite) after-each
        (suite-after-each-tail suite) (last after-each)))

(defmacro define-tail-registration (name head tail)
  `(defun ,name (function &key location)
     (let ((pathname (registration-location-pathname location)))
       (with-test-registry-lock
         (let ((registration
                 (append-to-tail-list (current-or-root-suite-unlocked)
                                      ,head
                                      ,tail
                                      function)))
           (record-registration-owner-unlocked registration pathname)
           (note-test-registry-change-unlocked)
           registration)))))

(defun add-owned-child-unlocked (parent child pathname)
  (append-to-tail-list parent
                       suite-children
                       suite-children-tail
                       child)
  (record-registration-owner-unlocked child pathname)
  (note-test-registry-change-unlocked)
  child)
(defun add-child (parent child)
  (with-test-registry-lock
    (add-owned-child-unlocked parent child nil)))
