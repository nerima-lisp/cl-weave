(in-package #:cl-weave)

(defun snapshot-string (value)
  (let ((*print-case* :downcase)
        (*print-circle* t)
        (*print-length* nil)
        (*print-level* nil)
        (*print-pretty* nil))
    (write-to-string value :escape t :readably nil)))

(defun snapshot-entry (key entries)
  (assoc key entries :test #'string=))

(defun replace-snapshot-entry (key value entries)
  (let ((entry (snapshot-entry key entries)))
    (if entry (progn
        (setf (cdr entry) value)
        entries)
      (append entries (list (cons key value))))))

(defun snapshot-sequence-key (prefix index)
  (format nil "~A[~D]" prefix index))

(defun snapshot-sequence-key-index (prefix key)
  (when (stringp key)
    (let* ((prefix-length (length prefix))
           (key-length (length key)))
      (when (and
          (> key-length (+ prefix-length 2))
          (string= key prefix :end1 prefix-length :end2 prefix-length)
          (char= (char key prefix-length) #\[)
          (char= (char key (1- key-length)) #\]))
        (let ((index 0))
          (loop for position from (1+ prefix-length) below (1- key-length)
                for digit = (digit-char-p (char key position) 10)
                unless digit
                  do (return nil)
                do (setf index (+ (* index 10) digit))
                finally (return index)))))))

(defun snapshot-sequence-entry-p (prefix entry)
  (and (consp entry) (snapshot-sequence-key-index prefix (car entry))))

(defun remove-snapshot-sequence-entries (prefix entries)
  (remove-if
    (lambda (entry)
      (snapshot-sequence-entry-p prefix entry))
    entries))

(defun snapshot-sequence-replacement (prefix values entries)
  (append
    (remove-snapshot-sequence-entries prefix entries)
    (loop for value in values
          for index from 0
          collect (cons (snapshot-sequence-key prefix index) (snapshot-string value)))))

(defstruct snapshot-session-file file
  entries
  entry-index
  operations
  dirty-p)

(defstruct (snapshot-session (:constructor make-snapshot-session ())) (files (make-hash-table :test #'equal))
  #+sb-thread
  (lock (sb-thread:make-mutex :name "cl-weave snapshot session")))

(defvar *snapshot-session* nil)

(define-conditional-lock-macro with-snapshot-session-lock ((session)) (snapshot-session-lock session))

(defun snapshot-session-refresh-index (file)
  (let ((index (make-hash-table :test #'equal)))
    (dolist (entry (snapshot-session-file-entries file))
      (when (consp entry)
        (setf (gethash (car entry) index) entry)))
    (setf (snapshot-session-file-entry-index file) index)))

(defun snapshot-session-load-file (file)
  (call-with-snapshot-file-lock
    file
    (lambda ()
      (let ((entries (copy-tree (read-snapshot-file-unlocked file))))
        (make-snapshot-session-file
          :file
          file
          :entries
          entries
          :entry-index
          (let ((index (make-hash-table :test #'equal)))
            (dolist (entry entries index)
              (when (consp entry)
                (setf (gethash (car entry) index) entry)))))))))

(defun snapshot-session-file-for (file)
  (let ((session *snapshot-session*))
    (or
      (with-snapshot-session-lock
        (session)
        (gethash file (snapshot-session-files session)))
      (let ((loaded (snapshot-session-load-file file)))
        (with-snapshot-session-lock
          (session)
          (or
            (gethash file (snapshot-session-files session))
            (setf (gethash file (snapshot-session-files session)) loaded)))))))

(defun read-snapshot-file ()
  (let ((file (canonical-snapshot-file-pathname)))
    (if *snapshot-session* (let ((session-file (snapshot-session-file-for file)))
        (multiple-value-bind (staged-p entries) (with-snapshot-session-lock
            (*snapshot-session*)
            (values
              (snapshot-session-file-operations session-file)
              (copy-tree (snapshot-session-file-entries session-file))))
          (if staged-p entries
            (call-with-snapshot-file-lock
              file
              (lambda ()
                (let ((disk-entries (read-snapshot-file-unlocked file)))
                  (with-snapshot-session-lock
                    (*snapshot-session*)
                    (unless (snapshot-session-file-operations session-file)
                      (setf (snapshot-session-file-entries session-file) disk-entries)
                      (snapshot-session-refresh-index session-file))
                    (copy-tree (snapshot-session-file-entries session-file)))))))))
      (when (probe-file file)
        (call-with-snapshot-file-lock
          file
          (lambda ()
            (read-snapshot-file-unlocked file)))))))

(defun write-snapshot-file (entries)
  (let ((file (snapshot-file-pathname)))
    (ensure-directories-exist file)
    (setf file (canonical-snapshot-file-pathname file))
    (call-with-snapshot-file-lock
      file
      (lambda ()
        (write-snapshot-file-unlocked entries file)))
    (when *snapshot-session*
      (with-snapshot-session-lock
        (*snapshot-session*)
        (remhash file (snapshot-session-files *snapshot-session*))))))

(defun call-with-snapshot-update-transaction (function)
  (let ((file (snapshot-file-pathname)))
    (ensure-directories-exist file)
    (setf file (canonical-snapshot-file-pathname file))
    (call-with-snapshot-file-lock
      file
      (lambda ()
        (funcall function (read-snapshot-file-unlocked file) file)))))

(defun snapshot-session-current-file ()
  (snapshot-session-file-for (canonical-snapshot-file-pathname)))

(defun snapshot-current-entries ()
  (if *snapshot-session* (let ((session *snapshot-session*)
          (file (snapshot-session-current-file)))
      (with-snapshot-session-lock (session) (snapshot-session-file-entries file)))
    (read-snapshot-file)))

(defun snapshot-current-entry (key)
  (if *snapshot-session* (let ((session *snapshot-session*)
          (file (snapshot-session-current-file)))
      (with-snapshot-session-lock
        (session)
        (gethash key (snapshot-session-file-entry-index file))))
    (snapshot-entry key (read-snapshot-file))))

(defun snapshot-session-stage (operation)
  (ensure-directories-exist (snapshot-file-pathname))
  (let ((session *snapshot-session*)
        (file (snapshot-session-current-file)))
    (with-snapshot-session-lock
      (session)
      (setf (snapshot-session-file-entries file) (ecase (car operation)
          (:replace
            (replace-snapshot-entry
              (second operation)
              (third operation)
              (snapshot-session-file-entries file)))
          (:sequence
            (snapshot-sequence-replacement
              (second operation)
              (third operation)
              (snapshot-session-file-entries file)))))
      (snapshot-session-refresh-index file)
      (push operation (snapshot-session-file-operations file))
      (setf (snapshot-session-file-dirty-p file) t))))

(defun snapshot-session-stage-replacement (key actual-string)
  (snapshot-session-stage (list :replace key actual-string)))

(defun snapshot-session-stage-sequence (prefix values)
  (snapshot-session-stage (list :sequence prefix (copy-list values))))

(defun snapshot-session-apply-operation (operation entries)
  (ecase (car operation)
    (:replace (replace-snapshot-entry (second operation) (third operation) entries))
    (:sequence
      (snapshot-sequence-replacement (second operation) (third operation) entries))))

(defun flush-snapshot-session (session)
  (let ((files
        (with-snapshot-session-lock
          (session)
          (loop for file being the hash-values of (snapshot-session-files session)
                when (snapshot-session-file-dirty-p file)
                  collect file))))
    (dolist (session-file files)
      (let ((file (snapshot-session-file-file session-file)))
        (call-with-snapshot-file-lock
          file
          (lambda ()
            (let* ((disk-entries (read-snapshot-file-unlocked file))
                   (next-entries disk-entries))
              (with-snapshot-session-lock
                (session)
                (dolist (operation (reverse (snapshot-session-file-operations session-file)))
                  (setf next-entries (snapshot-session-apply-operation operation next-entries))))
              (unless (equal disk-entries next-entries)
                (write-snapshot-file-unlocked next-entries file))
              (with-snapshot-session-lock
                (session)
                (setf (snapshot-session-file-entries session-file) next-entries
                      (snapshot-session-file-operations session-file) nil
                      (snapshot-session-file-dirty-p session-file) nil)
                (snapshot-session-refresh-index session-file)))))))))

(defun call-with-snapshot-session (function)
  (if *snapshot-session* (funcall function)
    (let ((*snapshot-session* (make-snapshot-session)))
      (unwind-protect (funcall function)
        (flush-snapshot-session *snapshot-session*)))))
