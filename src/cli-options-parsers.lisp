(in-package #:cl-weave/cli)

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
