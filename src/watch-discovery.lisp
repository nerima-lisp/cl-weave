(in-package #:cl-weave)

(defun component-source-pathname (component)
  (let ((pathname (ignore-errors (asdf:component-pathname component))))
    (when (and pathname (not (uiop:directory-pathname-p pathname)))
      (uiop:ensure-absolute-pathname pathname))))

(defun collect-component-files/k (component seen-components seen-pathnames continue)
  (cond
    ((gethash component seen-components)
     (funcall continue '()))
    (t
     (setf (gethash component seen-components) t)
     (let ((children (ignore-errors (asdf:component-children component)))
           (source (component-source-pathname component)))
       (labels ((collect-children/k (remaining child-continue)
                  (if (null remaining)
                      (funcall child-continue '())
                      (collect-component-files/k
                       (first remaining)
                       seen-components
                       seen-pathnames
                       (lambda (files)
                         (collect-children/k
                          (rest remaining)
                          (lambda (tail)
                            (funcall child-continue (append files tail)))))))))
         (collect-children/k
          children
          (lambda (child-files)
            (if (and source (probe-file source) (not (gethash source seen-pathnames)))
                (progn
                  (setf (gethash source seen-pathnames) t)
                  (funcall continue (cons source child-files)))
                (funcall continue child-files)))))))))

(defun collect-asdf-dependency-graph/k
    (system include-dependencies seen-systems own-files/k continue)
  "Walk SYSTEM's ASDF dependency graph, and, when INCLUDE-DEPENDENCIES, every
transitive dependency reachable via ASDF:SYSTEM-DEPENDS-ON. OWN-FILES/K is
called once per distinct system, as (FUNCALL OWN-FILES/K SYSTEM-OBJECT
OWN-CONTINUE), to compute that system's own contribution before it is
combined with its dependencies' files and handed to CONTINUE."
  (let ((system-object (asdf:find-system system)))
    (if (gethash system-object seen-systems)
        (funcall continue '())
        (progn
          (setf (gethash system-object seen-systems) t)
          (funcall
           own-files/k
           system-object
           (lambda (own-files)
             (if include-dependencies
                 (labels ((collect-dependencies/k (remaining dependencies-continue)
                            (if (null remaining)
                                (funcall dependencies-continue '())
                                (let ((dependency-system
                                        (asdf/find-component:resolve-dependency-spec
                                         system-object (first remaining))))
                                  (if dependency-system
                                      (collect-asdf-dependency-graph/k
                                       dependency-system t seen-systems own-files/k
                                       (lambda (files)
                                         (collect-dependencies/k
                                          (rest remaining)
                                          (lambda (tail)
                                            (funcall dependencies-continue
                                                     (append files tail))))))
                                      (collect-dependencies/k
                                       (rest remaining) dependencies-continue))))))
                   (collect-dependencies/k
                    (asdf:system-depends-on system-object)
                    (lambda (dependency-files)
                      (funcall continue (append own-files dependency-files)))))
                 (funcall continue own-files))))))))

(defun system-files/k (system include-dependencies continue)
  (let ((seen-systems (make-hash-table :test (function eq)))
        (seen-components (make-hash-table :test (function eq)))
        (seen-pathnames (make-hash-table :test (function equal))))
    (collect-asdf-dependency-graph/k
     system
     include-dependencies
     seen-systems
     (lambda (system-object own-continue)
       (collect-component-files/k
        system-object seen-components seen-pathnames own-continue))
     continue)))

(defun asdf-system-files (system &key include-dependencies)
  "Return existing source files declared by SYSTEM and, optionally, its dependencies."
  (system-files/k system include-dependencies #'identity))

(defun asdf-system-definition-files (system &key include-dependencies)
  "Return existing ASDF definition files for SYSTEM and, optionally, its dependencies."
  (let ((seen-systems (make-hash-table :test #'eq))
        (seen-pathnames (make-hash-table :test #'equal)))
    (collect-asdf-dependency-graph/k
     system
     include-dependencies
     seen-systems
     (lambda (system-object own-continue)
       (let ((pathname (asdf:system-source-file system-object)))
         (funcall own-continue
                  (if (and pathname
                           (probe-file pathname)
                           (not (gethash pathname seen-pathnames)))
                      (progn
                        (setf (gethash pathname seen-pathnames) t)
                        (list pathname))
                      '()))))
     #'identity)))

(defun watched-system-files (system &key include-dependencies)
  "Return source and definition files that can change SYSTEM's component graph."
  (let ((seen (make-hash-table :test #'equal))
        (files nil))
    (dolist (pathname
             (append
              (asdf-system-files
               system
               :include-dependencies include-dependencies)
              (asdf-system-definition-files
               system
               :include-dependencies include-dependencies)))
      (unless (gethash pathname seen)
        (setf (gethash pathname seen) t)
        (push pathname files)))
    (nreverse files)))

(defconstant +watch-file-signature-buffer-size+ 8192)

(defconstant +watch-file-signature-fnv-offset-basis+ #xcbf29ce484222325)

(defconstant +watch-file-signature-fnv-mask+ #xffffffffffffffff)

(defconstant +watch-file-signature-fnv-prime+ #x100000001b3)

(defparameter *watch-file-signature-element-type* (quote (unsigned-byte 8)))

(defun file-content-signature (pathname &optional buffer)
  (with-open-file (stream pathname
                          :direction :input
                          :element-type *watch-file-signature-element-type*)
    (let ((buffer (or buffer
                      (make-array +watch-file-signature-buffer-size+
                                  :element-type *watch-file-signature-element-type*)))
          (hash +watch-file-signature-fnv-offset-basis+)
          (byte-count 0))
      (loop
        for count = (read-sequence buffer stream)
        while (plusp count)
        do (incf byte-count count)
           (loop for index below count
                 do (setf hash
                          (logand +watch-file-signature-fnv-mask+
                                  (* +watch-file-signature-fnv-prime+
                                     (logxor hash (aref buffer index))))))
        finally (return (values hash byte-count))))))

(defun pathname-signature (pathname &optional buffer)
  (handler-case
      (if (probe-file pathname)
          (let ((write-date (file-write-date pathname)))
            (multiple-value-bind (content-hash byte-count)
                (file-content-signature pathname buffer)
              (list :exists t
                    :write-date write-date
                    :length byte-count
                    :hash content-hash)))
          (list :exists nil))
    (error ()
      (list :exists :unknown))))

(defun file-state (pathnames)
  (let ((buffer (make-array +watch-file-signature-buffer-size+
                            :element-type *watch-file-signature-element-type*)))
    (mapcar (lambda (pathname)
              (cons pathname (pathname-signature pathname buffer)))
            pathnames)))

(defun changed-pathnames (old-state new-state)
  (let ((new-signatures (make-hash-table :test (function equal)))
        (seen (make-hash-table :test (function equal)))
        (changed (quote ())))
    (dolist (entry new-state)
      (setf (gethash (car entry) new-signatures) (cdr entry)))
    (dolist (entry old-state)
      (destructuring-bind (pathname . signature) entry
        (setf (gethash pathname seen) t)
        (multiple-value-bind (new-signature presentp)
            (gethash pathname new-signatures)
          (unless (and presentp (equal signature new-signature))
            (push pathname changed)))))
    (dolist (entry new-state)
      (unless (gethash (car entry) seen)
        (push (car entry) changed)))
    (nreverse changed)))
