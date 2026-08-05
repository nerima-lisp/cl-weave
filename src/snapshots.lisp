(in-package #:cl-weave)

(defvar *update-snapshots* nil)

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
            return (list :line line-number :expected expected-line :actual actual-line))))

(defun snapshot-comparison-values (key actual-string entry)
  (let* ((file (namestring (snapshot-file-pathname)))
         (expected-present-p (not (null entry)))
         (expected-string (and entry (cdr entry)))
         (difference
        (when expected-present-p
          (snapshot-first-difference expected-string actual-string)))
         (reason
        (if expected-present-p :snapshot-mismatch
          :missing-snapshot)))
    (values
      (list
        :snapshot-key
        key
        :snapshot-file
        file
        :value
        actual-string
        :reason
        reason
        :difference
        difference)
      (list
        :snapshot-key
        key
        :snapshot-file
        file
        :value
        expected-string
        :present
        expected-present-p
        :reason
        reason
        :difference
        difference))))

(defun snapshot-entries ()
  (copy-tree (snapshot-current-entries)))

(defun snapshot-value (key)
  (unless (stringp key)
    (error "cl-weave:snapshot-value expects a string snapshot key."))
  (let ((entry (snapshot-current-entry key)))
    (if entry (values (cdr entry) t)
      (values nil nil))))

(defun call-with-snapshot-update-transaction (function)
  (let ((file (snapshot-file-pathname)))
    (ensure-directories-exist file)
    (setf file (canonical-snapshot-file-pathname file))
    (call-with-snapshot-file-lock
      file
      (lambda ()
        (funcall function (read-snapshot-file-unlocked file) file)))))

(defun snapshot-update-token-p (value)
  (member (string-downcase value) '("1" "true" "yes" "update") :test #'string=))

(defun snapshot-update-enabled-p ()
  (or
    *update-snapshots*
    #+
    sbcl
    (let ((value (sb-ext:posix-getenv "CL_WEAVE_UPDATE_SNAPSHOTS")))
      (and value (snapshot-update-token-p value)))
    #-
    sbcl
    nil))

