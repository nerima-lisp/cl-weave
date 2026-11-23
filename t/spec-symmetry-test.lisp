(in-package #:cl-weave/spec-test)

(defun symmetry-test-spec (constants symmetry)
  (make-spec :name 'symmetry-test :constants constants :variables '(x y)
             :init (lambda () '((x 0 y 0))) :symmetry symmetry))

(describe "spec symmetry"
  (it "returns no canonicalizer without symmetric constants"
    (expect (spec-state-canonicalizer (symmetry-test-spec nil nil)) :to-be nil))

  (it "normalizes two elements idempotently and distinguishes orbits"
    (let* ((spec (symmetry-test-spec (list 'procs (spec-set :a :b)) '(procs)))
           (canonicalize (spec-state-canonicalizer spec))
           (state (list 'x :b 'y :a))
           (result (funcall canonicalize state)))
      (expect result :to-equal (list 'x :a 'y :b))
      (expect (funcall canonicalize result) :to-equal result)
      (expect (funcall canonicalize (list 'x :a 'y :b)) :to-equal result)
      (expect (equal (funcall canonicalize (list 'x :a 'y :a)) result) :to-be nil)))

  (it "preserves singleton empty and absent symmetric values"
    (dolist (domain (list (list :a) nil))
      (let ((canonicalize (spec-state-canonicalizer
                           (symmetry-test-spec (list 'procs domain) '(procs)))))
        (expect (funcall canonicalize (list 'x :a 'y 42))
                :to-equal (list 'x :a 'y 42))))
    (let ((canonicalize (spec-state-canonicalizer
                         (symmetry-test-spec (list 'procs '(:a :b)) '(procs)))))
      (expect (funcall canonicalize (list 'x 1 'y 2)) :to-equal (list 'x 1 'y 2))))

  (it "normalizes nested sets functions and record values"
    (let* ((spec (symmetry-test-spec (list 'procs '(:a :b)) '(procs)))
           (canonicalize (spec-state-canonicalizer spec))
           (state (list 'x :b 'y (spec-sequence
                                   (spec-set :b)
                                   (make-spec-function (list (cons :b :a)))
                                   (make-spec-record :b :b))))
           (expected (list 'x :a 'y (spec-sequence
                                      (spec-set :a)
                                      (make-spec-function (list (cons :a :b)))
                                      (make-spec-record :b :a)))))
      (expect (funcall canonicalize state) :to-equal expected)
      (expect (funcall canonicalize expected) :to-equal expected)))

  (it "normalizes five element permutations"
    (let ((canonicalize (spec-state-canonicalizer
                         (symmetry-test-spec (list 'procs '(:a :b :c :d :e)) '(procs)))))
      (expect (funcall canonicalize (list 'x :e 'y :d))
              :to-equal (list 'x :a 'y :b))))

  (it "handles overlapping and disjoint symmetry groups"
    (let ((canonicalize (spec-state-canonicalizer
                         (symmetry-test-spec (list 'a '(:a :b) 'b '(:b :c)) '(a b)))))
      (expect (funcall canonicalize (list 'x :c 'y :b))
              :to-equal (list 'x :a 'y :b)))
    (let ((canonicalize (spec-state-canonicalizer
                         (symmetry-test-spec (list 'a '(:a :b) 'b '(:c :d)) '(a b)))))
      (expect (funcall canonicalize (list 'x :b 'y :d))
              :to-equal (list 'x :a 'y :c))))

  (it "rejects nil as a symmetric element"
    (dolist (domain (list (list nil :a) (spec-set nil :a)))
      (expect (handler-case
                  (progn (spec-state-canonicalizer
                          (symmetry-test-spec (list (quote procs) domain) (quote (procs))))
                         :no-error)
                (spec-definition-error () :signalled))
              :to-be :signalled)))

  (it "rejects constants that are neither a set nor a list"
    (dolist (value (list 42 (spec-sequence 1 2) (make-spec-function nil)
                         (make-spec-record) (cons 1 2)))
      (expect (handler-case
                  (progn (spec-state-canonicalizer
                          (symmetry-test-spec (list 'procs value) '(procs))) :no-error)
                (spec-definition-error () :signalled))
              :to-be :signalled))))
