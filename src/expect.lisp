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
  `(let ((reason ,(if args
                      `(format nil ,reason ,@args)
                      reason)))
     (record-assertion)
     (signal-assertion-failure
      (make-assertion-detail
       :form '(fail)
       :matcher :fail
       :actual reason
       :expected '(:no-explicit-failure)
       :negated nil
       :pass nil))))

(defmacro skip (&optional (reason "skipped"))
  `(let ((reason ,reason))
     (let ((restart (find-restart 'skip-test)))
       (if restart
           (invoke-restart restart reason)
           (error "cl-weave: skip requested outside a running test: ~A" reason)))))

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
                  (list temps values (first stores) writer reader replacement
                        (gensym "SAVED-"))))))
    `(let* (,@(loop for (temps values nil nil reader nil saved) in expansions
                    append (append
                            (loop for temp in temps
                                  for value in values
                                  collect `(,temp ,value))
                            `((,saved ,reader)))))
       (unwind-protect
            (progn
              ,@(loop for (nil nil store writer nil replacement nil) in expansions
                      collect `(let ((,store ,replacement))
                                 ,writer))
              ,@body)
         ,@(loop for (nil nil store writer nil nil saved) in expansions
                 collect `(let ((,store ,saved))
                            ,writer))))))
