(in-package #:cl-weave)

;;;; Equality classes over shrink candidates.
;;;;
;;;; Deduplicating shrink candidates cannot just call EQUAL: a candidate may
;;;; be circular, and two structurally identical candidates must collapse to
;;;; one even when their subterms are shared differently. So candidates are
;;;; modelled as a graph and coloured by refinement until the partition is
;;;; stable, which terminates on cycles and answers "same value" rather than
;;;; "same traversal". property-generators-shrinking.lisp is the only caller.

(progn
  (defun eq-hash-test-p (hash-test)
    (or (eq hash-test (quote eq))
        (eq hash-test (function eq))
        (eq hash-test (symbol-function (quote eq)))))

  (defun eql-hash-test-p (hash-test)
    (or (eq hash-test (quote eql))
        (eq hash-test (function eql))
        (eq hash-test (symbol-function (quote eql)))))

  (defun candidate-hash-test-token (hash-test)
    (cond
      ((eq-hash-test-p hash-test) :eq)
      ((eql-hash-test-p hash-test) :eql)
      ((equal-hash-test-p hash-test) :equal)
      ((equalp-hash-test-p hash-test) :equalp)
      (t hash-test)))

  (defun candidate-hash-test-function (test-token)
    (case test-token
      (:eq (function eq))
      (:eql (function eql))
      (:equal (function equal))
      (:equalp (function equalp))
      (otherwise test-token)))

  (defstruct candidate-equality-node
    object
    test
    base
    unordered-p
    children
    parents
    (remaining 0)
    (color 0))

  (defun candidate-equality-class-ids (candidates hash-test)
    (let ((nodes nil)
          (pending nil)
          (atom-number 0)
          (container-caches (make-hash-table :test (function eq)))
          (atom-caches (make-hash-table :test (function eq))))
      (labels
          ((cache-for (test-token caches test)
             (multiple-value-bind (cache present-p)
                 (gethash test-token caches)
               (unless present-p
                 (setf cache (make-hash-table :test test)
                       (gethash test-token caches) cache))
               cache))
           (make-node (object test-token &key base unordered-p children expand-p)
             (let ((node
                     (make-candidate-equality-node
                      :object object
                      :test test-token
                      :base base
                      :unordered-p unordered-p
                      :children children)))
               (push node nodes)
               (when expand-p
                 (push node pending))
               node))
           (ensure-node (object test-token)
             (let* ((test
                      (candidate-hash-test-function test-token))
                    (equalp-test-p (eq test-token :equalp)))
               (if (and (member test-token (quote (:equal :equalp))) (candidate-container-p object equalp-test-p))
                   (let ((cache
                           (cache-for
                            test-token
                            container-caches
                            (function eq))))
                     (multiple-value-bind (node present-p)
                         (gethash object cache)
                       (unless present-p
                         (setf node
                               (make-node
                                object
                                test-token
                                :expand-p t)
                               (gethash object cache) node))
                       node))
                   (let ((cache
                           (cache-for test-token atom-caches test)))
                     (multiple-value-bind (node present-p)
                         (gethash object cache)
                       (unless present-p
                         (setf node
                               (make-node
                                object
                                test-token
                                :base
                                (list :atom (incf atom-number)))
                               (gethash object cache) node))
                       node)))))
           (entry-node (key value table-test value-test)
             (make-node
              nil
              value-test
              :base (list :entry)
              :children
              (list
               (ensure-node
                key
                (candidate-hash-test-token table-test))
               (ensure-node value value-test)))))
        (let* ((root-test (candidate-hash-test-token hash-test))
               (roots
                 (mapcar
                  (lambda (candidate)
                    (ensure-node candidate root-test))
                  candidates)))
          (loop while pending
                for node = (pop pending)
                for object = (candidate-equality-node-object node)
                for test-token = (candidate-equality-node-test node)
                do
                   (cond
                     ((consp object)
                      (setf
                       (candidate-equality-node-base node) (list :cons)
                       (candidate-equality-node-children node)
                       (list
                        (ensure-node (car object) test-token)
                        (ensure-node (cdr object) test-token))))
                     ((arrayp object)
                      (setf
                       (candidate-equality-node-base node)
                       (if (vectorp object)
                           (list :vector (length object))
                           (list :array (array-dimensions object)))
                       (candidate-equality-node-children node)
                       (loop for index below
                             (if (vectorp object)
                                 (length object)
                                 (array-total-size object))
                             collect
                             (ensure-node
                              (row-major-aref object index)
                              test-token))))
                     ((hash-table-p object)
                      (let ((entries nil)
                            (table-test (hash-table-test object)))
                        (maphash
                         (lambda (key value)
                           (push
                            (entry-node
                             key value table-test test-token)
                            entries))
                         object)
                        (setf
                         (candidate-equality-node-base node)
                         (list
                          :hash-table
                          table-test
                          (hash-table-count object))
                         (candidate-equality-node-unordered-p node) t
                         (candidate-equality-node-children node) entries)))
                     ((typep object (quote structure-object))
                      #+sbcl
                      (let ((boundness nil)
                            (children nil))
                        (dolist
                            (slot
                             (sb-mop:class-slots (class-of object)))
                          (let* ((name
                                   (sb-mop:slot-definition-name slot))
                                 (bound-p
                                   (slot-boundp object name)))
                            (push (not (null bound-p)) boundness)
                            (when bound-p
                              (push
                               (ensure-node
                                (slot-value object name)
                                test-token)
                               children))))
                        (setf
                         (candidate-equality-node-base node)
                         (list
                          :structure
                          (class-of object)
                          (nreverse boundness))
                         (candidate-equality-node-children node)
                         (nreverse children)))
                      #-sbcl
                      (error
                       "Cycle-safe structure equality is unsupported on this implementation."))))
          (dolist (node nodes)
            (setf
             (candidate-equality-node-remaining node)
             (length (candidate-equality-node-children node)))
            (dolist (child (candidate-equality-node-children node))
              (push node (candidate-equality-node-parents child))))
          (let ((queue nil)
                (processed nil)
                (fixed-class-count 0)
                (fixed-classes (make-hash-table :test (function equal))))
            (dolist (node nodes)
              (when (zerop (candidate-equality-node-remaining node))
                (push node queue)))
            (loop while queue
                  for node = (pop queue)
                  do
                     (push node processed)
                     (dolist (parent
                              (candidate-equality-node-parents node))
                       (when
                           (zerop
                            (decf
                             (candidate-equality-node-remaining
                              parent)))
                         (push parent queue))))
            (labels
                ((ordered-colors (node color-function)
                   (let ((colors
                           (mapcar
                            color-function
                            (candidate-equality-node-children node))))
                     (if (candidate-equality-node-unordered-p node)
                         (sort colors (function <))
                         colors))))
              (dolist (node (nreverse processed))
                (let* ((descriptor
                         (list
                          (candidate-equality-node-base node)
                          (ordered-colors
                           node
                           (lambda (child)
                             (candidate-equality-node-color child)))))
                       (color
                         (multiple-value-bind (existing present-p)
                             (gethash descriptor fixed-classes)
                           (if present-p
                               existing
                               (setf
                                (gethash descriptor fixed-classes)
                                (incf fixed-class-count))))))
                  (setf (candidate-equality-node-color node) color)))
              (let ((unresolved
                      (remove-if
                       (lambda (node)
                         (zerop
                          (candidate-equality-node-remaining node)))
                       nodes)))
                (when unresolved
                  (labels
                      ((encoded-child-color (child)
                         (if
                             (zerop
                              (candidate-equality-node-remaining child))
                             (ash
                              (candidate-equality-node-color child)
                              1)
                             (1+
                              (ash
                               (candidate-equality-node-color child)
                               1))))
                       (assign-partition (descriptor-function)
                         (let ((classes
                                 (make-hash-table
                                  :test (function equal)))
                               (class-count 0)
                               (next-colors
                                 (make-hash-table
                                  :test (function eq))))
                           (dolist (node unresolved)
                             (let* ((descriptor
                                      (funcall
                                       descriptor-function
                                       node))
                                    (color
                                      (multiple-value-bind
                                          (existing present-p)
                                          (gethash descriptor classes)
                                        (if present-p
                                            existing
                                            (setf
                                             (gethash descriptor classes)
                                             (incf class-count))))))
                               (setf (gethash node next-colors) color)))
                           (values next-colors class-count))))
                    (multiple-value-bind (colors class-count)
                        (assign-partition
                         (lambda (node)
                           (list
                            (candidate-equality-node-base node)
                            (ordered-colors
                             node
                             (lambda (child)
                               (if
                                   (zerop
                                    (candidate-equality-node-remaining
                                     child))
                                   (ash
                                    (candidate-equality-node-color child)
                                    1)
                                   1))))))
                      (maphash
                       (lambda (node color)
                         (setf
                          (candidate-equality-node-color node)
                          color))
                       colors)
                      (loop
                        (multiple-value-bind
                            (next-colors next-class-count)
                            (assign-partition
                             (lambda (node)
                               (list
                                (candidate-equality-node-color node)
                                (candidate-equality-node-base node)
                                (ordered-colors
                                 node
                                 (function encoded-child-color)))))
                          (when (= next-class-count class-count)
                            (maphash
                             (lambda (node color)
                               (setf
                                (candidate-equality-node-color node)
                                (+ fixed-class-count color)))
                             next-colors)
                            (return))
                          (setf class-count next-class-count)
                          (maphash
                           (lambda (node color)
                             (setf
                              (candidate-equality-node-color node)
                              color))
                           next-colors))))))))
            (mapcar
             (lambda (root)
               (candidate-equality-node-color root))
             roots)))))))