(defmacro define-snapshot-expected-reader (name matcher-label value-name)
  `(defun ,name (expected)
    (unless (= (length expected) 1)
      (error
        "Matcher ~A expects exactly one string ~A, got ~D values."
        ,matcher-label
        ,value-name
        (length expected)))
    (let ((value (first expected)))
      (unless (stringp value)
        (error "Matcher ~A expects a string ~A." ,matcher-label ,value-name))
      value)))

(define-snapshot-expected-reader
  snapshot-key-from-expected
  ":to-match-snapshot"
  "snapshot key")

(define-snapshot-expected-reader
  snapshot-sequence-prefix-from-expected
  ":to-match-snapshot-sequence"
  "snapshot key prefix")

(defun snapshot-sequence-values (actual)
  (typecase actual
    (list actual)
    ((and vector (not string)) (coerce actual 'list))
    (t
      (error
        "Matcher :to-match-snapshot-sequence expects a list or non-string ~
             vector of states, got ~S."
        actual))))

(defun snapshot-sequence-context-values (actual expected prefix index count)
  (values
    (append
      actual
      (list :snapshot-prefix prefix :snapshot-index index :snapshot-count count))
    (append
      expected
      (list :snapshot-prefix prefix :snapshot-index index :snapshot-count count))))

(defun snapshot-sequence-extra-values (prefix index count entry)
  (let ((file (namestring (snapshot-file-pathname))))
    (values
      (list
        :snapshot-prefix
        prefix
        :snapshot-key
        (car entry)
        :snapshot-file
        file
        :snapshot-index
        index
        :snapshot-count
        count
        :value
        nil
        :present
        nil
        :reason
        :unexpected-snapshot)
      (list
        :snapshot-prefix
        prefix
        :snapshot-key
        (car entry)
        :snapshot-file
        file
        :snapshot-index
        index
        :snapshot-count
        count
        :value
        (cdr entry)
        :present
        t
        :reason
        :unexpected-snapshot))))

(defun call-with-snapshot-comparison/k (key actual-string entry on-match on-mismatch)
  (if (and entry (string= actual-string (cdr entry))) (funcall on-match)
    (multiple-value-call
      on-mismatch
      (snapshot-comparison-values key actual-string entry))))

(defun call-with-snapshot-sequence-comparison/k (values entries prefix count index on-match on-mismatch &optional entry-index)
  (let ((entry-index
        (or
          entry-index
          (let ((entry-table (make-hash-table :test (function equal))))
            (dolist (entry entries entry-table)
              (when (and (consp entry) (not (nth-value 1 (gethash (car entry) entry-table))))
                (setf (gethash (car entry) entry-table) entry)))))))
    (loop for value in values
          for position from index
          for key = (snapshot-sequence-key prefix position)
          for actual-string = (snapshot-string value)
          for entry = (gethash key entry-index)
          do (multiple-value-bind (matched reported-actual reported-expected) (call-with-snapshot-comparison/k
          key
          actual-string
          entry
          (lambda ()
            (values t nil nil))
          (lambda (actual expected)
            (values nil actual expected)))
        (unless matched
          (return
            (multiple-value-call
              on-mismatch
              (snapshot-sequence-context-values
                reported-actual
                reported-expected
                prefix
                position
                count)))))
          finally (let ((extra-entry
            (find-if
              (lambda (candidate)
                (let ((candidate-index
                      (and (consp candidate) (snapshot-sequence-key-index prefix (car candidate)))))
                  (and candidate-index (>= candidate-index count))))
              entries)))
        (return
          (if extra-entry (multiple-value-call
              on-mismatch
              (snapshot-sequence-extra-values
                prefix
                (snapshot-sequence-key-index prefix (car extra-entry))
                count
                extra-entry))
            (funcall on-match)))))))

(defun snapshot-match-or-update-p (actual expected)
  (let* ((key (snapshot-key-from-expected expected))
         (actual-string (snapshot-string actual)))
    (if (snapshot-update-enabled-p) (if *snapshot-session* (progn
          (snapshot-session-stage-replacement key actual-string)
          t)
        (call-with-snapshot-update-transaction
          (lambda (entries file)
            (let ((entry (snapshot-entry key entries)))
              (unless (and entry (string= actual-string (cdr entry)))
                (write-snapshot-file-unlocked
                  (replace-snapshot-entry key actual-string entries)
                  file))
              t))))
      (let ((entry (snapshot-current-entry key)))
        (if (and entry (string= actual-string (cdr entry))) t
          (multiple-value-bind (reported-actual reported-expected) (snapshot-comparison-values key actual-string entry)
            (values nil reported-actual reported-expected)))))))

(defun snapshot-sequence-match-or-update-p (actual expected)
  (let* ((prefix (snapshot-sequence-prefix-from-expected expected))
         (values (snapshot-sequence-values actual))
         (count (length values)))
    (if (snapshot-update-enabled-p) (if *snapshot-session* (progn
          (snapshot-session-stage-sequence prefix values)
          t)
        (call-with-snapshot-update-transaction
          (lambda (entries file)
            (let ((next-entries (snapshot-sequence-replacement prefix values entries)))
              (unless (equal next-entries entries)
                (write-snapshot-file-unlocked next-entries file))
              t))))
      (let ((entries (snapshot-current-entries))
            (entry-index
            (and
              *snapshot-session*
              (let ((session *snapshot-session*)
                    (file (snapshot-session-current-file)))
                (with-snapshot-session-lock (session) (snapshot-session-file-entry-index file))))))
        (call-with-snapshot-sequence-comparison/k
          values
          entries
          prefix
          count
          0
          (lambda ()
            t)
          (lambda (reported-actual reported-expected)
            (values nil reported-actual reported-expected))
          entry-index)))))
