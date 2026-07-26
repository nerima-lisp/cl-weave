(in-package #:cl-weave)

(defmatcher :to-be (actual expected)
  (eql actual (expected-one expected :to-be)))

(defmatcher :to-equal (actual expected)
  (equal actual (expected-one expected :to-equal)))

(defmatcher :to-equalp (actual expected)
  (equalp actual (expected-one expected :to-equalp)))

(defmatcher :to-be-one-of (actual expected)
  (multiple-value-bind (raw-candidates candidates candidate-count)
      (one-of-candidates expected :to-be-one-of)
    (let ((matched-index (position actual candidates :test #'eql)))
      (values (not (null matched-index))
              (one-of-report actual raw-candidates candidate-count matched-index)
              (one-of-expected-report raw-candidates candidate-count)))))

(defpredicate-matcher :to-be-truthy (actual)
  (not (null actual)))

(defpredicate-matcher :to-be-falsy (actual)
  (null actual))

(defpredicate-matcher :to-be-null (actual)
  (null actual))

(defpredicate-matcher :to-be-defined (actual)
  (not (null actual)))

(defmatcher :to-be-nan (actual expected)
  (expected-none expected :to-be-nan)
  (values (nan-value-p actual)
          (nan-report actual)
          (nan-expected-report)))

(defmatcher :to-satisfy (actual expected)
  (funcall (expected-one expected :to-satisfy) actual))

(defmatcher :to-be-type-of (actual expected)
  (typep actual (expected-one expected :to-be-type-of)))

(defmatcher :to-be-instance-of (actual expected)
  (typep actual (expected-one expected :to-be-instance-of)))

(defmatcher :to-contain (actual expected)
  (contains-value-p actual (expected-one expected :to-contain)))

(defmatcher :to-match (actual expected)
  (match-string-pattern-p actual (expected-one expected :to-match)))

(defmatcher :to-contain-equal (actual expected)
  (let ((value (expected-one expected :to-contain-equal)))
    (values (contains-equal-value-p actual value)
            (contain-equal-report actual value)
            (list :value value :test :equalp))))

(defmatcher :to-match-object (actual expected)
  (let ((subset (expected-one expected :to-match-object)))
    (multiple-value-bind (pass failure)
        (match-object-value-p actual subset)
      (values pass
              (match-object-report actual subset failure)
              (match-object-expected-report subset)))))

(defmatcher :to-have-length (actual expected)
  (let ((length (sequence-length actual)))
    (and length (= length (expected-one expected :to-have-length)))))

(defmatcher :to-have-property (actual expected)
  (multiple-value-bind (path expected-value compare-value-p)
      (normalize-property-expected expected :to-have-property)
    (multiple-value-bind (present-p actual-value)
        (property-path-value actual path)
      (values (and present-p
                   (or (not compare-value-p)
                       (equalp actual-value expected-value)))
              (list :path (property-path-segments path)
                    :present present-p
                    :value actual-value)
              (append (list :path (property-path-segments path))
                      (when compare-value-p
                        (list :value expected-value)))))))

(defmatcher :to-be-close-to (actual expected)
  (multiple-value-bind (target digits)
      (normalize-close-to-expected expected :to-be-close-to)
    (let* ((threshold (close-to-threshold digits))
           (difference (when (and (realp actual)
                                  (not (nan-value-p actual))
                                  (not (nan-value-p target)))
                         (abs (- target actual)))))
      (values (and difference (< difference threshold))
              (close-to-report actual target digits difference threshold)
              (list :value target
                    :num-digits digits
                    :threshold threshold)))))

(defcomparison-matcher :to-be-greater-than >)
(defcomparison-matcher :to-be-greater-than-or-equal >=)
(defcomparison-matcher :to-be-less-than <)
(defcomparison-matcher :to-be-less-than-or-equal <=)

(defmatcher :to-throw (actual expected)
  (let* ((expectation (normalize-throw-expected expected :to-throw))
         (condition (thrown-condition actual :to-throw))
         (actual-report (or (condition-report condition)
                            (no-condition-report))))
    (values (and condition (thrown-condition-matches-p condition expectation))
            actual-report
            expectation)))

(defmatcher :to-run-under-ms (actual expected)
  (let* ((max-ms (non-negative-real-expected expected :to-run-under-ms "millisecond threshold"))
         (measurement (measure-thunk actual :to-run-under-ms)))
    (values (< (getf measurement :elapsed-ms) max-ms)
            measurement
            (list :max-ms max-ms))))

(defmatcher :to-allocate-under (actual expected)
  "Passes when ACTUAL thunk allocates fewer bytes than EXPECTED."
  (let* ((max-bytes (non-negative-real-expected expected :to-allocate-under "byte threshold"))
         (measurement (measure-thunk actual :to-allocate-under))
         (bytes (measured-bytes-consed measurement :to-allocate-under)))
    (values (< bytes max-bytes)
            measurement
            (list :max-bytes max-bytes))))

(defmatcher :to-have-slot (actual expected)
  "Passes when ACTUAL names a class that defines the EXPECTED slot."
  (let* ((slot-name (expected-one expected :to-have-slot))
         (class (class-designator-class actual :to-have-slot))
         (slots (class-slot-names class :to-have-slot)))
    (values (not (null (member slot-name slots :test #'eq)))
            (list :class (class-name class)
                  :slots slots)
            (list :slot slot-name))))

(defmatcher :to-have-method-specialized-on (actual expected)
  (:description "Passes when ACTUAL names a generic function with a method "
                "specialized on the EXPECTED specializers.")
  (let* ((expected-specializers (expected-one expected :to-have-method-specialized-on))
         (generic-function
           (generic-function-designator-function actual :to-have-method-specialized-on))
         (methods
           (generic-function-specializer-lists generic-function
                                               :to-have-method-specialized-on)))
    (values (not (null (member expected-specializers methods :test #'equal)))
            (list :methods methods)
            (list :specializers expected-specializers))))

(defmatcher :to-expand-to (actual expected)
  (let ((expanded-form (expand-once actual))
        (expected-form (expected-one expected :to-expand-to)))
    (values (equal expanded-form expected-form)
            expanded-form
            expected-form)))

(defmatcher :to-match-inline-snapshot (actual expected)
  (string= (snapshot-string actual)
           (expected-one expected :to-match-inline-snapshot)))

(defmatcher :to-match-snapshot (actual expected)
  (snapshot-match-or-update-p actual expected))

(defmatcher :to-match-snapshot-sequence (actual expected)
  "Matches a list or vector of states against external snapshots named prefix[0], prefix[1], ..."
  (snapshot-sequence-match-or-update-p actual expected))

(defpredicate-matcher :to-have-been-called (actual)
  (let ((report (mock-report actual)))
    (values (plusp (getf report :call-count))
            report
            '(:call-count (:min 1)))))

(defmatcher :to-have-been-called-times (actual expected)
  (let* ((times (expected-one expected :to-have-been-called-times))
         (report (mock-report actual)))
    (values (= (getf report :call-count) times)
            report
            (list :call-count times))))

(defmatcher :to-have-been-called-with (actual expected)
  (let ((report (mock-report actual)))
    (values (mock-called-with-p actual expected report)
            report
            (list :arguments expected))))

(defmatcher :to-have-been-last-called-with (actual expected)
  (let ((report (mock-report actual)))
    (multiple-value-bind (arguments present-p)
        (last-list-entry (getf report :calls))
      (values (and present-p (equal arguments expected))
              report
              (list :last-arguments expected)))))

(defmatcher :to-have-been-nth-called-with (actual expected)
  (multiple-value-bind (index expected-arguments)
      (expected-index-and-tail expected :to-have-been-nth-called-with)
    (let ((report (mock-report actual)))
      (multiple-value-bind (arguments present-p)
          (nth-list-entry (getf report :calls) index)
        (values (and present-p (equal arguments expected-arguments))
                report
                (list :index index :arguments expected-arguments))))))

(defpredicate-matcher :to-have-returned (actual)
  (let ((report (mock-report actual)))
    (values (plusp (getf report :return-count))
            report
            '(:return-count (:min 1)))))

(defmatcher :to-have-returned-times (actual expected)
  (let* ((times (expected-one expected :to-have-returned-times))
         (report (mock-report actual)))
    (values (= (getf report :return-count) times)
            report
            (list :return-count times))))

(defmatcher :to-have-returned-with (actual expected)
  (let ((report (mock-report actual)))
    (values (mock-returned-with-p actual expected report)
            report
            (list :values expected))))

(defmatcher :to-have-last-returned-with (actual expected)
  (let* ((report (mock-report actual))
         (returns (return-results (getf report :results))))
    (multiple-value-bind (result present-p) (last-list-entry returns)
      (values (and present-p (equal (getf result :values) expected))
              report
              (list :last-values expected)))))

(defmatcher :to-have-nth-returned-with (actual expected)
  (multiple-value-bind (index expected-values)
      (expected-index-and-tail expected :to-have-nth-returned-with)
    (let* ((report (mock-report actual))
           (returns (return-results (getf report :results))))
      (multiple-value-bind (result present-p)
          (nth-list-entry returns index)
        (values (and present-p (equal (getf result :values) expected-values))
                report
                (list :index index :values expected-values))))))

(defpredicate-matcher :to-have-thrown (actual)
  (let ((report (mock-report actual)))
    (values (plusp (getf report :throw-count))
            report
            '(:throw-count (:min 1)))))

