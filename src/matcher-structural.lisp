(in-package #:cl-weave)

(defun contains-value-p (container value)
  (typecase container
    (string (and (stringp value) (not (null (search value container)))))
    (list (not (null (member value container :test #'equal))))
    (vector (not (null (find value container :test #'equal))))
    (t nil)))

(defun contains-equal-value-p (container value)
  (typecase container
    (hash-table
     (loop for candidate being the hash-values of container
           thereis (equalp candidate value)))
    (sequence
     (not (null (position value container :test #'equalp))))
    (t nil)))

(defun contain-equal-report (container value)
  (list :container container
        :value value
        :test :equalp))

(defun match-pattern-mode (pattern)
  (cond
    ((stringp pattern) :substring)
    ((functionp pattern) :predicate)
    ((and (symbolp pattern) (fboundp pattern)) :predicate)
    (t :invalid)))

(defun match-pattern-report (actual pattern mode reason &optional condition)
  (let ((report (list :value actual
                      :pattern pattern
                      :mode mode
                      :reason reason)))
    (if condition
        (append report (list :error (princ-to-string condition)))
        report)))

(defun match-pattern-expected-report (pattern mode)
  (list :pattern pattern
        :test (ecase mode
                (:substring :substring)
                (:predicate :predicate)
                (:invalid :valid-pattern))))

(defun match-string-pattern-p (actual pattern)
  (let ((mode (match-pattern-mode pattern)))
    (cond
      ((not (stringp actual))
       (values nil
               (match-pattern-report actual pattern mode :not-a-string)
               (match-pattern-expected-report pattern mode)))
      ((eq mode :substring)
       (let ((pass (not (null (search pattern actual)))))
         (values pass
                 (match-pattern-report actual pattern mode (if pass :matched :no-match))
                 (match-pattern-expected-report pattern mode))))
      ((eq mode :predicate)
       (handler-case
           (let ((pass (not (null (funcall pattern actual)))))
             (values pass
                     (match-pattern-report actual pattern mode (if pass :matched :predicate-false))
                     (match-pattern-expected-report pattern mode)))
         (condition (condition)
           (values nil
                   (match-pattern-report actual pattern mode :predicate-error condition)
                   (match-pattern-expected-report pattern mode)))))
      (t
       (values nil
               (match-pattern-report actual pattern mode :invalid-pattern)
               (match-pattern-expected-report pattern mode))))))

(defun sequence-length (value)
  (when (typep value 'sequence)
    (length value)))

(defun property-path-segments (path)
  (cond
    ((vectorp path) (coerce path 'list))
    ((listp path) path)
    (t (list path))))

(defun sequence-index-value (sequence index)
  (if (and (integerp index)
           (not (minusp index))
           (< index (length sequence)))
      (values (elt sequence index) t)
      (values nil nil)))

(defun alist-value (entries key)
  (let ((entry (assoc key entries :test #'equal)))
    (if entry
        (values (cdr entry) t)
        (values nil nil))))

(defun plist-value (plist key)
  (loop for tail = plist then (cddr tail)
        while (and (consp tail) (consp (cdr tail)))
        for plist-key = (first tail)
        for value = (second tail)
        when (eql plist-key key)
          return (values value t)
        finally (return (values nil nil))))

(defun object-slot-value (object slot-name)
  (if (symbolp slot-name)
      (handler-case
          (if (slot-exists-p object slot-name)
              (if (slot-boundp object slot-name)
                  (values (slot-value object slot-name) t)
                  (values nil t))
              (values nil nil))
        (error ()
          (values nil nil)))
      (values nil nil)))

(defun alist-object-p (value)
  (and (consp value)
       (listp value)
       (every #'consp value)))

(defun plist-object-p (value)
  (and (consp value)
       (listp value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             always (symbolp (first tail)))))

(defun object-subset-designator-p (value)
  (or (hash-table-p value)
      (alist-object-p value)
      (plist-object-p value)))

(defun object-entry-list (value)
  (cond
    ((hash-table-p value)
     (loop for key being the hash-keys of value using (hash-value entry-value)
           collect (list key entry-value)))
    ((alist-object-p value)
     (loop for (key . entry-value) in value
           collect (list key entry-value)))
    ((plist-object-p value)
     (loop for (key entry-value) on value by #'cddr
           collect (list key entry-value)))
    (t nil)))

(defun object-property-value (object key)
  (typecase object
    (hash-table (gethash key object))
    (cons
     (cond
       ((alist-object-p object) (alist-value object key))
       ((plist-object-p object) (plist-value object key))
       (t (values nil nil))))
    (t
     (object-slot-value object key))))

(defun match-object-failure (path reason actual-value expected-value)
  (list :path path
        :reason reason
        :actual-value actual-value
        :expected-value expected-value
        :test :equalp))

(declaim (ftype function match-object-value/k match-object-sequence/k))

(defun match-recursion-succeeded ()
  "The SUCCEED continuation for a recursive MATCH-OBJECT-VALUE/K call:
report the nested match back to the caller as (values matched failure)."
  (values t nil))

(defun match-recursion-failed (failure)
  "The FAIL continuation for a recursive MATCH-OBJECT-VALUE/K call: report
FAILURE back to the caller as (values matched failure)."
  (values nil failure))

(defun match-object-entries/k (actual entries path succeed fail)
  (dolist (entry entries (funcall succeed))
    (destructuring-bind (key expected-value) entry
      (let ((property-path (append path (list key))))
        (multiple-value-bind (actual-value present-p)
            (object-property-value actual key)
          (unless present-p
            (return (funcall fail
                             (match-object-failure property-path
                                                   :missing-property
                                                   nil
                                                   expected-value))))
          (multiple-value-bind (matched failure)
              (match-object-value/k actual-value
                                    expected-value
                                    property-path
                                    #'match-recursion-succeeded
                                    #'match-recursion-failed)
            (unless matched
              (return (funcall fail failure)))))))))

(defun match-object-value/k (actual expected path succeed fail)
  (cond
    ((object-subset-designator-p expected)
     (match-object-entries/k actual
                             (object-entry-list expected)
                             path
                             succeed
                             fail))
    ((equalp actual expected)
     (funcall succeed))
    ((and (vectorp expected) (not (stringp expected)))
     (match-object-sequence/k actual expected path 0 succeed fail))
    (t
     (funcall fail
              (match-object-failure path :value-mismatch actual expected)))))

(defun match-object-sequence/k (actual expected path index succeed fail)
  (cond
    ((not (typep actual 'sequence))
     (funcall fail
              (match-object-failure path :type-mismatch actual expected)))
    ((/= (length actual) (length expected))
     (funcall fail
              (match-object-failure path :length-mismatch
                                    (length actual)
                                    (length expected))))
    (t
     (loop for position from index below (length expected)
           do (multiple-value-bind (matched failure)
                  (match-object-value/k
                   (elt actual position)
                   (elt expected position)
                   (append path (list position))
                   #'match-recursion-succeeded
                   #'match-recursion-failed)
                (unless matched
                  (return (funcall fail failure))))
           finally (return (funcall succeed))))))

(defun match-object-value-p (actual expected &optional (path nil))
  (match-object-value/k actual
                        expected
                        path
                        (lambda () (values t nil))
                        (lambda (failure) (values nil failure))))

(defun match-object-report (actual subset failure)
  (list :value actual
        :subset subset
        :failure failure))

(defun match-object-expected-report (subset)
  (list :subset subset
        :test :partial-equalp))

(defun property-segment-value (value segment)
  (typecase value
    (hash-table (gethash segment value))
    (cons
     (cond
       ((integerp segment) (sequence-index-value value segment))
       ((consp (first value)) (alist-value value segment))
       (t (plist-value value segment))))
    (vector
     (sequence-index-value value segment))
    (t
     (object-slot-value value segment))))

(defun property-path-value (value path)
  (let ((current value))
    (dolist (segment (property-path-segments path) (values t current))
      (multiple-value-bind (next present-p)
          (property-segment-value current segment)
        (unless present-p
          (return (values nil nil)))
        (setf current next)))))

(defun normalize-property-expected (expected matcher)
  (unless (<= 1 (length expected) 2)
    (error "Matcher ~S expects a property path and optional expected value, got ~D values."
           matcher
           (length expected)))
  (values (first expected)
          (second expected)
          (= (length expected) 2)))
