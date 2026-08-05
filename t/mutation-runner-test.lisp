(in-package #:cl-weave/test)

(defun collected-mutation-forms (form &key operators)
  (mapcar #'mutation-form
          (if operators
              (collect-mutations form :operators operators)
              (collect-mutations form))))

(defun expect-arithmetic-mutation (source expected)
  (expect (collected-mutation-forms source
                                    :operators '(:arithmetic-operator))
          :to-contain
          expected))

(defun expect-arithmetic-mutations (cases)
  (dolist (case cases)
    (destructuring-bind (source expected) case
      (expect-arithmetic-mutation source expected))))

(describe "mutation testing"
  (it "collects one-at-a-time form mutations"
    (let ((mutations (collect-mutations '(if (= value 1) (+ value 2) nil))))
      (expect (mapcar #'mutation-operator mutations) :to-contain :comparison-operator)
      (expect (mapcar #'mutation-operator mutations) :to-contain :arithmetic-operator)
      (expect (mapcar #'mutation-operator mutations) :to-contain :boolean-literal)
      (expect (mapcar #'mutation-operator mutations) :to-contain :conditional-branch)
      (expect (mapcar #'mutation-form mutations) :to-contain
              '(if (/= value 1) (+ value 2) nil))
      (expect (mapcar #'mutation-form mutations) :to-contain
              '(if (= value 1) (- value 2) nil))))

  (it "lists mutation operators as deterministic metadata"
    (let ((operators (list-mutation-operators))
          (custom-metadata (mutation-operator-metadata :keyword-toggle)))
      (expect (mapcar (lambda (entry) (getf entry :name)) operators)
              :to-contain
              :arithmetic-operator)
      (expect (mapcar (lambda (entry) (getf entry :name)) operators)
              :to-contain
              :keyword-toggle)
      (expect (getf (mutation-operator-metadata :arithmetic-operator) :description)
              :to-contain
              "arithmetic")
      (expect (getf custom-metadata :description)
              :to-equal
              "Toggles :enabled keyword literals to :disabled.")))

  (it "supports macro-defined custom mutation operators"
    (let ((mutations (collect-mutations '(:enabled)
                                        :operators '(:keyword-toggle))))
      (expect (length mutations) :to-be 1)
      (expect (mutation-operator (first mutations)) :to-be :keyword-toggle)
      (expect (mutation-path (first mutations)) :to-equal '(0))
      (expect (mutation-original (first mutations)) :to-be :enabled)
      (expect (mutation-replacement (first mutations)) :to-be :disabled)
      (expect (mutation-form (first mutations)) :to-equal '(:disabled))))

  (it "does not mutate quoted forms or named function syntax"
    (expect (collect-mutations '(quote (+ t nil))) :to-equal nil)
    (expect (collect-mutations '(function calculate-value)) :to-equal nil))

  (it "mutates executable lambda bodies in function forms"
    (expect (collected-mutation-forms
             '(function (lambda (value) (+ value 1))))
            :to-contain
            '(function (lambda (value) (- value 1)))))

  (it "mutates lambda bodies but not lambda lists or declarations"
    (let ((mutations
            (collect-mutations
             '(lambda (value &optional (= 1 2))
                (declare (type (integer 0 10) value))
                (+ value 1)))))
      (expect (length mutations) :to-be 1)
      (expect (mutation-path (first mutations)) :to-equal '(3))
      (expect (mutation-original (first mutations)) :to-equal '(+ value 1))
      (expect (mutation-form (first mutations)) :to-equal
              '(lambda (value &optional (= 1 2))
                 (declare (type (integer 0 10) value))
                 (- value 1)))))

  (it "mutates evaluated condition and function-position lambda forms"
    (let ((cond-mutations
            (collect-mutations '(cond ((= value 1) :matched) (t :fallback))))
          (lambda-mutations
            (collect-mutations '((lambda (value) (+ value 1)) 2))))
      (expect (mapcar #'mutation-form cond-mutations) :to-contain
              '(cond ((/= value 1) :matched) (t :fallback)))
      (expect (mapcar #'mutation-form lambda-mutations) :to-contain
              '((lambda (value) (- value 1)) 2))))

  (it "mutates handler and restart clause bodies but not clause syntax"
    (let ((handler-mutations
            (collect-mutations
             '(handler-case (parse value)
                (error (condition)
                  (declare (ignore condition))
                  (+ value 1)))))
          (restart-mutations
            (collect-mutations
             '(restart-case (parse value)
                (use-value (replacement)
                  (+ replacement 1))))))
      (expect (mapcar #'mutation-form handler-mutations) :to-contain
              '(handler-case (parse value)
                 (error (condition)
                   (declare (ignore condition))
                   (- value 1))))
      (expect (mapcar #'mutation-form restart-mutations) :to-contain
              '(restart-case (parse value)
                 (use-value (replacement)
                   (- replacement 1))))))

  (it "walks evaluated positions across binding and control contexts"
    (expect-arithmetic-mutations
     '(((let* ((value (+ 1 2))) value)
        (let* ((value (- 1 2))) value))
       ((multiple-value-bind (value) (+ 1 2) value)
        (multiple-value-bind (value) (- 1 2) value))
       ((destructuring-bind (value) (list (+ 1 2)) value)
        (destructuring-bind (value) (list (- 1 2)) value))
       ((flet ((compute (value) (+ value 1))) (compute 2))
        (flet ((compute (value) (- value 1))) (compute 2)))
       ((labels ((compute (value) (+ value 1))) (compute 2))
        (labels ((compute (value) (- value 1))) (compute 2)))
       ((macrolet ((compute (value) (+ value 1))) (compute 2))
        (macrolet ((compute (value) (- value 1))) (compute 2)))
       ((symbol-macrolet ((value (+ 1 2))) value)
        (symbol-macrolet ((value (- 1 2))) value))
       ((do ((value (+ 1 2) (+ value 1)))
            ((> value 3) (+ value 2))
          (+ value 3))
        (do ((value (- 1 2) (+ value 1)))
            ((> value 3) (+ value 2))
          (+ value 3)))
       ((do* ((value 0 (+ value 1)))
             ((> value 3) (+ value 2)))
        (do* ((value 0 (- value 1)))
             ((> value 3) (+ value 2))))
       ((handler-bind ((error (make-handler (+ 1 2)))) (work))
        (handler-bind ((error (make-handler (- 1 2)))) (work)))
       ((unwind-protect (+ 1 2) (cleanup (+ 3 4)))
        (unwind-protect (- 1 2) (cleanup (+ 3 4))))
       ((the integer (+ 1 2))
        (the integer (- 1 2)))
       ((locally (declare (optimize speed)) (+ 1 2))
        (locally (declare (optimize speed)) (- 1 2)))
       ((eval-when (:execute) (+ 1 2))
        (eval-when (:execute) (- 1 2)))
       ((multiple-value-call #'list (+ 1 2) (values 3 4))
        (multiple-value-call #'list (- 1 2) (values 3 4)))
       ((progv (list 'value) (list (+ 1 2)) (+ 3 4))
        (progv (list 'value) (list (- 1 2)) (+ 3 4))))))

  (it "keeps syntax, declarations, and documentation immutable"
    (let ((forms
            '((let* (((+ 1 2) 3)) value)
              (multiple-value-bind ((+ 1 2)) (values 3) value)
              (flet (((+ 1 2) () "(+ 3 4)" (declare (special (+ 5 6))) value))
                value)
              (handler-bind (((+ 1 2) #'handle)) value)
              (the (+ 1 2) value)
              (eval-when ((+ 1 2)) value))))
      (dolist (form forms)
        (expect (collected-mutation-forms
                 form :operators '(:arithmetic-operator))
                :to-equal
                nil))))

  (it "marks surviving and killed mutants"
    (let* ((results (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore mutation))
                                     (= (eval form) 2))))
           (summary (mutation-summary results)))
      (expect (mapcar #'mutation-result-status results) :to-contain :killed)
      (expect (getf summary :total) :to-be 1)
      (expect (getf summary :killed) :to-be 1)
      (expect (getf summary :survived) :to-be 0)
      (expect (getf summary :score) :to-be 1.0)))

  (it "checks mutation score quality gates for CI"
    (let ((killed (run-mutations '(+ 1 1)
                                 (lambda (form mutation)
                                   (declare (ignore mutation))
                                   (= (eval form) 2))))
          (survived (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore form mutation))
                                     t))))
      (multiple-value-bind (pass-p summary)
          (mutation-score-passes-p killed 1.0)
        (expect pass-p :to-be t)
        (expect (getf summary :score) :to-be 1.0))
      (multiple-value-bind (pass-p summary)
          (mutation-score-passes-p survived 1.0)
        (expect pass-p :to-be nil)
        (expect (getf summary :survived) :to-be 1))
      (expect (assert-mutation-score killed 1.0) :to-satisfy #'listp)
      (handler-case
          (progn
            (assert-mutation-score survived 1.0)
            (expect nil :to-be t))
        (mutation-score-failure (condition)
          (expect (mutation-score-failure-min-score condition) :to-be 1.0)
          (expect (getf (mutation-score-failure-summary condition) :survived)
                  :to-be 1)))))

  (it "uses the score threshold when some mutants survive"
    (let ((results
            (run-mutations '(+ 1 (= 1 1))
                           (lambda (form mutation)
                             (declare (ignore form))
                             (eq (mutation-operator mutation)
                                 :comparison-operator)))))
      (multiple-value-bind (pass-p summary)
          (mutation-score-passes-p results 0.5)
        (expect pass-p :to-be t)
        (expect (getf summary :killed) :to-be 1)
        (expect (getf summary :survived) :to-be 1)
        (expect (getf summary :score) :to-be 0.5))
      (multiple-value-bind (pass-p summary)
          (mutation-score-passes-p results 0.5001)
        (declare (ignore summary))
        (expect pass-p :to-be nil))))

  (it "keeps unexpected harness errors visible"
    (let* ((results (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore form mutation))
                                     (error "harness failed"))))
           (summary (mutation-summary results)))
      (expect (mapcar #'mutation-result-status results) :to-contain :errored)
      (expect (getf summary :errored) :to-be 1)))

  #+sbcl
  (it "records mutation test timeouts as errors on SBCL"
    (let* ((results (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore form mutation))
                                     (loop))
                                   :timeout-ms 10))
           (result (first results)))
      (expect (mutation-result-status result) :to-be :errored)
      (expect (mutation-result-condition result)
              :to-be-instance-of 'cl-weave:test-timeout)
      (expect (cl-weave:test-timeout-ms (mutation-result-condition result))
              :to-be 10)))

  #-sbcl
  (it "rejects mutation timeouts when the implementation cannot enforce them"
    (expect (lambda ()
              (run-mutations '(+ 1 1)
                             (lambda (form mutation)
                               (declare (ignore form mutation))
                               t)
                             :timeout-ms 10))
            :to-throw "Mutation timeouts require SBCL."))

  (it "validates mutation timeout values before execution"
    (handler-case
        (progn
          (run-mutations '(+ 1 1) (lambda (form mutation)
                                    (declare (ignore form mutation))
                                    t)
                         :timeout-ms 0)
          (expect nil :to-be t))
      (error (condition)
        (expect (princ-to-string condition) :to-contain "positive integer"))))

  (it "prints AI-readable mutation reports"
    (let* ((results (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore mutation))
                                     (= (eval form) 2))))
           (sexp-output (with-output-to-string (stream)
                          (report-mutations-sexp results stream)))
           (json-output (with-output-to-string (stream)
                          (report-mutations-json results stream))))
      (expect sexp-output :to-contain ":CL-WEAVE/MUTATIONS")
      (expect sexp-output :to-contain ":SCHEMA-VERSION 1")
      (expect sexp-output :to-contain ":OPERATOR :ARITHMETIC-OPERATOR")
      (expect json-output :to-contain "\"kind\":\"mutations\"")
      (expect json-output :to-contain "\"killed\":1")
      (expect json-output :to-contain "\"operator\":\"ARITHMETIC-OPERATOR\""))))

(describe "mutation public records"
  (it "exposes operator names and descriptions"
    (let ((operator (cl-weave::mutation-operator-named :arithmetic-operator)))
      (expect (typep operator 'cl-weave::mutation-operator) :to-be-truthy)
      (expect (cl-weave:mutation-operator-name operator)
              :to-be
              :arithmetic-operator)
      (expect (cl-weave:mutation-operator-description operator)
              :to-contain
              "arithmetic")))

  (it "rejects unknown or malformed mutation operator designators"
    (expect (lambda () (cl-weave::mutation-operator-named :no-such-operator))
            :to-throw
            "Unknown mutation operator")
    (expect (lambda () (collect-mutations '(+ 1 1) :operators '(:no-such-operator)))
            :to-throw
            "Unknown mutation operator")
    (expect (lambda () (collect-mutations '(+ 1 1) :operators (list 42)))
            :to-throw
            "Invalid mutation operator designator")
    (expect (lambda () (cl-weave:mutation-operator-metadata 42))
            :to-throw
            "Invalid mutation operator designator"))

  (it "rejects malformed mutation operator registrations"
    (expect (lambda ()
              (cl-weave::register-mutation-operator
               "not-a-keyword" (lambda (f p) (declare (ignore f p)))))
            :to-throw)
    (expect (lambda ()
              (cl-weave::register-mutation-operator :ok "not-a-function"))
            :to-throw)
    (expect (lambda ()
              (cl-weave::register-mutation-operator
               :ok (lambda (f p) (declare (ignore f p)))
               :description 42))
            :to-throw))

  (it "exposes mutation result fields"
    (let* ((mutation (first (collect-mutations '(+ 1 1)
                                                :operators '(:arithmetic-operator))))
           (condition (make-condition 'simple-error :format-control "failed"))
           (result (cl-weave::make-mutation-result
                    :mutation mutation
                    :status :errored
                    :condition condition)))
      (expect (typep mutation 'cl-weave:mutation) :to-be-truthy)
      (expect (typep result 'cl-weave:mutation-result) :to-be-truthy)
      (expect (cl-weave:mutation-result-mutation result) :to-be mutation)
      (expect (cl-weave:mutation-result-status result) :to-be :errored)
      (expect (cl-weave:mutation-result-condition result) :to-be condition))))

(describe "mutation walker coverage for uncommon special forms"
  (it "walks dolist count/result forms and body, including the no-result-form path"
    (expect-arithmetic-mutations
     '(((dolist (value (+ 1 2) (+ value 9)) (+ value 3))
        (dolist (value (- 1 2) (+ value 9)) (+ value 3)))
       ((dolist (value (+ 1 2) (+ value 9)) (+ value 3))
        (dolist (value (+ 1 2) (- value 9)) (+ value 3)))
       ((dolist (value (+ 1 2)) (+ value 3))
        (dolist (value (+ 1 2)) (- value 3))))))

  (it "does not walk into a dolist binding with no result form"
    (expect (collected-mutation-forms
             '(dolist (value (list 1 2)) value)
             :operators '(:arithmetic-operator))
            :to-equal
            nil))

  (it "walks dotimes count/result forms and body"
    (expect-arithmetic-mutations
     '(((dotimes (value (+ 1 2) (+ value 9)) (+ value 3))
        (dotimes (value (- 1 2) (+ value 9)) (+ value 3)))
       ((dotimes (value (+ 1 2) (+ value 9)) (+ value 3))
        (dotimes (value (+ 1 2) (- value 9)) (+ value 3))))))

  (it "walks block, return-from, and tagbody go bodies"
    (expect-arithmetic-mutations
     '(((block done (+ 1 2))
        (block done (- 1 2)))
       ((return-from done (+ 1 2))
        (return-from done (- 1 2)))))
    (expect (collected-mutation-forms
             '(tagbody
               start
               (setq value (+ 1 2))
               (go start))
             :operators '(:arithmetic-operator))
            :to-contain
            '(tagbody
              start
              (setq value (- 1 2))
              (go start))))

  (it "walks setq and psetq value forms but not the variable names"
    (expect-arithmetic-mutation
     '(setq value (+ 1 2))
     '(setq value (- 1 2)))
    (expect-arithmetic-mutation
     '(psetq a (+ 1 2) b (+ 3 4))
     '(psetq a (- 1 2) b (+ 3 4)))
    (expect-arithmetic-mutation
     '(psetq a (+ 1 2) b (+ 3 4))
     '(psetq a (+ 1 2) b (- 3 4))))

  (it "skips a defun/defmacro docstring but walks the body beneath it"
    (let ((mutations (collect-mutations
                       '(defun compute (x)
                         "Adds one to X."
                         (+ x 1))
                       :operators '(:arithmetic-operator))))
      (expect (length mutations) :to-be 1)
      (expect (mapcar #'mutation-form mutations)
              :to-contain
              '(defun compute (x)
                "Adds one to X."
                (- x 1))))))
