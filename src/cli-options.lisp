(in-package #:cl-weave/cli)

(defvar *cli-option-specs*)
(defvar *cli-environment-specs*)
(defvar *cli-falsy-tokens*)
(defvar *cli-boolean-truthy-tokens*)
(defvar *cli-bail-truthy-tokens*)
(defvar cl-weave/metadata::*metadata-cli-options*)

(define-condition cli-error (error)
  ((message :initarg :message :reader cli-error-message))
  (:report (lambda (condition stream)
             (write-string (cli-error-message condition) stream))))

(defun signal-cli-error (control &rest arguments)
  "Signal a CLI-ERROR whose message is (FORMAT NIL CONTROL . ARGUMENTS)."
  (error 'cli-error :message (apply #'format nil control arguments)))

(defmacro define-cli-spec-accessors (&rest specifications)
  `(progn
     ,@(loop for (name key) in specifications
             collect `(defun ,name (spec)
                        (getf spec ,key)))))

(define-cli-spec-accessors
  (cli-spec-flag :flag)
  (cli-spec-field :field)
  (cli-spec-kind :kind)
  (cli-spec-command :command)
  (cli-spec-parser :parser)
  (cli-spec-argument-name :argument-name)
  (cli-spec-default :default)
  (cli-spec-value :value)
  (cli-entry-name :name)
  (cli-entry-environment :environment))

