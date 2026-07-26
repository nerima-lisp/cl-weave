(in-package #:cl-weave/test)

(describe "watch suite diff"
  (it "traverses fifty thousand nested watch suites without consuming control stack"
      (let* ((cl-weave::*test-registry-generation* 0)
             (depth 50000)
             (root (cl-weave::make-suite :name "root"))
             (current root)
             (changed (make-hash-table :test (function equal))))
        (dotimes (index depth)
          (let ((nested
                  (cl-weave::make-suite
                   :name (format nil "level-~D" index)
                   :parent current)))
            (cl-weave::add-child current nested)
            (setf current nested)))
        (labels ((exercise ()
                   (let ((path (cl-weave::suite-stable-path current)))
                     (expect (length path) :to-be depth)
                     (expect (first path) :to-equal (cons "level-0" 0))
                     (expect (car (last path))
                             :to-equal
                             (cons (format nil "level-~D" (1- depth)) 0)))
                   (expect
                    (cl-weave::collect-suite-preservation-records root changed)
                    :to-equal
                    nil)
                   (expect
                    (cl-weave::prune-changed-registrations root changed)
                    :to-be
                    root)
                   (multiple-value-bind (registrations suites)
                       (cl-weave::registry-reachable-objects root)
                     (expect (hash-table-count registrations)
                             :to-be
                             (1+ depth))
                     (expect (hash-table-count suites)
                             :to-be
                             (1+ depth)))))
          #+sbcl
          (sb-ext:with-timeout 30
            (exercise))
          #-sbcl
          (exercise))))

  (it
  "preserves every suite in a deep hierarchy with linear visits"
  (let* ((depth 4096)
         (changed-pathname
           #P"/tmp/cl-weave/watch-deep-preservation.lisp")
         (changed
           (cl-weave::changed-pathname-table
            (list changed-pathname)))
         (location (list :file changed-pathname))
         (root (cl-weave::make-suite :name "root"))
         (current root))
    (let ((cl-weave::*root-suite* root)
          (cl-weave::*current-suite* root)
          (cl-weave::*registration-owners*
            (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (labels ((record-suite-owner (suite)
                 (cl-weave::record-registration-owner suite location)
                 suite)
               (register-hook (suite hook)
                 (let ((cl-weave::*current-suite* suite))
                   (cl-weave::register-before-each
                    hook :location location))))
        (register-hook root (lambda () :old-root))
        (dotimes (index depth)
          (let ((nested
                  (record-suite-owner
                    (cl-weave::make-suite
                     :name (format nil "level-~D" index)
                     :parent current)))
                (hook (lambda () index)))
            (cl-weave::add-child current nested)
            (register-hook nested hook)
            (setf current nested)))
        (multiple-value-bind (tree collection-visits)
            (cl-weave::collect-suite-preservation-records
             root changed)
          (expect collection-visits :to-be (1+ depth))
          (let* ((replacement-root
                   (cl-weave::make-suite :name "root"))
                 (replacement-current replacement-root)
                 (replacement-suites (list replacement-root))
                 (replacement-hooks nil))
            (setf cl-weave::*root-suite* replacement-root
                  cl-weave::*current-suite* replacement-root)
            (let ((hook (lambda () :new-root)))
              (register-hook replacement-root hook)
              (push hook replacement-hooks))
            (dotimes (index depth)
              (let ((nested
                      (record-suite-owner
                        (cl-weave::make-suite
                         :name (format nil "level-~D" index)
                         :parent replacement-current)))
                    (hook (lambda () index)))
                (cl-weave::add-child replacement-current nested)
                (register-hook nested hook)
                (push nested replacement-suites)
                (push hook replacement-hooks)
                (setf replacement-current nested)))
            (setf replacement-suites
                  (nreverse replacement-suites)
                  replacement-hooks
                  (nreverse replacement-hooks))
            (multiple-value-bind (merged-root merge-visits)
                (cl-weave::merge-suite-preservation-records
                 replacement-root tree)
              (expect merged-root :to-be replacement-root)
              (expect merge-visits :to-be depth)
              (let ((parent nil))
                (loop for suite in replacement-suites
                      for hook in replacement-hooks
                      do (expect
                           (cl-weave::suite-parent suite)
                           :to-be
                           parent)
                         (expect
                           (cl-weave::suite-before-each suite)
                           :to-equal
                           (list hook))
                         (expect
                           (cl-weave::suite-before-each-tail suite)
                           :to-be
                           (last
                             (cl-weave::suite-before-each suite)))
                         (expect
                           (cl-weave::suite-children-tail suite)
                           :to-be
                           (last
                             (cl-weave::suite-children suite)))
                         (setf parent suite)))))))))))
