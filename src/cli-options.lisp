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

(defun string-present-p (value)
  (and value (plusp (length value))))

(defun option-token-p (token)
  (and (string-present-p token)
       (>= (length token) 2)
       (char= (char token 0) #\-)
       (char= (char token 1) #\-)))

(defun environment-value (name)
  (let ((value (uiop:getenv name)))
    (when (string-present-p value)
      value)))

(defun truthy-environment-p (name)
  (let ((value (environment-value name)))
    (and value
         (not (member (string-downcase value) *cli-falsy-tokens*
                      :test #'string=)))))

(defun first-environment-binding (names)
  (loop for name in names
        for value = (environment-value name)
        when value
          return (cons name value)))

(defun parse-boolean (value name)
  (let ((normalized (string-downcase value)))
    (cond
      ((member normalized *cli-boolean-truthy-tokens* :test #'string=) t)
      ((member normalized *cli-falsy-tokens* :test #'string=) nil)
      (t (signal-cli-error "~A must be a boolean: ~A" name value)))))

(defconstant +maximum-numeric-token-length+ 128)

(defun ensure-numeric-token-length (value name)
  (when (> (length value) +maximum-numeric-token-length+)
    (signal-cli-error "~A must not exceed ~D characters"
                       name
                       +maximum-numeric-token-length+))
  value)

(defun parse-complete-integer (value name)
  (ensure-numeric-token-length value name)
  (handler-case
      (parse-integer value :junk-allowed nil)
    (error ()
      (signal-cli-error "~A must be an integer: ~A" name value))))

(defun parse-positive-integer (value name)
  (let ((integer (parse-complete-integer value name)))
    (unless (plusp integer)
      (signal-cli-error "~A must be positive: ~A" name value))
    integer))

(defun parse-non-negative-integer (value name)
    (let ((integer (parse-complete-integer value name)))
      (when (minusp integer)
        (signal-cli-error "~A must be a non-negative integer: ~A" name value))
      integer))

  (defun normalize-runner-option (value name normalizer)
    (handler-case
        (funcall normalizer value)
      (error (condition)
        (signal-cli-error "~A: ~A" name condition))))

  (defmacro define-runner-option-parser (name integer-parser normalizer)
    "Define NAME as a CLI option parser (VALUE OPTION-NAME) that parses VALUE
via INTEGER-PARSER, then runs the result through NORMALIZER -- wrapping any
error NORMALIZER signals as a CLI-ERROR naming OPTION-NAME."
    `(defun ,name (value option-name)
       (normalize-runner-option
        (,integer-parser value option-name)
        option-name
        #',normalizer)))

  (define-runner-option-parser parse-retry-option
      parse-non-negative-integer cl-weave::normalize-retry-count)

  (define-runner-option-parser parse-timeout-ms-option
      parse-positive-integer cl-weave::normalize-timeout-ms)

  (define-runner-option-parser parse-max-workers-option
      parse-positive-integer cl-weave::normalize-max-workers)

(defun parse-positive-number (value name)
  (ensure-numeric-token-length value name)
  (labels ((invalid ()
             (signal-cli-error "~A must be a positive number: ~A" name value))
           (ascii-digit-p (character)
             (char<= #\0 character #\9))
           (digits-p (string)
             (and (plusp (length string))
                  (every #'ascii-digit-p string)))
           (component (string)
             (unless (digits-p string)
               (invalid))
             (parse-integer string :junk-allowed nil)))
    (let* ((first-dot (position #\. value))
           (second-dot (and first-dot
                            (position #\. value :start (1+ first-dot)))))
      (when (or (string= value "") second-dot)
        (invalid))
      (let ((number
              (handler-case
                  (if first-dot
                      (let* ((whole (component (subseq value 0 first-dot)))
                             (fraction-text (subseq value (1+ first-dot)))
                             (fraction (component fraction-text))
                             (denominator (expt 10 (length fraction-text))))
                        (float (+ whole (/ fraction denominator)) 1.0))
                      (component value))
                (arithmetic-error ()
                  (invalid)))))
        (unless (plusp number)
          (invalid))
        number))))

(defun parse-percentage (value name)
  (ensure-numeric-token-length value name)
  (labels ((zero-number-p ()
             (let ((dot (position #\. value)))
               (and (plusp (length value))
                    (if dot
                        (and (plusp dot)
                             (< dot (1- (length value)))
                             (null (position #\. value :start (1+ dot)))
                             (every (lambda (character)
                                      (or (char= character #\0)
                                          (char= character #\.)))
                                    value))
                        (every (lambda (character)
                                 (char= character #\0))
                               value))))))
    (let ((number (if (zero-number-p)
                      0.0
                      (parse-positive-number value name))))
      (when (> number 100)
        (signal-cli-error "~A must not exceed 100: ~A" name value))
      number)))

(defun parse-reporter (value)
  (let ((normalized (string-downcase value)))
    (or (loop for reporter in (cl-weave:run-reporters)
              when (string= normalized (string-downcase (symbol-name reporter)))
                return reporter)
        (signal-cli-error "cl-weave: unknown reporter: ~A" value))))

(defun parse-sequence-order (value)
  (if (string-equal value "random")
      :random
      (signal-cli-error "Unknown sequence order: ~A" value)))

(defun parse-bail (value)
  (ensure-numeric-token-length value "--bail")
  (let ((normalized (string-downcase value)))
    (normalize-runner-option
     (cond
       ((member normalized *cli-bail-truthy-tokens* :test #'string=) t)
       ((member normalized *cli-falsy-tokens* :test #'string=) nil)
       (t
        (let ((parsed (ignore-errors
                        (parse-complete-integer value "--bail"))))
          (unless (and parsed (plusp parsed))
            (signal-cli-error
             "--bail must be true, false, or a positive integer: ~A"
             value))
          parsed)))
     "--bail"
     #'cl-weave::normalize-bail)))

(defun parse-shard (value)
  (ensure-numeric-token-length value "--shard")
  (let ((slash (position #\/ value)))
    (unless slash
      (signal-cli-error "--shard must use INDEX/COUNT: ~A" value))
    (normalize-runner-option
     (list (parse-positive-integer (subseq value 0 slash) "--shard index")
           (parse-positive-integer (subseq value (1+ slash)) "--shard count"))
     "--shard"
     #'cl-weave::normalize-shard)))

(defmacro define-passthrough-option-parser (name transform)
  "Define NAME as a CLI option parser (VALUE IGNORE) that ignores its second
argument and returns (TRANSFORM VALUE)."
  `(defun ,name (value ignore)
     (declare (ignore ignore))
     (,transform value)))

(define-passthrough-option-parser parse-reporter-option parse-reporter)
(define-passthrough-option-parser parse-bail-option parse-bail)
(define-passthrough-option-parser parse-shard-option parse-shard)
(define-passthrough-option-parser parse-sequence-order-option parse-sequence-order)
(define-passthrough-option-parser parse-pathname-option pathname)
(define-passthrough-option-parser parse-system-list-option list)

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
