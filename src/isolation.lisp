(in-package #:cl-weave)

(defun finite-proper-list-p (object)
  "Return T when OBJECT is a proper list, safely rejecting dotted and circular
lists via Floyd tortoise-and-hare traversal. Shared by the matcher and property
subsystems, which load after this file."
  (loop with slow = object
        with fast = object
        do (cond
             ((null fast) (return t))
             ((atom fast) (return nil))
             ((null (cdr fast)) (return t))
             ((atom (cdr fast)) (return nil))
             (t
              (setf slow (cdr slow)
                    fast (cddr fast))
              (when (eq slow fast)
                (return nil))))))

(defvar *isolated-timeout-seconds* 5)

(defstruct isolated-result
  status
  exit-code
  stdout
  stderr
  timed-out-p
  elapsed-ms
  script-path
  stdout-path
  stderr-path
  home-path)

(defun normalize-isolated-systems (systems)
  (cond
    ((null systems) nil)
    ((stringp systems) (list systems))
    ((symbolp systems) (list (string-downcase (symbol-name systems))))
    ((listp systems)
     (mapcar (lambda (system)
               (etypecase system
                 (string system)
                 (symbol (string-downcase (symbol-name system)))))
             systems))
    (t (error "cl-weave: isolated systems must be a string, symbol, or list, got ~S."
              systems))))

(defun isolated-temp-name (prefix)
  (format nil "~A-~36R-~36R-~36R"
          prefix
          (get-internal-real-time)
          (get-universal-time)
          (random (expt 36 8))))

(defun isolated-temp-pathname (prefix type)
  (loop repeat 100
        for pathname = (merge-pathnames
                        (make-pathname :name (isolated-temp-name prefix)
                                       :type type)
                        (uiop:temporary-directory))
        for stream = (open pathname
                           :direction :output
                           :if-exists nil
                           :if-does-not-exist :create)
        when stream
          do (close stream)
             (return pathname)
        finally (error "cl-weave: failed to allocate isolated temp file for ~A.~A"
                       prefix
                       type)))

(defun isolated-temp-directory (prefix)
  (loop repeat 100
        for pathname = (merge-pathnames
                        (make-pathname :directory (list :relative
                                                        (isolated-temp-name prefix)))
                        (uiop:temporary-directory))
        when (isolated-create-temp-directory pathname)
          do
             (return pathname)
        finally (error "cl-weave: failed to allocate isolated temp directory for ~A"
                       prefix)))

(defun isolated-create-temp-directory (pathname)
  (unless (probe-file pathname)
    (ensure-directories-exist pathname)
    t))

(defun read-file-string-or-empty (pathname)
  (if (probe-file pathname)
      (uiop:read-file-string pathname)
      ""))

(defun maybe-path-namestring (pathname keep-files)
  (and keep-files pathname (namestring pathname)))

(defun normalize-isolated-keep-files (keep-files)
  (case keep-files
    ((nil) nil)
    ((t) t)
    (:on-failure :on-failure)
    (otherwise
     (error "cl-weave: isolated keep-files must be NIL, T, or :ON-FAILURE, got ~S."
            keep-files))))

(defun isolated-retain-files-p (keep-files status)
  (case keep-files
    ((nil) nil)
    ((t) t)
    (:on-failure (not (eq status :pass)))))

#+sbcl
(defun isolated-environment-entry-name-p (name entry)
  (let ((prefix (concatenate 'string name "=")))
    (and (>= (length entry) (length prefix))
         (string= prefix (subseq entry 0 (length prefix))))))

#+sbcl
(defun isolated-process-environment (home)
  (let* ((cache (merge-pathnames #p".cache/" home))
         (replacements (list (format nil "HOME=~A" (namestring home))
                             (format nil "XDG_CACHE_HOME=~A" (namestring cache)))))
    (ensure-directories-exist cache)
    (append replacements
            (remove-if
             (lambda (entry)
               (or (isolated-environment-entry-name-p "HOME" entry)
                   (isolated-environment-entry-name-p "XDG_CACHE_HOME" entry)))
             (sb-ext:posix-environ)))))

(defun write-isolated-script (pathname form systems package)
  (with-open-file (stream pathname :direction :output :if-exists :supersede)
    (let ((*print-case* :downcase)
          (*print-pretty* t))
      (write
       `(progn
          (require :asdf)
          (pushnew (truename ".")
                   (symbol-value (find-symbol "*CENTRAL-REGISTRY*" "ASDF"))
                   :test #'equal)
          ,@(loop for system in (normalize-isolated-systems systems)
                  collect `(funcall
                            (symbol-function (find-symbol "LOAD-SYSTEM" "ASDF"))
                            ,system)))
       :stream stream)
      (terpri stream)
      (write `(in-package ,(string-upcase (string package))) :stream stream)
      (terpri stream)
      (write
       `(handler-case
            (progn
              ,form
              (funcall (symbol-function (find-symbol "EXIT" "SB-EXT")) :code 0))
          (condition (condition)
            (format *error-output* "~&~A~%" condition)
            (funcall (symbol-function (find-symbol "PRINT-BACKTRACE" "SB-DEBUG"))
                     :stream *error-output*)
            (funcall (symbol-function (find-symbol "EXIT" "SB-EXT")) :code 1)))
       :stream stream)
      (terpri stream)))
  pathname)

#+sbcl
(defun isolated-sbcl-program ()
  ;; SB-EXT:*RUNTIME-PATHNAME* names the SBCL running us, which is the one an
  ;; isolated child should be started with -- except in a standalone
  ;; executable image, where the runtime and the core are the same file and
  ;; that file is cl-weave itself, not a Lisp that understands --script. SBCL
  ;; makes the two equal only in that shape, so it is a reliable test. Fall
  ;; back to the SBCL on PATH there; RUN-PROGRAM below searches for it.
  (or (when (and (boundp 'sb-ext:*runtime-pathname*)
                 sb-ext:*runtime-pathname*
                 (not (equal sb-ext:*runtime-pathname*
                             sb-ext:*core-pathname*)))
        (namestring sb-ext:*runtime-pathname*))
      "sbcl"))

#+sbcl
(defun wait-isolated-process (process timeout)
  (let ((deadline (+ (get-internal-real-time)
                     (round (* timeout internal-time-units-per-second)))))
    (loop while (sb-ext:process-alive-p process)
          do (when (>= (get-internal-real-time) deadline)
               (ignore-errors (sb-ext:process-kill process 15))
               (sleep 0.05)
               (when (sb-ext:process-alive-p process)
                 (ignore-errors (sb-ext:process-kill process 9)))
               (ignore-errors (sb-ext:process-wait process))
               (return :timeout))
             (sleep 0.01)
          finally (progn
                    (sb-ext:process-wait process)
                    (return :finished)))))

#+sbcl
(defun run-isolated (form &key
                            (systems '("cl-weave"))
                            (package (package-name *package*))
                            (timeout *isolated-timeout-seconds*)
                            keep-files)
  (require-platform-capability :isolation)
  (unless (and (numberp timeout) (plusp timeout))
    (error "cl-weave: isolated timeout must be a positive number, got ~S." timeout))
  (let* ((keep-files (normalize-isolated-keep-files keep-files))
         script
         stdout
         stderr
         home
         (started (get-internal-real-time))
         result
         retain-files)
    (unwind-protect
         (progn
           (setf script (isolated-temp-pathname "cl-weave-isolated" "lisp")
                 stdout (isolated-temp-pathname "cl-weave-isolated" "out")
                 stderr (isolated-temp-pathname "cl-weave-isolated" "err")
                 home (isolated-temp-directory "cl-weave-isolated-home"))
           (write-isolated-script script form systems package)
           (let* ((process
                     (sb-ext:run-program
                      (isolated-sbcl-program)
                      (list "--script" (namestring script))
                      :search t
                      :wait nil
                      :output stdout
                      :error stderr
                      :environment (isolated-process-environment home)
                      :if-output-exists :supersede
                      :if-error-exists :supersede))
                  (wait-status (wait-isolated-process process timeout))
                  (exit-code (sb-ext:process-exit-code process))
                  (elapsed-ms (/ (* 1000
                                    (- (get-internal-real-time) started))
                                 internal-time-units-per-second))
                  (status (cond
                            ((eq wait-status :timeout) :timeout)
                            ((eql exit-code 0) :pass)
                            (t :fail))))
             (setf retain-files (isolated-retain-files-p keep-files status)
                   result (make-isolated-result
                           :status status
                           :exit-code exit-code
                           :stdout (read-file-string-or-empty stdout)
                           :stderr (read-file-string-or-empty stderr)
                           :timed-out-p (eq wait-status :timeout)
                           :elapsed-ms elapsed-ms
                           :script-path (maybe-path-namestring script retain-files)
                           :stdout-path (maybe-path-namestring stdout retain-files)
                           :stderr-path (maybe-path-namestring stderr retain-files)
                           :home-path (maybe-path-namestring home retain-files)))
             result))
      (unless retain-files
        (ignore-errors (delete-file script))
        (ignore-errors (delete-file stdout))
        (ignore-errors (delete-file stderr))
        (ignore-errors
          (uiop:delete-directory-tree home :validate t :if-does-not-exist :ignore))))))

#-sbcl
(defun run-isolated (form &key systems package timeout keep-files)
  (declare (ignore form systems package timeout keep-files))
  (require-platform-capability :isolation))

(defun signal-isolated-failure (result form)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher :isolated
    :actual (list :status (isolated-result-status result)
                  :exit-code (isolated-result-exit-code result)
                  :timed-out-p (isolated-result-timed-out-p result)
                  :elapsed-ms (isolated-result-elapsed-ms result)
                  :stdout (isolated-result-stdout result)
                  :stderr (isolated-result-stderr result)
                  :script-path (isolated-result-script-path result)
                  :stdout-path (isolated-result-stdout-path result)
                  :stderr-path (isolated-result-stderr-path result)
                  :home-path (isolated-result-home-path result))
    :expected '(:status :pass :exit-code 0)
    :negated nil
    :pass nil)))
