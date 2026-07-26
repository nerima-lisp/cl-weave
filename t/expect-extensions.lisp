(in-package #:cl-weave/test)

(defun slow-measured-operation ()
  (sleep 0.001))

(defun allocating-measured-operation ()
  (list :allocated))

(defparameter *measurement-fields*
  '(:elapsed-ms :elapsed-seconds :bytes-consed :values))

(defun expect-measurement-fields (actual)
  (dolist (field *measurement-fields*)
    (expect actual :to-contain field)))

(defun expect-measurement-failure (condition matcher expected)
  (with-assertion-detail (detail condition actual)
    (expect (cl-weave::assertion-detail-matcher detail) :to-be matcher)
    (expect-measurement-fields actual)
    (expect (cl-weave::assertion-detail-expected detail) :to-equal expected)))

(defun expect-performance-measurement-failure ()
  (handler-case
      (progn
        (expect #'slow-measured-operation :to-run-under-ms 0)
        (expect nil :to-be-truthy))
    (cl-weave:assertion-failure (condition)
      (expect-measurement-failure condition :to-run-under-ms '(:max-ms 0)))))

(defun expect-allocation-measurement-failure ()
  (handler-case
      (progn
        (expect #'allocating-measured-operation :to-allocate-under 0)
        (expect nil :to-be-truthy))
    (cl-weave:assertion-failure (condition)
      (expect-measurement-failure condition
                                  :to-allocate-under
                                  '(:max-bytes 0)))))

(defun expect-public-custom-matcher-failure ()
  (expect 4 :to-be-even)
  (handler-case
      (progn
        (expect 5 :to-be-even)
        (expect nil :to-be-truthy))
    (cl-weave:assertion-failure (condition)
      (with-assertion-detail (detail condition)
        (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-even)
        (expect (cl-weave::assertion-detail-actual detail)
                :to-equal '(:value 5 :parity :odd))
        (expect (cl-weave::assertion-detail-expected detail)
                :to-equal '(:parity :even))))))

(defun expect-extended-custom-matcher-failure ()
  (expect 7 :to-be-odd)
  (handler-case
      (progn
        (expect 8 :to-be-odd)
        (expect nil :to-be-truthy))
    (cl-weave:assertion-failure (condition)
      (with-assertion-detail (detail condition)
        (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-odd)
        (expect (cl-weave::assertion-detail-actual detail)
                :to-equal '(:value 8 :parity :even))
        (expect (cl-weave::assertion-detail-expected detail)
                :to-equal '(:parity :odd))))))

(defun expect-data-driven-custom-matcher-failure ()
  (expect 5 :to-be-between 1 10)
  (handler-case
      (progn
        (expect 11 :to-be-between 1 10)
        (expect nil :to-be-truthy))
    (cl-weave:assertion-failure (condition)
      (with-assertion-detail (detail condition)
        (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-between)
        (expect (cl-weave::assertion-detail-actual detail)
                :to-equal '(:value 11 :range (1 10)))
        (expect (cl-weave::assertion-detail-expected detail)
                :to-equal '(:range (1 10)))))))

(defun expect-stable-matcher-metadata ()
  (let* ((metadata (cl-weave:list-matchers))
         (names (mapcar (lambda (entry) (getf entry :name)) metadata))
         (sorted-names (sort (copy-list names) #'string< :key #'symbol-name))
         (even (cl-weave:matcher-metadata :to-be-even))
         (odd (cl-weave:matcher-metadata :to-be-odd))
         (between (cl-weave:matcher-metadata :to-be-between))
         (slot (cl-weave:matcher-metadata :to-have-slot))
         (method (cl-weave:matcher-metadata :to-have-method-specialized-on)))
    (expect names :to-equal sorted-names)
    (expect names :to-contain :to-be)
    (expect even :to-equal
            '(:name :to-be-even
              :description "Passes when ACTUAL is an even integer."))
    (expect odd :to-equal
            '(:name :to-be-odd
              :description "Passes when ACTUAL is an odd integer."))
    (expect between :to-equal
            '(:name :to-be-between
              :description "Passes when ACTUAL is within the inclusive numeric range."))
    (expect slot :to-equal
            '(:name :to-have-slot
              :description "Passes when ACTUAL names a class that defines the EXPECTED slot."))
    (expect method :to-equal
            '(:name :to-have-method-specialized-on
              :description "Passes when ACTUAL names a generic function with a method specialized on the EXPECTED specializers."))))

(defun expect-smart-assertion-failure ()
  (handler-case
      (progn
        (expect (= (+ 1 1) 3))
        (expect nil :to-be-truthy))
    (cl-weave:assertion-failure (condition)
      (with-assertion-detail (detail condition actual)
        (expect (cl-weave::assertion-detail-matcher detail) :to-be '=)
        (expect actual :to-contain '(:form (+ 1 1) :value 2))
        (expect actual :to-contain '(:form 3 :value 3))
        (expect (cl-weave::assertion-detail-expected detail)
                :to-equal '(= (+ 1 1) 3))))))

(describe "expect extensions and measurements"
  (it "supports public custom matchers with structured failure data"
    (expect-public-custom-matcher-failure)))

(describe "expect-extend custom matchers"
    (it "supports Vitest-style expect-extend custom matchers"
      (expect-extended-custom-matcher-failure)))

  (describe "matcher result values"
    (it "preserves defaults and reports across matcher value arities"
      (flet ((normalized-values (producer)
               (multiple-value-list
                (cl-weave::matcher-result-values
                 (cl-weave::make-matcher
                  :function
                  (lambda (actual expected)
                    (declare (ignore actual expected))
                    (funcall producer)))
                 :original-actual
                 :original-expected))))
        (expect (normalized-values (lambda () (values)))
                :to-equal
                (list nil :original-actual :original-expected))
        (expect (normalized-values (lambda () (values nil)))
                :to-equal
                (list nil :original-actual :original-expected))
        (expect (normalized-values (lambda () (values :pass nil)))
                :to-equal
                (list :pass nil :original-expected))
        (expect (normalized-values
                 (lambda ()
                   (values :pass :reported-actual :reported-expected :ignored)))
                :to-equal
                (list :pass :reported-actual :reported-expected)))))

(describe "data-driven custom matchers"
  (it "supports data-driven extend-expect custom matchers"
    (expect-data-driven-custom-matcher-failure)))

(describe "matcher metadata and smart assertions"
  (it "exposes stable matcher metadata for AI tooling"
    (expect-stable-matcher-metadata)))

(describe "smart assertions"
  (it "signals smart assertion failures with operand values"
    (expect-smart-assertion-failure)))

(describe "expect performance and allocation measurements"
  (it "reports performance measurements in assertion failures"
    (expect-performance-measurement-failure))

  (it "reports allocation measurements in assertion failures"
    (expect-allocation-measurement-failure)))

(progn
  (describe "matcher argument validation"
    (it "rejects malformed matcher arguments with stable errors"
      (dolist (bad-expectation
               (list (lambda () (expect 1 :to-be-close-to))
                     (lambda () (expect 1 :to-be-close-to 2 :digits))
                     (lambda () (expect 1 :to-be-close-to 2 -3))
                     (lambda () (expect 1 :to-be-one-of))
                     (lambda () (expect 1 :to-be-instance-of (find-symbol "NO-SUCH-CLASS" "KEYWORD")))
                     (lambda () (expect (lambda () t) :to-throw 42))
                     (lambda () (expect 42 :to-run-under-ms 5))
                     (lambda () (expect (lambda () t) :to-run-under-ms "fast"))
                     (lambda () (expect (lambda () t) :to-run-under-ms -1))
                     (lambda () (expect (lambda () t) :to-allocate-under "few"))
                     (lambda () (expect 42 :to-have-method-specialized-on 'name))
                     (lambda () (expect 42 :to-have-slot))
                     (lambda () (expect :no-such-class-designator :to-have-slot 'value))))
        (expect bad-expectation :to-throw)))

    (it "rejects malformed custom matcher definitions with stable errors"
      (dolist (bad-definition
               (list (lambda () (eval '(cl-weave:defmatcher "not-a-symbol" (a e) t)))
                     (lambda () (eval '(cl-weave:defmatcher :ok (1 e) t)))
                     (lambda () (eval '(cl-weave:defmatcher :ok (a 2) t)))
                     (lambda () (eval '(cl-weave:expect-extend ("not-a-symbol" (a e) t))))
                     (lambda () (eval '(cl-weave:expect-extend (:ok (1 e) t))))
                     (lambda () (eval '(cl-weave:expect-extend (:ok (a 2) t))))
                     (lambda ()
                       (cl-weave:extend-expect
                        (list (list "not-a-symbol" (lambda (a e) t)))))
                     (lambda ()
                       (cl-weave:extend-expect
                        (list (list :ok "not-a-function"))))
                     (lambda ()
                       (cl-weave:extend-expect
                        (list (list :ok (lambda (a e) t) :bad-key "x"))))))
        (expect bad-definition :to-throw)))

    (it "bounds close-to precision before exact arithmetic"
      (expect 1 :to-be-close-to 1 cl-weave::+maximum-close-to-precision+)
      (dolist (digits (list (1+ cl-weave::+maximum-close-to-precision+)
                            (expt 10 10000)))
        (expect (lambda ()
                  (expect 1 :to-be-close-to 1 digits))
                :to-throw
                "integer digit count between")))

    (it "rejects non-finite and unsupported one-of candidate collections"
      (let ((cycle (list :candidate)))
        (setf (cdr cycle) cycle)
        #+sbcl
        (sb-ext:with-timeout 1
          (expect (lambda ()
                    (expect :candidate :to-be-one-of cycle))
                  :to-throw
                  "finite proper list"))
        #-sbcl
        (expect (lambda ()
                  (expect :candidate :to-be-one-of cycle))
                :to-throw
                "finite proper list"))
      (dolist (candidates (list (cons :candidate :tail)
                                42))
        (expect (lambda ()
                  (expect :candidate :to-be-one-of candidates))
                :to-throw
                "finite proper list")))

    (it "bounds one-of candidate collections before normalization"
      (let* ((limit cl-weave::+maximum-one-of-candidate-count+)
             (oversize (1+ limit))
             (table (make-hash-table :test #'eql :size oversize)))
        (dotimes (index oversize)
          (setf (gethash index table) index))
        (dolist (candidates
                 (list (make-list oversize :initial-element :candidate)
                       (make-array oversize :initial-element :candidate)
                       table))
          (expect (lambda ()
                    (expect :missing :to-be-one-of candidates))
                  :to-throw
                  "at most")))))

  (describe "logic rule term instantiation"
    (it "handles rule terms nested to depth 50000"
      (let ((rule-term '?value)
            (query-term :resolved))
        (loop repeat 50000 do (setf rule-term (cons :node rule-term) query-term (cons :node query-term)))
        (expect (logic-query
                 (list (list ':- (cons :deep rule-term)))
                 (list (cons :deep query-term)))
                :to-equal
                '(nil))))

    (it "rejects cyclic rule terms before instantiation"
      (let* ((cycle (list '?value))
             (program (list (list ':- (cons :cyclic cycle)))))
        (setf (cdr cycle) cycle)
        (expect (lambda ()
                  (logic-query program '((:cyclic :resolved))))
                :to-throw
                "cyclic logic value")))

    (it "rejects cyclic top-level programs before normalization"
      (let ((program (list (list :cyclic :resolved))))
        (setf (cdr program) program)
        (expect (lambda ()
                  (logic-query program '((:cyclic :resolved)) :max-steps 1))
                :to-throw
                "cyclic logic value")))))
