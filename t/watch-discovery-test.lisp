(in-package #:cl-weave/test)

(describe "watch discovery"
  (it "collects source files from ASDF systems"
    (let ((files (cl-weave:asdf-system-files "cl-weave" :include-dependencies nil)))
      (expect files :to-satisfy
              (lambda (paths)
                (some (lambda (pathname)
                        (search "src/runner-api.lisp" (namestring pathname)))
                      paths)))
      (expect files :to-satisfy
              (lambda (paths)
                (some (lambda (pathname)
                        (search "src/watch.lisp" (namestring pathname)))
                      paths)))))

  (it "resolves versioned and feature ASDF dependencies"
    (let ((root-system (asdf:find-system "cl-weave"))
          (dependency-system (asdf:find-system "cl-weave/test"))
          (visited-systems nil))
      (with-mocked-functions
          (((symbol-function (quote asdf:system-depends-on))
            (lambda (system)
              (push system visited-systems)
              (if (eq system root-system)
                  (list (list :version "cl-weave" "0")
                        (list :feature
                              (first *features*)
                              "cl-weave/test")
                        (list :feature
                              :cl-weave-feature-that-does-not-exist
                              "cl-weave/missing"))
                  nil))))
        (cl-weave::asdf-system-definition-files
         root-system
         :include-dependencies t)
        (expect
         (member dependency-system visited-systems :test (function eq))
         :to-satisfy
         (function identity)))))

  (it "detects changed, deleted, and added file states in stable order"
    (let* ((pathname #P"/tmp/cl-weave-watch-state.lisp")
           (deleted #P"/tmp/cl-weave-watch-deleted.lisp")
           (unreadable #P"/tmp/cl-weave-watch-unreadable.lisp")
           (added #P"/tmp/cl-weave-watch-added.lisp")
           (old-state (list (cons pathname 1)
                            (cons deleted 7)
                            (cons unreadable nil)))
           (new-state (list (cons pathname 2)
                            (cons unreadable nil)
                            (cons added 9))))
      (expect (cl-weave::changed-pathnames old-state new-state)
              :to-equal (list pathname deleted added))
      (expect (cl-weave::changed-pathnames new-state new-state)
              :to-equal nil)))

  (it "shares one content buffer across a file-state scan"
    (let ((buffers (quote ())))
      (with-mocked-functions
          (((symbol-function (quote cl-weave::pathname-signature))
            (lambda (pathname &optional buffer)
              (declare (ignore pathname))
              (push buffer buffers)
              (list :exists t))))
        (cl-weave::file-state (list #P"first.lisp" #P"second.lisp")))
      (expect (length buffers) :to-be 2)
      (expect (eq (first buffers) (second buffers)) :to-be-truthy)
      (expect (typep (first buffers)
                     (quote (simple-array (unsigned-byte 8) (*))))
              :to-be-truthy)
      (expect (length (first buffers)) :to-be 8192)))

  #+sbcl
  (it "detects same-size content changes with an unchanged modification time"
    (let* ((directory (make-test-temporary-directory "watch-signature"))
           (pathname (merge-pathnames #P"watched.bin" directory)))
      (unwind-protect
          (progn
            (with-open-file (stream pathname
                                    :direction :output
                                    :if-exists :supersede
                                    :element-type (quote (unsigned-byte 8)))
              (write-sequence #(65 66 67 68) stream))
            (let* ((old-state (cl-weave::file-state (list pathname)))
                   (modified-time
                     (sb-posix:stat-mtime
                      (sb-posix:stat (namestring pathname)))))
              (with-open-file (stream pathname
                                      :direction :output
                                      :if-exists :supersede
                                      :element-type (quote (unsigned-byte 8)))
                (write-sequence #(87 88 89 90) stream))
              (sb-posix:utime (namestring pathname)
                              modified-time
                              modified-time)
              (let ((new-state (cl-weave::file-state (list pathname))))
                (expect (getf (cdr (first new-state)) :write-date)
                        :to-be
                        (getf (cdr (first old-state)) :write-date))
                (expect (getf (cdr (first new-state)) :length)
                        :to-be
                        (getf (cdr (first old-state)) :length))
                (expect (equal (getf (cdr (first new-state)) :hash)
                               (getf (cdr (first old-state)) :hash))
                        :to-be-falsy)
                (expect (cl-weave::changed-pathnames old-state new-state)
                        :to-equal (list pathname)))))
        (uiop:delete-directory-tree directory
                                    :validate t
                                    :if-does-not-exist :ignore))))

  (it "reports an unknown signature when a path cannot be read as a file"
    (let ((directory (make-test-temporary-directory "watch-signature-unreadable")))
      (unwind-protect
           (expect (cl-weave::pathname-signature directory)
                   :to-equal (list :exists :unknown))
        (uiop:delete-directory-tree directory
                                    :validate t
                                    :if-does-not-exist :ignore)))))
