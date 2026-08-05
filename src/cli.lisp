(in-package #:cl-weave/cli)

(defun command-token-p (token)
  (member token *metadata-commands* :test #'string=))

(defparameter *cli-command-token-effects*
  ;; Fields SET-CLI-OPTION-FIELD applies for each token in *METADATA-COMMANDS*.
  ;; RUN/DOCTOR/METADATA set only :COMMAND; LIST/WATCH also flip their own
  ;; boolean flag; VERSION/HELP set only their own flag, leaving :COMMAND alone.
  '(("run" (:command . :run))
    ("list" (:command . :list) (:list . t))
    ("watch" (:command . :watch) (:watch . t))
    ("doctor" (:command . :doctor))
    ("metadata" (:command . :metadata))
    ("version" (:version . t))
    ("help" (:help . t))))

(defparameter *cli-command-token-effect-table*
  ;; O(1) index over *CLI-COMMAND-TOKEN-EFFECTS*, built once at load time so
  ;; APPLY-COMMAND-TOKEN does not linearly rescan the table on every CLI token.
  (let ((table (make-hash-table :test 'equal)))
    (dolist (entry *cli-command-token-effects* table)
      (setf (gethash (first entry) table) (rest entry)))))

(defun apply-command-token (options token)
  (dolist (field.value (gethash token *cli-command-token-effect-table*))
    (set-cli-option-field options (car field.value) (cdr field.value))))

(defun handle-option-token (options token rest)
  (multiple-value-bind (flag inline-value inline-p)
      (option-name-and-inline-value token)
    (apply-cli-option options flag
                      (if inline-p (list* inline-value rest) rest)
                      inline-p)))

(defun command-allows-positional-system-p (command)
  (member command '(:run :list :watch :doctor :metadata)))

(defun normalize-cli-arguments (argv)
  (if (and argv (string= (first argv) "--"))
      (rest argv)
      argv))

(defun finish-cli-argument-parse (options)
  (setf (cli-options-systems options)
        (nreverse (cli-options-systems options))
        (cli-options-load-files options)
        (nreverse (cli-options-load-files options)))
  options)

(defun parse-cli-argument/k (options command-seen token tail k)
  (cond
    ((option-token-p token)
     (funcall k (handle-option-token options token tail) command-seen))
    ((and (not command-seen) (command-token-p token))
     (apply-command-token options token)
     (funcall k tail t))
    ((and (command-allows-positional-system-p (cli-options-command options))
          (null (cli-options-systems options)))
     (push token (cli-options-systems options))
     (funcall k tail command-seen))
    (t
     (error 'cli-error
            :message (format nil "Unexpected argument: ~A" token)))))

(defun parse-cli-arguments/k (options rest command-seen k)
  (if (null rest)
      (funcall k (finish-cli-argument-parse options))
      (parse-cli-argument/k
       options
       command-seen
       (first rest)
       (rest rest)
       (lambda (next next-command-seen)
         (parse-cli-arguments/k options next next-command-seen k)))))

(defun parse-cli-arguments (argv &optional (options (options-from-environment)))
  (parse-cli-arguments/k options
                         (normalize-cli-arguments argv)
                         nil
                         #'identity))

(defun cli-usage ()
  (format nil "~{~A~%~}"
          (append
           '("Usage:"
             "  cl-weave run [SYSTEM] [options]"
             "  cl-weave list [SYSTEM] [options]"
             "  cl-weave watch [SYSTEM] [options]"
             "  cl-weave doctor [SYSTEM] [options]"
             "  cl-weave metadata [SYSTEM] [options]"
             "  cl-weave version"
             "  cl-weave help"
             ""
             "Options:")
           (loop for entry in (metadata-cli-options)
                 append (cli-option-usage-lines entry)))))
