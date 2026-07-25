(in-package #:cl-weave)

(defun focused-child-p (child)
  (cond
    ((suite-p child)
     (or (suite-focus child)
         (some #'focused-child-p (suite-children child))))
    ((test-case-p child)
     (test-case-focus child))))

(progn
  (defun build-focus-index (suite)
    (let ((index (make-hash-table :test (function eq)))
          (stack (list (list* suite nil (suite-children suite)))))
      (loop while stack
            for frame = (car stack)
            for node = (car frame)
            for ancestor-focused = (cadr frame)
            for remaining = (cddr frame)
            do (if remaining
                   (let ((child (car remaining)))
                     (setf (cddr frame) (cdr remaining))
                     (cond
                       ((suite-p child)
                        (let ((focused (or ancestor-focused
                                           (suite-focus child))))
                          (push (list* child focused (suite-children child))
                                stack)))
                       ((test-case-p child)
                        (when (or ancestor-focused
                                  (test-case-focus child))
                          (setf (gethash child index) t)))))
                   (progn
                     (pop stack)
                     (when (or ancestor-focused
                               (some (lambda (child)
                                       (gethash child index))
                                     (suite-children node)))
                       (setf (gethash node index) t)))))
      (values (not (null (gethash suite index))) index)))

  (defun focused-suite-p (suite)
    (nth-value 0 (build-focus-index suite))))

(defstruct selection-filter
  "Per-run selection criteria and identity indexes threaded through traversal."
  focus-enabled
  focus-index
  name-filter
  location-filter
  location-filter-index
  test-path-filter
  test-path-index
  include-tags
  include-tag-index
  exclude-tags
  exclude-tag-index
  test-paths
  selected-tests
  selected-suites)


(defconstant +maximum-selection-filter-count+ 100000)

(defun normalize-bounded-proper-list (value description element-normalizer)
  (loop with seen = (make-hash-table :test #'eq)
        with normalized = nil
        with count = 0
        with cursor = value
        do (cond
             ((null cursor)
              (return (nreverse normalized)))
             ((or (atom cursor)
                  (gethash cursor seen)
                  (>= count +maximum-selection-filter-count+))
              (error "cl-weave: ~A must be a finite proper list with at most ~D entries."
                     description
                     +maximum-selection-filter-count+))
             (t
              (setf (gethash cursor seen) t)
              (incf count)
              (push (funcall element-normalizer (car cursor)) normalized)
              (setf cursor (cdr cursor))))))

(defun normalized-test-filter (filter)
  (when filter
    (unless (stringp filter)
      (error "cl-weave: name-filter must be a string or NIL."))
    (unless (string= filter "")
      (string-downcase filter))))


(defun test-path-matches-filter-p (path filter)
  (or (null filter)
      (search filter
              (string-downcase (filter-path-string path))
              :test #'char=)))

(defun normalize-shard (shard)
  (cond
    ((null shard) nil)
    ((and (consp shard)
          (consp (cdr shard))
          (null (cddr shard))
          (integerp (first shard))
          (integerp (second shard))
          (<= 1 (first shard) (second shard) +maximum-shard-count+))
     (list (first shard) (second shard)))
    (t
     (error "Shard must be NIL or (INDEX COUNT) with 1 <= INDEX <= COUNT <= ~D."
            +maximum-shard-count+))))

(defun shard-includes-ordinal-p (ordinal shard)
  (or (null shard)
      (= (first shard)
         (1+ (mod (1- ordinal) (second shard))))))

(defun location-pathname-designator (designator)
  (make-pathname
   :defaults
   (etypecase designator
     (pathname
      (uiop:ensure-absolute-pathname designator (uiop:getcwd)))
     (string
      (uiop:ensure-absolute-pathname designator (uiop:getcwd))))))


(defun normalize-location-filter (location-filter)
  (normalize-bounded-proper-list
   location-filter
   "location-filter"
   #'location-pathname-designator))

(defun normalize-test-path-component (component)
  (etypecase component
    (string (copy-seq component))))

(defun normalize-test-path-filter (test-path-filter)
  (normalize-bounded-proper-list
   test-path-filter
   "test-path-filter"
   (lambda (path)
     (normalize-bounded-proper-list
      path
      "each test-path-filter path"
      #'normalize-test-path-component))))


(defun test-location-pathname (test)
  (let ((file (getf (test-case-location test) :file)))
    (when file
      (location-pathname-designator file))))

(defun test-location-matches-filter-p (test location-filter-index)
  (or (null location-filter-index)
      (let ((pathname (test-location-pathname test)))
        (and pathname
             (gethash pathname location-filter-index)))))

(defun selected-path-p (path path-index)
  (or (null path-index)
      (gethash path path-index)))

(progn
  (defun tag-membership-index (tags)
    (when tags
      (let ((index (make-hash-table :test (function equal)
                                    :size (length tags))))
        (dolist (tag tags index)
          (setf (gethash tag index) t)))))

  (defun tag-index-member-p (tag index)
    (and index (gethash tag index)))

  (defun test-tags-match-filter-p
      (test include-tag-index exclude-tag-index)
    (let ((include-match (null include-tag-index)))
      (dolist (tag (test-case-tags test) include-match)
        (when (and exclude-tag-index
                   (tag-index-member-p tag exclude-tag-index))
          (return nil))
        (when (and include-tag-index
                   (tag-index-member-p tag include-tag-index))
          (setf include-match t))))))

(defun base-selected-test-case-p (test path filter ancestor-focused)
  (declare (ignore ancestor-focused))
  (and (or (not (selection-filter-focus-enabled filter))
           (gethash test (selection-filter-focus-index filter)))
       (test-path-matches-filter-p path
                                   (selection-filter-name-filter filter))
       (test-location-matches-filter-p
        test
        (selection-filter-location-filter-index filter))
       (selected-path-p path
                        (selection-filter-test-path-index filter))
       (test-tags-match-filter-p
        test
        (selection-filter-include-tag-index filter)
        (selection-filter-exclude-tag-index filter))))

(defun collect-selection-indexes (suite filter shard)
  (setf (selection-filter-include-tag-index filter)
        (tag-membership-index (selection-filter-include-tags filter))
        (selection-filter-exclude-tag-index filter)
        (tag-membership-index (selection-filter-exclude-tags filter)))
  (let ((selected-tests (make-hash-table :test (function eq)))
        (selected-suites (make-hash-table :test (function eq)))
        (test-paths (make-hash-table :test (function eq)))
        (ordinal 0)
        (stack (list (cons suite (suite-children suite)))))
    (loop while stack
          for frame = (car stack)
          for node = (car frame)
          for remaining = (cdr frame)
          do (if remaining
                 (let ((child (car remaining)))
                   (setf (cdr frame) (cdr remaining))
                   (cond
                     ((suite-p child)
                      (push (cons child (suite-children child)) stack))
                     ((test-case-p child)
                      (let ((path (test-path node child)))
                        (setf (gethash child test-paths) path)
                        (when (base-selected-test-case-p
                               child path filter nil)
                          (incf ordinal)
                          (when (or (null shard)
                                    (shard-includes-ordinal-p ordinal shard))
                            (setf (gethash child selected-tests) t)))))))
                 (progn
                   (pop stack)
                   (when (some (lambda (child)
                                 (if (suite-p child)
                                     (gethash child selected-suites)
                                     (and (test-case-p child)
                                          (gethash child selected-tests))))
                               (suite-children node))
                     (setf (gethash node selected-suites) t)))))
    (values selected-tests selected-suites test-paths)))

(defun normalize-sequence-order (order)
  (cond
    ((null order) :defined)
    ((eq order :random) :random)
    (t (error "Sequence order must be NIL or :RANDOM: ~S" order))))

(defun normalize-sequence-seed (seed)
  (cond
    ((null seed) 0)
    ((integerp seed) seed)
    (t (error "Sequence seed must be an integer: ~S" seed))))

(progn
  (defun update-stable-string-hash (hash string)
    (loop for char across string
          do (setf hash
                   (mod (* (logxor hash (char-code char))
                           +stable-hash-prime+)
                        +stable-hash-modulus+))
          finally (return hash)))

  (defun stable-string-hash (string seed)
    (update-stable-string-hash
     (mod (+ +stable-hash-offset+ seed) +stable-hash-modulus+)
     string)))

(defun sequence-suite-prefix (suite)
  (format nil "~{~A~^ > ~}" (mapcar #'suite-name (rest (suite-lineage suite)))))

(defun sequence-child-label (suite child &optional prefix)
  (format nil "~A :: ~A:~A"
          (or prefix (sequence-suite-prefix suite))
          (cond
            ((suite-p child) "suite")
            ((test-case-p child) "test")
            (t "unknown"))
          (cond
            ((suite-p child) (suite-name child))
            ((test-case-p child) (test-case-name child))
            (t child))))

(progn
  (defun sequence-child-hash (suite child prefix prefix-hash)
    (let ((kind (cond
                  ((suite-p child) "suite")
                  ((test-case-p child) "test")))
          (name (cond
                  ((suite-p child) (suite-name child))
                  ((test-case-p child) (test-case-name child)))))
      (if (and kind (stringp name))
          (update-stable-string-hash
           (update-stable-string-hash
            (update-stable-string-hash
             (update-stable-string-hash prefix-hash " :: ")
             kind)
            ":")
           name)
          (stable-string-hash
           (sequence-child-label suite child prefix)
           *test-sequence-seed*))))

  (defun ordered-children (suite children)
    (if (eq *test-sequence-order* :random)
        (let* ((prefix (sequence-suite-prefix suite))
               (prefix-hash
                (stable-string-hash prefix *test-sequence-seed*))
               (decorated
                (stable-sort
                 (mapcar
                  (lambda (child)
                    (cons (sequence-child-hash
                           suite child prefix prefix-hash)
                          child))
                  children)
                 (function <)
                 :key (function car))))
          (loop for cell on decorated
                do (setf (car cell) (cdar cell)))
          decorated)
        children)))

(defun selected-test-case-p (suite test filter ancestor-focused)
  (declare (ignore suite ancestor-focused))
  (gethash test (selection-filter-selected-tests filter)))

(defun selected-suite-p (suite filter ancestor-focused)
  (declare (ignore ancestor-focused))
  (gethash suite (selection-filter-selected-suites filter)))

(defun selected-child-suite-p (child filter child-focused)
  (declare (ignore child-focused))
  (gethash child (selection-filter-selected-suites filter)))

(defun selected-child-test-p (suite child filter ancestor-focused)
  (selected-test-case-p suite child filter ancestor-focused))
