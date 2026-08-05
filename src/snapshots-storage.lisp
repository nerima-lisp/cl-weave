(in-package #:cl-weave)

(defvar *snapshot-directory* #P"__snapshots__/")

(defvar *snapshot-file-name* "snapshots.sexp")

#+

sbcl

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

#+

sb-thread

(progn
  (defstruct (snapshot-file-lock-entry (:constructor make-snapshot-file-lock-entry (mutex))) mutex
    (references 0 :type (integer 0 *)))
  (defvar *snapshot-file-locks* (make-hash-table :test #'equal)))

#+

sb-thread

(defvar *snapshot-file-locks-lock* (sb-thread:make-mutex :name "cl-weave snapshot lock registry"))

(defvar *snapshot-temporary-file-counter* 0)

(defun snapshot-file-pathname ()
  (merge-pathnames *snapshot-file-name* *snapshot-directory*))

(defun canonical-snapshot-file-pathname (&optional (file (snapshot-file-pathname)))
  (uiop:truenamize (uiop:ensure-absolute-pathname file)))

#+

sb-thread

(defun acquire-snapshot-file-lock-entry (file)
  (let ((key (namestring file)))
    (sb-thread:with-mutex
      (*snapshot-file-locks-lock*)
      (let ((entry
            (or
              (gethash key *snapshot-file-locks*)
              (setf (gethash key *snapshot-file-locks*) (make-snapshot-file-lock-entry
                  (sb-thread:make-mutex :name (format nil "cl-weave snapshot ~A" key)))))))
        (incf (snapshot-file-lock-entry-references entry))
        (values key entry)))))

(defun snapshot-process-lock-file-pathname (file)
  (merge-pathnames
    (format nil ".~A.lock" (file-namestring file))
    (uiop:pathname-directory-pathname file)))

#+

sbcl

(defun call-with-snapshot-process-lock (file function)
  (let ((directory (uiop:pathname-directory-pathname file)))
    (if (probe-file directory) (let ((descriptor nil)
            (locked-p nil))
        (unwind-protect (progn
            (setf descriptor (sb-posix:open
                (namestring (snapshot-process-lock-file-pathname file))
                (logior sb-posix:o-rdwr sb-posix:o-creat)
                #o600))
            (sb-posix:lockf descriptor sb-posix:f-lock 0)
            (setf locked-p t)
            (funcall function))
          (when locked-p
            (ignore-errors (sb-posix:lockf descriptor sb-posix:f-ulock 0)))
          (when descriptor
            (ignore-errors (sb-posix:close descriptor)))))
      (funcall function))))

#-

sbcl

(defun call-with-snapshot-process-lock (file function)
  (declare (ignore file))
  (funcall function))

(defun call-with-snapshot-file-lock (file function)
  #+
  sb-thread
  (multiple-value-bind (key entry) (acquire-snapshot-file-lock-entry file)
    (unwind-protect (sb-thread:with-mutex
        ((snapshot-file-lock-entry-mutex entry))
        (call-with-snapshot-process-lock file function))
      (sb-thread:with-mutex
        (*snapshot-file-locks-lock*)
        (decf (snapshot-file-lock-entry-references entry))
        (when (and
            (zerop (snapshot-file-lock-entry-references entry))
            (eq entry (gethash key *snapshot-file-locks*)))
          (remhash key *snapshot-file-locks*)))))
  #-
  sb-thread
  (call-with-snapshot-process-lock file function))

(defun next-snapshot-temporary-file-counter ()
  #+
  sb-thread
  (sb-thread:with-mutex
    (*snapshot-file-locks-lock*)
    (incf *snapshot-temporary-file-counter*))
  #-
  sb-thread
  (incf *snapshot-temporary-file-counter*))

(defun snapshot-temporary-file-pathname (file)
  (merge-pathnames
    (format
      nil
      ".~A.~D.~D.tmp"
      (file-namestring file)
      (get-universal-time)
      (next-snapshot-temporary-file-counter))
    (uiop:pathname-directory-pathname file)))

#+

sbcl

(defun open-snapshot-temporary-pathname (temporary-file)
  (handler-case (let ((descriptor
          (sb-posix:open
            (namestring temporary-file)
            (logior sb-posix:o-wronly sb-posix:o-creat sb-posix:o-excl)
            #o600)))
      (handler-case (sb-sys:make-fd-stream
          descriptor
          :output
          t
          :element-type
          'character
          :external-format
          :default
          :pathname
          temporary-file
          :auto-close
          t)
        (condition (condition)
          (ignore-errors (sb-posix:close descriptor))
          (ignore-errors (delete-file temporary-file))
          (error condition))))
    (sb-posix:syscall-error (condition)
      (if (= (sb-posix:syscall-errno condition) sb-posix:eexist) nil
        (error condition)))))

#-

sbcl

(defun open-snapshot-temporary-pathname (temporary-file)
  (open
    temporary-file
    :direction
    :output
    :if-exists
    nil
    :if-does-not-exist
    :create))

#+

sbcl

(defun restrict-snapshot-temporary-file-permissions (temporary-file file)
  (let ((target-mode
        (when (probe-file file)
          (logand #o777 (sb-posix:stat-mode (sb-posix:stat (namestring file)))))))
    (sb-posix:chmod
      (namestring temporary-file)
      (if target-mode (logand #o600 target-mode)
        #o600))))

#-

sbcl

(defun restrict-snapshot-temporary-file-permissions (temporary-file file)
  (declare (ignore temporary-file file)))

(defun open-snapshot-temporary-file (file)
  (loop for temporary-file = (snapshot-temporary-file-pathname file)
        for stream = (open-snapshot-temporary-pathname temporary-file)
        when stream
          return (values temporary-file stream)))

(defun read-snapshot-file-unlocked (file)
  (when (probe-file file)
    (with-open-file (stream file :direction :input)
      (let ((*read-eval* nil))
        (read stream nil nil)))))

(defun write-snapshot-file-unlocked (entries file)
  (multiple-value-bind (temporary-file stream) (open-snapshot-temporary-file file)
    (let ((published-p nil))
      (unwind-protect (progn
          (let ((*print-case* :downcase)
                (*print-circle* t)
                (*print-pretty* t))
            (prin1 entries stream)
            (terpri stream))
          (close stream)
          (setf stream nil)
          (restrict-snapshot-temporary-file-permissions temporary-file file)
          (uiop:rename-file-overwriting-target
            temporary-file
            (make-pathname :type (or (pathname-type file) :unspecific) :defaults file))
          (setf published-p t)
          nil)
        (when stream
          (ignore-errors (close stream :abort t)))
        (unless published-p
          (ignore-errors (delete-file temporary-file)))))))
