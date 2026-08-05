(in-package #:cl-weave)

(defmacro expect (actual &body expectation)
  (if expectation
      (expand-matcher-expectation 'expect actual expectation)
      (expand-smart-assertion actual `(expect ,actual))))

(defmacro expect-not (actual &body expectation)
  (expand-matcher-expectation 'expect-not actual expectation :negated t))

(defmacro signals (condition-type &body body)
  `(expect (lambda () ,@body) :to-throw ',condition-type))

(defmacro finishes (&body body)
  `(expect (lambda () ,@body) :not :to-throw))

(defmacro fail (&optional (reason "explicit failure") &rest args)
  `(signal-fail-assertion
    ,(if args
         `(format nil ,reason ,@args)
         reason)))

(defun signal-skip (reason)
  (let ((restart (find-restart 'skip-test)))
    (if restart
        (invoke-restart restart reason)
        (error "cl-weave: skip requested outside a running test: ~A" reason))))

(defun signal-fail-assertion (reason)
  (record-assertion)
  (signal-assertion-failure
   (make-assertion-detail
    :form '(fail)
    :matcher :fail
    :actual reason
    :expected '(:no-explicit-failure)
    :negated nil
    :pass nil)))

(defmacro skip (&optional (reason "skipped"))
  `(signal-skip ,reason))

(defmacro expect-poll (thunk &body body)
  (multiple-value-bind (options expectation) (split-leading-option-plist body)
    (when (null expectation)
      (error "cl-weave: EXPECT-POLL requires a matcher, for example ~
              (EXPECT-POLL thunk :to-be expected)."))
    `(progn
       (record-assertion)
       (call-polling-expectation-thunk
        ,thunk
        (list ,@expectation)
        ,(if options
             `(list ,@options)
             nil)
        '(expect-poll ,thunk ,@body)))))

(defmacro expect-assertions (count)
  `(set-expected-assertion-count ,count '(expect-assertions ,count)))

(defmacro expect-has-assertions ()
  `(set-has-assertions-required '(expect-has-assertions)))

(defmacro expect-resolves (thunk &body expectation)
  `(expect (call-resolving-expectation-thunk
            ,thunk
            '(expect-resolves ,thunk ,@expectation))
           ,@expectation))

(defmacro expect-rejects (thunk &body expectation)
  `(expect (call-rejecting-expectation-thunk
            ,thunk
            '(expect-rejects ,thunk ,@expectation))
           ,@expectation))

(defmacro with-snapshot-updates (&body body)
  `(let ((*update-snapshots* t))
     ,@body))

(defmacro with-mocked-functions (bindings &environment environment &body body)
  (let ((expansions
          (loop for (place replacement) in bindings
                collect
                (multiple-value-bind (temps values stores writer reader)
                    (get-setf-expansion place environment)
                  (unless (= (length stores) 1)
                    (error "WITH-MOCKED-FUNCTIONS supports only single-value places, got ~S."
                           place))
                  (list :temps temps
                        :values values
                        :store (first stores)
                        :writer writer
                        :reader reader
                        :replacement replacement
                        :saved (gensym "SAVED-"))))))
    `(let* (,@(loop for expansion in expansions
                    append (destructuring-bind (&key temps values reader saved &allow-other-keys)
                               expansion
                             (append (mapcar #'list temps values)
                                     `((,saved ,reader))))))
       (unwind-protect
            (progn
              ,@(loop for expansion in expansions
                      collect (destructuring-bind (&key store writer replacement &allow-other-keys)
                                  expansion
                                `(let ((,store ,replacement))
                                   ,writer)))
              ,@body)
         ,@(loop for expansion in expansions
                 collect (destructuring-bind (&key store writer saved &allow-other-keys)
                             expansion
                           `(let ((,store ,saved))
                              ,writer)))))))
