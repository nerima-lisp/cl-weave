(in-package #:cl-weave)

(defvar *snapshot-directory* #P"__snapshots__/")
(defvar *snapshot-file-name* "snapshots.sexp")
#+sbcl
  (eval-when (:compile-toplevel :load-toplevel :execute)
    (require :sb-posix))
  (defvar *update-snapshots* nil)
  #+sb-thread
  (progn
    (defstruct (snapshot-file-lock-entry
                (:constructor make-snapshot-file-lock-entry (mutex)))
      mutex
      (references 0 :type (integer 0 *)))

    (defvar *snapshot-file-locks* (make-hash-table :test #'equal)))
  #+sb-thread
  (defvar *snapshot-file-locks-lock*
    (sb-thread:make-mutex :name "cl-weave snapshot lock registry"))
  (defvar *snapshot-temporary-file-counter* 0)

(defun snapshot-string (value)
  (let ((*print-case* :downcase)
        (*print-circle* t)
        (*print-length* nil)
        (*print-level* nil)
        (*print-pretty* nil))
    (write-to-string value :escape t :readably nil)))

(defun snapshot-file-pathname ()
    (merge-pathnames *snapshot-file-name* *snapshot-directory*))

  (defun canonical-snapshot-file-pathname (&optional (file (snapshot-file-pathname)))
    (uiop:truenamize (uiop:ensure-absolute-pathname file)))

  #+sb-thread
  (defun acquire-snapshot-file-lock-entry (file)
    (let ((key (namestring file)))
      (sb-thread:with-mutex (*snapshot-file-locks-lock*)
        (let ((entry
                (or (gethash key *snapshot-file-locks*)
                    (setf (gethash key *snapshot-file-locks*)
                          (make-snapshot-file-lock-entry
                           (sb-thread:make-mutex
                            :name (format nil "cl-weave snapshot ~A" key)))))))
          (incf (snapshot-file-lock-entry-references entry))
          (values key entry)))))

  (defun snapshot-process-lock-file-pathname (file)
    (merge-pathnames
     (format nil ".~A.lock" (file-namestring file))
     (uiop:pathname-directory-pathname file)))

  #+sbcl
  (defun call-with-snapshot-process-lock (file function)
    (let ((directory (uiop:pathname-directory-pathname file)))
      (if (probe-file directory)
          (let ((descriptor nil)
                (locked-p nil))
            (unwind-protect
                 (progn
                   (setf descriptor
                         (sb-posix:open
                          (namestring (snapshot-process-lock-file-pathname file))
                          (logior sb-posix:o-rdwr sb-posix:o-creat)
                          #o600))
                   (sb-posix:lockf descriptor sb-posix:f-lock 0)
                   (setf locked-p t)
                   (funcall function))
              (when locked-p
                (ignore-errors
                  (sb-posix:lockf descriptor sb-posix:f-ulock 0)))
              (when descriptor
                (ignore-errors
                  (sb-posix:close descriptor)))))
          (funcall function))))

  #-sbcl
  (defun call-with-snapshot-process-lock (file function)
    (declare (ignore file))
    (funcall function))

  (defun call-with-snapshot-file-lock (file function)
    #+sb-thread
    (multiple-value-bind (key entry)
        (acquire-snapshot-file-lock-entry file)
      (unwind-protect
           (sb-thread:with-mutex ((snapshot-file-lock-entry-mutex entry))
             (call-with-snapshot-process-lock file function))
        (sb-thread:with-mutex (*snapshot-file-locks-lock*)
          (decf (snapshot-file-lock-entry-references entry))
          (when (and (zerop (snapshot-file-lock-entry-references entry))
                     (eq entry (gethash key *snapshot-file-locks*)))
            (remhash key *snapshot-file-locks*)))))
    #-sb-thread
    (call-with-snapshot-process-lock file function))

  (defun next-snapshot-temporary-file-counter ()
    #+sb-thread
    (sb-thread:with-mutex (*snapshot-file-locks-lock*)
      (incf *snapshot-temporary-file-counter*))
    #-sb-thread
    (incf *snapshot-temporary-file-counter*))

  (defun snapshot-temporary-file-pathname (file)
    (merge-pathnames
     (format nil ".~A.~D.~D.tmp"
             (file-namestring file)
             (get-universal-time)
             (next-snapshot-temporary-file-counter))
     (uiop:pathname-directory-pathname file)))

  #+sbcl
  (defun open-snapshot-temporary-pathname (temporary-file)
    (handler-case
        (let ((descriptor
                (sb-posix:open
                  (namestring temporary-file)
                  (logior sb-posix:o-wronly sb-posix:o-creat sb-posix:o-excl)
                  #o600)))
          (handler-case
              (sb-sys:make-fd-stream
                descriptor
                :output t
                :element-type 'character
                :external-format :default
                :pathname temporary-file
                :auto-close t)
            (condition (condition)
              (ignore-errors (sb-posix:close descriptor))
              (ignore-errors (delete-file temporary-file))
              (error condition))))
      (sb-posix:syscall-error (condition)
        (if (= (sb-posix:syscall-errno condition) sb-posix:eexist)
            nil
            (error condition)))))

  #-sbcl
  (defun open-snapshot-temporary-pathname (temporary-file)
    (open temporary-file
          :direction :output
          :if-exists nil
          :if-does-not-exist :create))

  #+sbcl
  (defun restrict-snapshot-temporary-file-permissions (temporary-file file)
    (let ((target-mode
            (when (probe-file file)
              (logand #o777
                      (sb-posix:stat-mode
                        (sb-posix:stat (namestring file)))))))
      (sb-posix:chmod
        (namestring temporary-file)
        (if target-mode (logand #o600 target-mode) #o600))))

  #-sbcl
  (defun restrict-snapshot-temporary-file-permissions (temporary-file file)
    (declare (ignore temporary-file file)))

  (defun open-snapshot-temporary-file (file)
    (loop
      for temporary-file = (snapshot-temporary-file-pathname file)
      for stream = (open-snapshot-temporary-pathname temporary-file)
      when stream
        return (values temporary-file stream)))

(defun snapshot-line-list (string)
  (with-input-from-string (stream string)
    (loop for line = (read-line stream nil nil)
          while line
          collect line)))

(defun snapshot-first-difference (expected actual)
  (let ((expected-lines (snapshot-line-list expected))
        (actual-lines (snapshot-line-list actual)))
    (loop with expected-rest = expected-lines
          with actual-rest = actual-lines
          for line-number from 1
          while (or expected-rest actual-rest)
          for expected-line = (pop expected-rest)
          for actual-line = (pop actual-rest)
          unless (equal expected-line actual-line)
            return (list :line line-number
                         :expected expected-line
                         :actual actual-line))))

(defun snapshot-comparison-values (key actual-string entry)
  (let* ((file (namestring (snapshot-file-pathname)))
         (expected-present-p (not (null entry)))
         (expected-string (and entry (cdr entry)))
         (difference (when expected-present-p
                       (snapshot-first-difference expected-string actual-string)))
         (reason (if expected-present-p
                     :snapshot-mismatch
                     :missing-snapshot)))
    (values (list :snapshot-key key
                  :snapshot-file file
                  :value actual-string
                  :reason reason
                  :difference difference)
            (list :snapshot-key key
                  :snapshot-file file
                  :value expected-string
                  :present expected-present-p
                  :reason reason
                  :difference difference))))

(defstruct snapshot-session-file
    file entries entry-index operations dirty-p)

(defstruct (snapshot-session (:constructor make-snapshot-session ()))
    (files (make-hash-table :test #'equal))
    #+sb-thread (lock (sb-thread:make-mutex :name "cl-weave snapshot session")))

(defvar *snapshot-session* nil)

(defmacro with-snapshot-session-lock ((session) &body body)
    #+sb-thread `(sb-thread:with-mutex ((snapshot-session-lock ,session)) ,@body)
    #-sb-thread `(progn ,@body))

(defun read-snapshot-file-unlocked (file)
    (when (probe-file file)
      (with-open-file (stream file :direction :input)
        (let ((*read-eval* nil))
          (read stream nil nil)))))

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
          :file file :entries entries
          :entry-index (let ((index (make-hash-table :test #'equal)))
                         (dolist (entry entries index)
                           (when (consp entry)
                             (setf (gethash (car entry) index) entry)))))))))

(defun snapshot-session-file-for (file)
    (let ((session *snapshot-session*))
      (or (with-snapshot-session-lock (session)
            (gethash file (snapshot-session-files session)))
          (let ((loaded (snapshot-session-load-file file)))
            (with-snapshot-session-lock (session)
              (or (gethash file (snapshot-session-files session))
                  (setf (gethash file (snapshot-session-files session)) loaded)))))))

(defun read-snapshot-file ()   (let ((file (canonical-snapshot-file-pathname)))     (if *snapshot-session*         (let ((session-file (snapshot-session-file-for file)))           (multiple-value-bind (staged-p entries)               (with-snapshot-session-lock (*snapshot-session*)                 (values (snapshot-session-file-operations session-file)                         (copy-tree (snapshot-session-file-entries session-file))))             (if staged-p                 entries                 (call-with-snapshot-file-lock                  file                  (lambda ()                    (let ((disk-entries (read-snapshot-file-unlocked file)))                      (with-snapshot-session-lock (*snapshot-session*)                        (unless (snapshot-session-file-operations session-file)                          (setf (snapshot-session-file-entries session-file) disk-entries)                          (snapshot-session-refresh-index session-file))                        (copy-tree (snapshot-session-file-entries session-file)))))))))         (when (probe-file file)           (call-with-snapshot-file-lock            file            (lambda ()              (read-snapshot-file-unlocked file)))))))

(defun snapshot-entries () (copy-tree (snapshot-current-entries)))

(defun snapshot-entry (key entries) (assoc key entries :test #'string=))

(defun snapshot-value (key) (unless (stringp key) (error "cl-weave:snapshot-value expects a string snapshot key.")) (let ((entry (snapshot-current-entry key))) (if entry (values (cdr entry) t) (values nil nil))))

(defun write-snapshot-file-unlocked (entries file)
  (multiple-value-bind (temporary-file stream)
      (open-snapshot-temporary-file file)
    (let ((published-p nil))
      (unwind-protect
          (progn
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
              (make-pathname
                :type (or (pathname-type file) :unspecific)
                :defaults file))
            (setf published-p t)
            nil)
        (when stream
          (ignore-errors (close stream :abort t)))
        (unless published-p
          (ignore-errors (delete-file temporary-file)))))))

  (defun write-snapshot-file (entries) (let ((file (snapshot-file-pathname))) (ensure-directories-exist file) (setf file (canonical-snapshot-file-pathname file)) (call-with-snapshot-file-lock file (lambda () (write-snapshot-file-unlocked entries file))) (when *snapshot-session* (with-snapshot-session-lock (*snapshot-session*) (remhash file (snapshot-session-files *snapshot-session*))))))

  (defun call-with-snapshot-update-transaction (function)
    (let ((file (snapshot-file-pathname)))
      (ensure-directories-exist file)
      (setf file (canonical-snapshot-file-pathname file))
      (call-with-snapshot-file-lock
       file
       (lambda ()
         (funcall function (read-snapshot-file-unlocked file) file)))))

(defun replace-snapshot-entry (key value entries)
  (let ((entry (snapshot-entry key entries)))
    (if entry
        (progn
          (setf (cdr entry) value)
          entries)
        (append entries (list (cons key value))))))

(defun snapshot-update-token-p (value)
  (member (string-downcase value)
          '("1" "true" "yes" "update")
          :test #'string=))

(defun snapshot-update-enabled-p ()
  (or *update-snapshots*
      #+sbcl
      (let ((value (sb-ext:posix-getenv "CL_WEAVE_UPDATE_SNAPSHOTS")))
        (and value (snapshot-update-token-p value)))
      #-sbcl
      nil))

(defmacro define-snapshot-expected-reader (name matcher-label value-name)
  `(defun ,name (expected)
     (unless (= (length expected) 1)
       (error "Matcher ~A expects exactly one string ~A, got ~D values."
              ,matcher-label ,value-name (length expected)))
     (let ((value (first expected)))
       (unless (stringp value)
         (error "Matcher ~A expects a string ~A."
                ,matcher-label ,value-name))
       value)))

(define-snapshot-expected-reader snapshot-key-from-expected
  ":to-match-snapshot" "snapshot key")

(define-snapshot-expected-reader snapshot-sequence-prefix-from-expected
  ":to-match-snapshot-sequence" "snapshot key prefix")

(defun snapshot-sequence-values (actual)
  (typecase actual
    (list actual)
    ((and vector (not string))
     (coerce actual 'list))
    (t
     (error "Matcher :to-match-snapshot-sequence expects a list or non-string ~
             vector of states, got ~S."
            actual))))

(defun snapshot-sequence-key (prefix index)
  (format nil "~A[~D]" prefix index))

(defun snapshot-sequence-key-index (prefix key)
  (when (stringp key)
    (let* ((prefix-length (length prefix))
           (key-length (length key)))
      (when (and (> key-length (+ prefix-length 2))
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
  (and (consp entry)
       (snapshot-sequence-key-index prefix (car entry))))

(defun remove-snapshot-sequence-entries (prefix entries)
  (remove-if (lambda (entry)
               (snapshot-sequence-entry-p prefix entry))
             entries))

(defun snapshot-sequence-context-values (actual expected prefix index count)
  (values (append actual
                  (list :snapshot-prefix prefix
                        :snapshot-index index
                        :snapshot-count count))
          (append expected
                  (list :snapshot-prefix prefix
                        :snapshot-index index
                        :snapshot-count count))))

(defun snapshot-sequence-extra-values (prefix index count entry)
  (let ((file (namestring (snapshot-file-pathname))))
    (values (list :snapshot-prefix prefix
                  :snapshot-key (car entry)
                  :snapshot-file file
                  :snapshot-index index
                  :snapshot-count count
                  :value nil
                  :present nil
                  :reason :unexpected-snapshot)
            (list :snapshot-prefix prefix
                  :snapshot-key (car entry)
                  :snapshot-file file
                  :snapshot-index index
                  :snapshot-count count
                  :value (cdr entry)
                  :present t
                  :reason :unexpected-snapshot))))

(defun call-with-snapshot-comparison/k
    (key actual-string entry on-match on-mismatch)
  (if (and entry (string= actual-string (cdr entry)))
      (funcall on-match)
      (multiple-value-call on-mismatch
        (snapshot-comparison-values key actual-string entry))))

(defun call-with-snapshot-sequence-comparison/k (values entries prefix count index on-match on-mismatch &optional entry-index) (let ((entry-index (or entry-index (let ((index (make-hash-table :test (function equal)))) (dolist (entry entries index) (when (and (consp entry) (not (nth-value 1 (gethash (car entry) index)))) (setf (gethash (car entry) index) entry))))))) (loop for value in values for position from index for key = (snapshot-sequence-key prefix position) for actual-string = (snapshot-string value) for entry = (gethash key entry-index) do (multiple-value-bind (matched reported-actual reported-expected) (call-with-snapshot-comparison/k key actual-string entry (lambda () (values t nil nil)) (lambda (actual expected) (values nil actual expected))) (unless matched (return (multiple-value-call on-mismatch (snapshot-sequence-context-values reported-actual reported-expected prefix position count))))) finally (let ((extra-entry (find-if (lambda (candidate) (let ((candidate-index (and (consp candidate) (snapshot-sequence-key-index prefix (car candidate))))) (and candidate-index (>= candidate-index count)))) entries))) (return (if extra-entry (multiple-value-call on-mismatch (snapshot-sequence-extra-values prefix (snapshot-sequence-key-index prefix (car extra-entry)) count extra-entry)) (funcall on-match)))))))

(defun snapshot-sequence-replacement (prefix values entries)
    (append (remove-snapshot-sequence-entries prefix entries)
            (loop for value in values for index from 0
                  collect (cons (snapshot-sequence-key prefix index)
                                (snapshot-string value)))))

  (defun snapshot-session-current-file ()
    (snapshot-session-file-for (canonical-snapshot-file-pathname)))

  (defun snapshot-current-entries ()
    (if *snapshot-session*
        (let ((session *snapshot-session*)
              (file (snapshot-session-current-file)))
          (with-snapshot-session-lock (session)
            (snapshot-session-file-entries file)))
        (read-snapshot-file)))

  (defun snapshot-current-entry (key)
    (if *snapshot-session*
        (let ((session *snapshot-session*)
              (file (snapshot-session-current-file)))
          (with-snapshot-session-lock (session)
            (gethash key (snapshot-session-file-entry-index file))))
        (snapshot-entry key (read-snapshot-file))))

  (defun snapshot-session-stage (operation) (ensure-directories-exist (snapshot-file-pathname)) (let ((session *snapshot-session*) (file (snapshot-session-current-file))) (with-snapshot-session-lock (session) (setf (snapshot-session-file-entries file) (ecase (car operation) (:replace (replace-snapshot-entry (second operation) (third operation) (snapshot-session-file-entries file))) (:sequence (snapshot-sequence-replacement (second operation) (third operation) (snapshot-session-file-entries file))))) (snapshot-session-refresh-index file) (push operation (snapshot-session-file-operations file)) (setf (snapshot-session-file-dirty-p file) t))))

  (defun snapshot-session-stage-replacement (key actual-string)
    (snapshot-session-stage (list :replace key actual-string)))

  (defun snapshot-session-stage-sequence (prefix values)
    (snapshot-session-stage (list :sequence prefix (copy-list values))))

  (defun snapshot-session-apply-operation (operation entries)
    (ecase (car operation)
      (:replace (replace-snapshot-entry (second operation) (third operation) entries))
      (:sequence (snapshot-sequence-replacement (second operation) (third operation) entries))))

  (defun flush-snapshot-session (session) (let ((files (with-snapshot-session-lock (session) (loop for file being the hash-values of (snapshot-session-files session) when (snapshot-session-file-dirty-p file) collect file)))) (dolist (session-file files) (let ((file (snapshot-session-file-file session-file))) (call-with-snapshot-file-lock file (lambda () (let* ((disk-entries (read-snapshot-file-unlocked file)) (next-entries disk-entries)) (with-snapshot-session-lock (session) (dolist (operation (reverse (snapshot-session-file-operations session-file))) (setf next-entries (snapshot-session-apply-operation operation next-entries)))) (unless (equal disk-entries next-entries) (write-snapshot-file-unlocked next-entries file)) (with-snapshot-session-lock (session) (setf (snapshot-session-file-entries session-file) next-entries (snapshot-session-file-operations session-file) nil (snapshot-session-file-dirty-p session-file) nil) (snapshot-session-refresh-index session-file)))))))))

  (defun call-with-snapshot-session (function) (if *snapshot-session* (funcall function) (let ((*snapshot-session* (make-snapshot-session))) (unwind-protect (funcall function) (flush-snapshot-session *snapshot-session*)))))

  (defun snapshot-match-or-update-p (actual expected)
    (let* ((key (snapshot-key-from-expected expected))
           (actual-string (snapshot-string actual)))
      (if (snapshot-update-enabled-p)
          (if *snapshot-session*
              (progn (snapshot-session-stage-replacement key actual-string) t)
              (call-with-snapshot-update-transaction
               (lambda (entries file)
                 (let ((entry (snapshot-entry key entries)))
                   (unless (and entry (string= actual-string (cdr entry)))
                     (write-snapshot-file-unlocked
                      (replace-snapshot-entry key actual-string entries) file))
                   t))))
          (let ((entry (snapshot-current-entry key)))
            (if (and entry (string= actual-string (cdr entry)))
                t
                (multiple-value-bind (reported-actual reported-expected)
                    (snapshot-comparison-values key actual-string entry)
                  (values nil reported-actual reported-expected)))))))

(defun snapshot-sequence-match-or-update-p (actual expected) (let* ((prefix (snapshot-sequence-prefix-from-expected expected)) (values (snapshot-sequence-values actual)) (count (length values))) (if (snapshot-update-enabled-p) (if *snapshot-session* (progn (snapshot-session-stage-sequence prefix values) t) (call-with-snapshot-update-transaction (lambda (entries file) (let ((next-entries (snapshot-sequence-replacement prefix values entries))) (unless (equal next-entries entries) (write-snapshot-file-unlocked next-entries file)) t)))) (let ((entries (snapshot-current-entries)) (entry-index (and *snapshot-session* (let ((session *snapshot-session*) (file (snapshot-session-current-file))) (with-snapshot-session-lock (session) (snapshot-session-file-entry-index file)))))) (call-with-snapshot-sequence-comparison/k values entries prefix count 0 (lambda () t) (lambda (reported-actual reported-expected) (values nil reported-actual reported-expected)) entry-index)))))
