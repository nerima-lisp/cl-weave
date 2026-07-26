(in-package #:cl-weave)

(defun expected-one (expected matcher)
  (unless (= (length expected) 1)
    (error "Matcher ~S expects one expected value, got ~D." matcher (length expected)))
  (first expected))

(defun expected-none (expected matcher)
  (unless (null expected)
    (error "Matcher ~S expects no expected values, got ~D." matcher (length expected))))

(progn
  (defconstant +maximum-one-of-candidate-count+ 100000)

  (defun ensure-one-of-candidate-count (count matcher)
    (unless (<= count +maximum-one-of-candidate-count+)
      (error "Matcher ~S accepts at most ~D candidates, got ~D."
             matcher
             +maximum-one-of-candidate-count+
             count))
    count)

  (defun one-of-candidates (expected matcher)
    (let ((candidates (expected-one expected matcher)))
      (cond
        ((and (listp candidates)
              (finite-proper-list-p candidates))
         (let ((count (ensure-one-of-candidate-count
                       (length candidates)
                       matcher)))
           (values candidates candidates count)))
        ((and (vectorp candidates)
              (not (stringp candidates)))
         (let ((count (ensure-one-of-candidate-count
                       (length candidates)
                       matcher)))
           (values candidates (coerce candidates 'list) count)))
        ((hash-table-p candidates)
         (let ((count (ensure-one-of-candidate-count
                       (hash-table-count candidates)
                       matcher)))
           (values candidates
                   (loop for value being the hash-values of candidates
                         collect value)
                   count)))
        (t
         (error "Matcher ~S expects a finite proper list, non-string vector, ~
                 or hash table of candidates."
                matcher))))))

(defun one-of-report (actual raw-candidates candidate-count matched-index)
  (list :value actual
        :candidates raw-candidates
        :test 'eql
        :candidate-count candidate-count
        :matched-index matched-index))

(defun one-of-expected-report (raw-candidates candidate-count)
  (list :candidates raw-candidates
        :test 'eql
        :candidate-count candidate-count))

(defun nan-value-p (value)
  (and (floatp value)
       #+sbcl
       (sb-ext:float-nan-p value)
       #-sbcl
       (not (= value value))))

(defun nan-report (actual)
  (list :value actual
        :type (type-of actual)
        :float (floatp actual)
        :nan (nan-value-p actual)))

(defun nan-expected-report ()
  '(:predicate :nan :test :float-nan-p))

(defun non-negative-real-expected (expected matcher label)
  (let ((value (expected-one expected matcher)))
    (unless (and (realp value) (not (minusp value)))
      (error "Matcher ~S expects a non-negative real ~A, got ~S."
             matcher label value))
    value))

(defun real-expected (expected matcher label)
  (let ((value (expected-one expected matcher)))
    (unless (realp value)
      (error "Matcher ~S expects a real ~A, got ~S." matcher label value))
    value))

(defun comparison-report (actual expected matcher operator)
  (list :value actual
        :expected-value expected
        :matcher matcher
        :operator operator
        :actual-real (realp actual)
        :expected-real (realp expected)))

(defun comparison-expected-report (expected matcher operator)
  (list :value expected
        :matcher matcher
        :operator operator))

(defmacro defcomparison-matcher (name operator)
  `(defmatcher ,name (actual expected)
     (let ((target (real-expected expected ,name "comparison target")))
       ;; NaN is realp but an ordered comparison against it signals a
       ;; floating-point trap under SBCL; treat it as a clean non-match.
       (values (and (realp actual)
                    (not (nan-value-p actual))
                    (not (nan-value-p target))
                    (,operator actual target))
               (comparison-report actual target ,name ',operator)
               (comparison-expected-report target ,name ',operator)))))

(defmacro defpredicate-matcher (name (actual) &body body)
  "Define a matcher that accepts ACTUAL and no expected values."
  `(defmatcher ,name (,actual expected)
     (expected-none expected ',name)
     ,@body))

(defconstant +maximum-close-to-precision+ 1000)

  (defun ensure-close-to-precision (digits matcher)
    (unless (and (integerp digits)
                 (<= 0 digits +maximum-close-to-precision+))
      (error "Matcher ~S expects an integer digit count between 0 and ~D."
             matcher +maximum-close-to-precision+))
    digits)

  (defun normalize-close-to-expected (expected matcher)
  (unless (member (length expected) (quote (1 2)))
    (error "Matcher ~S expects one or two expected values, got ~D."
           matcher (length expected)))
  (destructuring-bind (target &optional (digits 2)) expected
    (unless (realp target)
      (error "Matcher ~S expects a real target, got ~S." matcher target))
    (values target (ensure-close-to-precision digits matcher))))

(defun close-to-threshold (digits)
  (let ((precision (ensure-close-to-precision digits :to-be-close-to)))
    (/ (expt 10 (- precision)) 2)))

(defun close-to-report (actual target digits difference threshold)
  (list :value actual
        :expected-value target
        :num-digits digits
        :difference difference
        :threshold threshold))

(defun thrown-condition (thunk matcher)
  (unless (functionp thunk)
    (error "Matcher ~S expects a function thunk, got ~S." matcher thunk))
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      condition)))

(defun condition-class-designator-p (value)
  (or (typep value 'class)
      (and (symbolp value) (find-class value nil))))

(defun condition-class-designator-class (value)
  (if (typep value 'class)
      value
      (find-class value)))

(defun condition-report (condition)
  (when condition
    (list :threw t
          :condition-type (class-name (class-of condition))
          :message (princ-to-string condition))))

(defun no-condition-report ()
  '(:threw nil :condition-type nil :message nil))

(defun normalize-throw-expected (expected matcher)
  (cond
    ((null expected)
     (list :matcher :any))
    ((/= (length expected) 1)
     (error "Matcher ~S expects zero or one expected value, got ~D."
            matcher (length expected)))
    (t
     (let ((value (first expected)))
       (cond
         ((stringp value)
          (list :matcher :message-substring :value value))
         ((condition-class-designator-p value)
          (list :matcher :condition-type
                :value (class-name (condition-class-designator-class value))))
         ((functionp value)
          (list :matcher :predicate :value value))
         (t
          (error "Matcher ~S expected NIL, a condition class designator, ~
                  string, or predicate, got ~S."
                 matcher value)))))))

(defun thrown-condition-matches-p (condition expectation)
  (case (getf expectation :matcher)
    (:any t)
    (:message-substring
     (not (null (search (getf expectation :value)
                        (princ-to-string condition)))))
    (:condition-type
     (typep condition (getf expectation :value)))
    (:predicate
     (not (null (funcall (getf expectation :value) condition))))
    (otherwise nil)))

(defun current-bytes-consed ()
  #+sbcl
  (sb-ext:get-bytes-consed)
  #-sbcl
  nil)

(defun measure-thunk (thunk matcher)
  (unless (functionp thunk)
    (error "Matcher ~S expects a function thunk, got ~S." matcher thunk))
  (let* ((start-time (get-internal-real-time))
         (start-bytes (current-bytes-consed))
         (values (multiple-value-list (funcall thunk)))
         (end-time (get-internal-real-time))
         (end-bytes (current-bytes-consed))
         (elapsed-seconds (/ (- end-time start-time)
                             internal-time-units-per-second))
         (elapsed-ms (* elapsed-seconds 1000)))
    (list :elapsed-seconds (coerce elapsed-seconds 'double-float)
          :elapsed-ms (coerce elapsed-ms 'double-float)
          :bytes-consed (when (and start-bytes end-bytes)
                          (- end-bytes start-bytes))
          :values values)))

(defun measured-bytes-consed (measurement matcher)
  (let ((bytes (getf measurement :bytes-consed)))
    (unless bytes
      (error "Matcher ~S cannot read bytes consed on this Common Lisp implementation."
             matcher))
    bytes))

(defun mop-required (matcher)
  (error "Matcher ~S requires SBCL MOP support." matcher))

(defun class-designator-class (designator matcher)
  (or (typecase designator
        (class designator)
        (symbol (find-class designator nil))
        (t (class-of designator)))
      (error "Matcher ~S cannot resolve class designator ~S." matcher designator)))

(defun class-slot-names (class matcher)
  (declare (ignorable matcher))
  #+sbcl
  (progn
    (sb-mop:finalize-inheritance class)
    (mapcar #'sb-mop:slot-definition-name
            (sb-mop:class-slots class)))
  #-sbcl
  (mop-required matcher))

(defun generic-function-designator-function (designator matcher)
  (let ((function (typecase designator
                    (symbol (when (fboundp designator)
                              (fdefinition designator)))
                    (function designator)
                    (t nil))))
    (unless (typep function 'generic-function)
      (error "Matcher ~S expects a generic function designator, got ~S."
             matcher designator))
    function))

(defun specializer-report-name (specializer)
  #+sbcl
  (cond
    ((typep specializer 'class)
     (class-name specializer))
    ((typep specializer 'sb-mop:eql-specializer)
     (list 'eql (sb-mop:eql-specializer-object specializer)))
    (t specializer))
  #-sbcl
  specializer)

(defun generic-function-specializer-lists (generic-function matcher)
  (declare (ignorable matcher))
  #+sbcl
  (progn
    (mapcar (lambda (method)
              (mapcar #'specializer-report-name
                      (sb-mop:method-specializers method)))
            (sb-mop:generic-function-methods generic-function)))
  #-sbcl
  (mop-required matcher))

(defun matcher-result-values (matcher actual expected)
  (multiple-value-call
      (lambda (default-actual default-expected
               &optional pass-p
                         (actual-report default-actual)
                         (expected-report default-expected)
               &rest ignored)
        (declare (dynamic-extent ignored) (ignore ignored))
        (values pass-p actual-report expected-report))
    (values actual expected)
    (funcall (matcher-function matcher) actual expected)))

(defun call-with-matcher-result/k (matcher actual expected continue)
  (multiple-value-call continue
    (matcher-result-values matcher actual expected)))

(defun expand-once (form)
  (macroexpand-1 form))