(defmacro define-cli-options (&body clauses)
  (labels ((clause (name)
             (or (assoc name clauses)
                 (error "DEFINE-CLI-OPTIONS requires a ~S clause." name)))
           (field-name (definition)
             (if (consp definition) (first definition) definition))
           (validate-specs (specs namespace fields allowed-kinds)
             (let ((flags '()))
               (dolist (spec specs)
                 (let ((flag (cli-spec-flag spec))
                       (field (cli-spec-field spec))
                       (kind (cli-spec-kind spec)))
                   (unless (and (stringp flag) (plusp (length flag)))
                     (error "~A CLI spec requires a non-empty string :FLAG: ~S"
                            namespace spec))
                   (when (member flag flags :test #'string=)
                     (error "Duplicate ~A CLI flag: ~A" namespace flag))
                   (push flag flags)
                   (unless (member field fields)
                     (error "Unknown CLI option field ~S in ~A spec ~S"
                            field namespace flag))
                   (unless (member kind allowed-kinds)
                     (error "Unknown ~A CLI option kind ~S in spec ~S"
                            namespace kind flag)))))))
    (let* ((field-definitions (rest (clause :fields)))
           (option-specs (rest (clause :options)))
           (environment-specs (rest (clause :environment)))
           (fields (mapcar (lambda (definition)
                             (intern (symbol-name (field-name definition)) :keyword))
                           field-definitions))
           (collection-fields
             (remove-duplicates
              (loop for spec in option-specs
                    when (eq (cli-spec-kind spec) :collection)
                      collect (cli-spec-field spec))))
           (field-accessors
             (loop for field in fields
                   collect
                   (cons field
                         (intern (format nil "CLI-OPTIONS-~A" field)
                                 (find-package '#:cl-weave/cli)))))
           (collection-accessors
             (loop for field in collection-fields
                   collect (assoc field field-accessors))))
      (when (/= (length clauses) 3)
        (error "DEFINE-CLI-OPTIONS accepts only :FIELDS, :OPTIONS, and :ENVIRONMENT."))
      (validate-specs option-specs "command-line" fields
                      '(:flag :collection :value :optional-value))
      (validate-specs environment-specs "environment" fields '(:value :truthy))
      `(progn
         (defstruct (cli-options (:constructor make-cli-options))
           ,@field-definitions)
         (defparameter *cli-option-specs* ',option-specs)
         (defparameter *cli-environment-specs* ',environment-specs)
         (defun set-cli-option-field (options field value)
           (let ((accessor (cdr (assoc field ',field-accessors))))
             (unless accessor
               (error "Unknown CLI option field: ~S" field))
             (funcall (fdefinition (list 'setf accessor)) value options))
           options)
         (defun push-cli-option-field (options field value)
           (let ((accessor (cdr (assoc field ',collection-accessors))))
             (unless accessor
               (error "Unknown collection CLI option field: ~S" field))
             (funcall (fdefinition (list 'setf accessor))
                      (cons value (funcall accessor options))
                      options))
           options)))))

(defun cli-option-spec (flag)
  (find flag *cli-option-specs* :key #'cli-spec-flag
        :test #'string=))

(defun cli-environment-spec (flag)
  (find flag *cli-environment-specs* :key #'cli-spec-flag
        :test #'string=))

(defun apply-cli-option-command (options spec)
  (let ((command (cli-spec-command spec)))
    (when command
      (set-cli-option-field options :command command))))

(defun call-cli-option-parser (parser value name)
  (if parser
      (funcall parser value name)
      value))

(defun require-option-argument (flag rest &optional inline-p)
  ;; When INLINE-P, the value was given explicitly as `--flag=VALUE`, so it is
  ;; taken verbatim even if it looks like an option token (e.g.
  ;; `--filter=--foo`) -- that inline form exists precisely to pass values that
  ;; begin with dashes. The separate `--flag VALUE` form still rejects a
  ;; following option token as a missing argument.
  (let ((value (first rest)))
    (unless (and value (or inline-p (not (option-token-p value))))
      (signal-cli-error "~A requires an argument" flag))
    value))

(defun option-name-and-inline-value (token)
  (let ((equals (position #\= token)))
    (if equals
        (values (subseq token 0 equals) (subseq token (1+ equals)) t)
        (values token nil nil))))

(defun bail-value-token-p (value)
  (handler-case
      (progn
        (parse-bail value)
        t)
    (cli-error () nil)))

(defun consume-optional-value (default rest accept-value-p)
  (if (and (first rest)
           (not (option-token-p (first rest)))
           (funcall accept-value-p (first rest)))
      (values (first rest) (rest rest))
      (values default rest)))

(defun optional-value-token-p (flag value)
  (cond
    ((string= flag "--bail") (bail-value-token-p value))
    (t nil)))

(defun apply-cli-option (options flag rest inline-p)
  (let ((spec (cli-option-spec flag)))
    (unless spec
      (signal-cli-error "Unknown option: ~A" flag))
    (ecase (cli-spec-kind spec)
      (:flag
       (when inline-p
         (signal-cli-error "~A does not accept an inline value" flag))
       (set-cli-option-field options (cli-spec-field spec)
                             (if (member :value spec) (cli-spec-value spec) t))
       (apply-cli-option-command options spec)
       rest)
      (:collection
       (push-cli-option-field options (cli-spec-field spec)
                              (require-option-argument flag rest inline-p))
       (rest rest))
      (:value
       (let* ((raw (require-option-argument flag rest inline-p))
              (name (or (cli-spec-argument-name spec) flag))
              (value (call-cli-option-parser (cli-spec-parser spec) raw name)))
         (set-cli-option-field options (cli-spec-field spec) value)
         (rest rest)))
      (:optional-value
       (multiple-value-bind (raw remaining)
           (if inline-p
               (values (first rest) (rest rest))
               (consume-optional-value
                (cli-spec-default spec)
                rest
                (lambda (value)
                  (optional-value-token-p flag value))))
         (let* ((name (or (cli-spec-argument-name spec) flag))
                (value (call-cli-option-parser (cli-spec-parser spec) raw name)))
           (set-cli-option-field options (cli-spec-field spec) value)
           remaining))))))

(defun apply-cli-option-environment (options entry)
  (let* ((binding (first-environment-binding (cli-entry-environment entry)))
         (name (car binding))
         (value (cdr binding))
         (option-name (cli-entry-name entry))
         (spec (cli-environment-spec option-name)))
    (when binding
      (unless spec
        (signal-cli-error "Unhandled environment-backed CLI option: ~A" option-name))
      (ecase (cli-spec-kind spec)
        (:value
         (set-cli-option-field
          options
          (cli-spec-field spec)
          (call-cli-option-parser (cli-spec-parser spec) value name)))
        (:truthy
         (when (truthy-environment-p name)
           (set-cli-option-field options (cli-spec-field spec) t)
           (apply-cli-option-command options spec)))))))

(defun options-from-environment ()
  (let ((options (make-cli-options)))
    (dolist (entry *metadata-cli-options*)
      (apply-cli-option-environment options entry))
    options))
