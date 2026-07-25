(in-package #:cl-weave)

(defun ensure-non-empty-sequence (value label)
  (unless (and (typep value 'sequence) (plusp (length value)))
    (error "cl-weave: ~A requires a non-empty sequence, got ~S." label value))
  value)

(defun ensure-bounded-sequence-lengths (min-length max-length label)
  (when (minusp min-length)
    (error "cl-weave: ~A requires a non-negative MIN-LENGTH, got ~S."
           label min-length))
  (when (> min-length max-length)
    (error "cl-weave: ~A requires MIN-LENGTH <= MAX-LENGTH, got ~S and ~S."
           label min-length max-length)))

(defun bounded-sequence-length (min-length max-length rng)
  (+ min-length
     (property-random-below rng (1+ (- max-length min-length)))))

(defun equalp-hash-test-p (hash-test)
  (or (eq hash-test (quote equalp))
      (eq hash-test (function equalp))
      (eq hash-test (symbol-function (quote equalp)))))

(defun candidate-container-p (value equalp-test-p)
  (or (consp value)
      (and equalp-test-p
           (or (arrayp value)
               (hash-table-p value)
               (typep value (quote structure-object))))))

(defun candidate-requires-safe-equality-p (value hash-test)
  (let ((equal-test-p (equal-hash-test-p hash-test))
        (equalp-test-p (equalp-hash-test-p hash-test)))
    (unless
        (and (or equal-test-p equalp-test-p)
             (candidate-container-p value equalp-test-p))
      (return-from candidate-requires-safe-equality-p nil))
    (let ((states (make-hash-table :test (function eq)))
          (pending (list (list value nil 0))))
      (loop while pending
            for frame = (pop pending)
            for node = (first frame)
            for complete-p = (second frame)
            for depth = (third frame)
            if complete-p
              do (setf (gethash node states) :complete)
            else
            when (candidate-container-p node equalp-test-p)
              do (when (>= depth 128)
                   (return-from candidate-requires-safe-equality-p t))
                 (case (gethash node states)
                   (:visiting
                    (return-from candidate-requires-safe-equality-p t))
                   (:complete)
                   (otherwise
                    (setf (gethash node states) :visiting)
                    (push (list node t depth) pending)
                    (let ((child-depth (1+ depth)))
                      (cond
                        ((consp node)
                         (push (list (cdr node) nil child-depth) pending)
                         (push (list (car node) nil child-depth) pending))
                        ((arrayp node)
                         (dotimes
                             (index
                              (if (vectorp node)
                                  (length node)
                                  (array-total-size node)))
                           (push (list (row-major-aref node index)
                                       nil
                                       child-depth)
                                 pending)))
                        ((hash-table-p node)
                         (maphash
                          (lambda (key item)
                            (push (list item nil child-depth) pending)
                            (push (list key nil child-depth) pending))
                          node))
                        ((typep node (quote structure-object))
                         #+sbcl
                         (dolist (slot (sb-mop:class-slots (class-of node)))
                           (let ((name (sb-mop:slot-definition-name slot)))
                             (when (slot-boundp node name)
                               (push (list (slot-value node name)
                                           nil
                                           child-depth)
                                     pending))))
                         #-sbcl
                         (return-from candidate-requires-safe-equality-p
                           t))))))
            finally (return nil)))))

(defun candidate-pair-seen-p (seen left right)
  (multiple-value-bind (rights present-p) (gethash left seen)
    (unless present-p
      (setf rights (make-hash-table :test #'eq)
            (gethash left seen) rights))
    (prog1
      (nth-value 1 (gethash right rights))
      (setf (gethash right rights) t))))

(defun equal-hash-test-p (hash-test)
  (or (eq hash-test (quote equal))
      (eq hash-test (function equal))
      (eq hash-test (symbol-function (quote equal)))))

(defun cycle-safe-candidate-equal-p
    (left right hash-test &optional initial-seen)
  (let ((pending (list (cons left right)))
        (seen (or initial-seen (make-hash-table :test (function eq))))
        (equalp-test-p (equalp-hash-test-p hash-test)))
    (loop while pending
          for pair = (pop pending)
          for left = (car pair)
          for right = (cdr pair)
          unless (eq left right)
            do (cond
                 ((and (consp left) (consp right))
                  (unless (candidate-pair-seen-p seen left right)
                    (push (cons (car left) (car right)) pending)
                    (push (cons (cdr left) (cdr right)) pending)))
                 ((or (consp left) (consp right))
                  (return-from cycle-safe-candidate-equal-p nil))
                 ((and equalp-test-p (arrayp left) (arrayp right))
                  (unless
                      (if (or (vectorp left) (vectorp right))
                          (and (vectorp left)
                               (vectorp right)
                               (= (length left) (length right)))
                          (equal (array-dimensions left)
                                 (array-dimensions right)))
                    (return-from cycle-safe-candidate-equal-p nil))
                  (unless (candidate-pair-seen-p seen left right)
                    (dotimes
                        (index
                         (if (vectorp left)
                             (length left)
                             (array-total-size left)))
                      (push (cons (row-major-aref left index)
                                  (row-major-aref right index))
                            pending))))
                 ((and equalp-test-p
                       (or (arrayp left) (arrayp right)))
                  (return-from cycle-safe-candidate-equal-p nil))
                 ((and equalp-test-p
      (hash-table-p left)
      (hash-table-p right))
  (unless
      (and (eq (hash-table-test left)
               (hash-table-test right))
           (= (hash-table-count left)
              (hash-table-count right)))
    (return-from cycle-safe-candidate-equal-p nil))
  (unless (candidate-pair-seen-p seen left right)
    (let ((table-test (hash-table-test left))
          (safe-left-entries nil)
          (safe-right-entries nil))
      (maphash
       (lambda (key value)
         (when (candidate-requires-safe-equality-p key table-test)
           (push (cons key value) safe-left-entries)))
       left)
      (maphash
       (lambda (key value)
         (when (candidate-requires-safe-equality-p key table-test)
           (push (cons key value) safe-right-entries)))
       right)
      (let* ((safe-left-count (length safe-left-entries))
             (safe-entries
               (append safe-left-entries safe-right-entries))
             (class-ids
               (candidate-equality-class-ids
                (mapcar (function car) safe-entries)
                table-test))
             (left-class-by-key
               (make-hash-table :test (function eq)))
             (right-entry-by-class
               (make-hash-table :test (function eql))))
        (loop for entry in safe-left-entries
              for class-id in class-ids
              do (setf
                  (gethash (car entry) left-class-by-key)
                  class-id))
        (loop for entry in safe-right-entries
              for class-id in (nthcdr safe-left-count class-ids)
              do (setf
                  (gethash class-id right-entry-by-class)
                  entry))
        (maphash
         (lambda (key left-value)
           (if (candidate-requires-safe-equality-p key table-test)
               (multiple-value-bind (class-id classified-p)
                   (gethash key left-class-by-key)
                 (declare (ignore classified-p))
                 (multiple-value-bind (right-entry present-p)
                     (gethash class-id right-entry-by-class)
                   (unless present-p
                     (return-from cycle-safe-candidate-equal-p nil))
                   (push (cons left-value (cdr right-entry)) pending)))
               (multiple-value-bind (right-value present-p)
                   (gethash key right)
                 (unless present-p
                   (return-from cycle-safe-candidate-equal-p nil))
                 (push (cons left-value right-value) pending))))
         left)))))
                 ((and equalp-test-p
                       (or (hash-table-p left) (hash-table-p right)))
                  (return-from cycle-safe-candidate-equal-p nil))
                 ((and equalp-test-p
                       (typep left (quote structure-object))
                       (typep right (quote structure-object)))
                  #+sbcl
                  (unless (eq (class-of left) (class-of right))
                    (return-from cycle-safe-candidate-equal-p nil))
                  #+sbcl
                  (unless (candidate-pair-seen-p seen left right)
                    (dolist (slot (sb-mop:class-slots (class-of left)))
                      (let* ((name (sb-mop:slot-definition-name slot))
                             (left-bound-p (slot-boundp left name))
                             (right-bound-p (slot-boundp right name)))
                        (unless (eq (not (null left-bound-p))
                                    (not (null right-bound-p)))
                          (return-from cycle-safe-candidate-equal-p nil))
                        (when left-bound-p
                          (push (cons (slot-value left name)
                                      (slot-value right name))
                                pending)))))
                  #-sbcl
                  (return-from cycle-safe-candidate-equal-p nil))
                 ((and equalp-test-p
                       (or (typep left (quote structure-object))
                           (typep right (quote structure-object))))
                  (return-from cycle-safe-candidate-equal-p nil))
                 ((not (funcall hash-test left right))
                  (return-from cycle-safe-candidate-equal-p nil)))
          finally (return t))))

(defun remove-duplicate-shrink-candidates (candidates hash-test)
  (let* ((processing (reverse candidates))
         (safe-flags
           (mapcar
            (lambda (candidate)
              (candidate-requires-safe-equality-p candidate hash-test))
            processing))
         (safe-candidates
           (loop for candidate in processing
                 for safe-p in safe-flags
                 when safe-p
                   collect candidate))
         (safe-class-ids
           (candidate-equality-class-ids safe-candidates hash-test))
         (unique nil)
         (seen (make-hash-table :test hash-test))
         (safe-seen (make-hash-table :test (function eql))))
    (loop for candidate in processing
          for safe-p in safe-flags
          do
             (if safe-p
                 (let ((class-id (pop safe-class-ids)))
                   (unless (nth-value 1 (gethash class-id safe-seen))
                     (push candidate unique)
                     (setf (gethash class-id safe-seen) t)))
                 (unless (nth-value 1 (gethash candidate seen))
                   (push candidate unique)
                   (setf (gethash candidate seen) t))))
    unique))

(defun copy-sequence-and-set-item (value index item)
  (etypecase value
    (list
      (let ((next (copy-list value)))
        (setf (nth index next) item)
        next))
    (string
      (let ((next (copy-seq value)))
        (setf (char next index) item)
        next))
    (vector
      (let ((next (copy-seq value)))
        (setf (aref next index) item)
        next))))

(defun sequence-shrink-candidates (value generator)
  (let ((candidates nil)
        (index 0))
    (map nil
         (lambda (element)
           (dolist (shrunk (property-shrink-candidates generator element))
             (push (copy-sequence-and-set-item value index shrunk)
                   candidates))
           (incf index))
         value)
    (nreverse candidates)))

(defun bounded-sequence-shrink-candidates (value
    min-length
    max-length
    predicate
    empty-value
    element-generator
    &key
    (hash-test #'equal))
  (when (funcall predicate value)
    (let ((value-length (length value)))
      (when (<= min-length value-length max-length)
        (let ((element-candidates (sequence-shrink-candidates value element-generator)))
          (remove-duplicate-shrink-candidates
            (remove-if-not
              (lambda (candidate)
                (and
                  (funcall predicate candidate)
                  (<= min-length (length candidate) max-length)))
              (list*
                empty-value
                (subseq value 0 (truncate value-length 2))
                element-candidates))
            hash-test))))))

(defun make-bounded-sequence-generator (name element-generator min-length max-length label predicate
                                             empty-value build-sequence &key (hash-test #'equal))
  (ensure-property-generator element-generator label)
  (ensure-bounded-sequence-lengths min-length max-length label)
  (let ((element-produce (property-generator-produce element-generator)))
    (make-property-generator
     :name name
     :produce (lambda (rng)
                (funcall build-sequence
                         (loop repeat (bounded-sequence-length min-length max-length rng)
                               collect (funcall element-produce rng))))
     :shrink (lambda (value)
               ;; Alternative generators (GEN-ONE-OF) may offer foreign values.
               (bounded-sequence-shrink-candidates
                value min-length max-length predicate empty-value element-generator
                :hash-test hash-test)))))
