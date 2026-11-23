(in-package #:cl-weave/spec-test)

(describe "spec value model"
  (it "normalizes sets independently of insertion order and fingerprint"
    (let ((a (spec-set 3 1 2 1))
          (b (make-spec-set (list 2 3 1))))
      (expect a :to-equal b)
      (expect (state-fingerprint (list 'x a))
              :to-be (state-fingerprint (list 'x b)))
      (expect (spec-set-elements a) :to-equal '(1 2 3))
      (expect (spec-set-size a) :to-be 3)))

  (it "orders mixed types and keeps integer and float elements distinct"
    (let ((s (spec-set '(1) 'a "a" #\a 1.0 1)))
      (expect (spec-set-size s) :to-be 6)
      (expect (spec-set-elements s) :to-equal (spec-set-elements
                                              (spec-set 1 #\a '(1) "a" 'a 1.0)))
      (expect (spec-set-member-p 1 s) :to-be t)
      (expect (spec-set-member-p 1.0 s) :to-be t)
      (expect (mapcar (lambda (x) (cond ((numberp x) :number)
                                        ((characterp x) :character)
                                        ((stringp x) :string)
                                        ((symbolp x) :symbol)
                                        (t :cons)))
                      (spec-set-elements s))
              :to-equal '(:number :number :character :string :symbol :cons))))

  (it "supports empty values and a set containing nil"
    (expect (spec-set-p (spec-set)) :to-be t)
    (expect (spec-set-elements (spec-set)) :to-equal nil)
    (expect (spec-function-p (make-spec-function nil)) :to-be t)
    (expect (spec-function-domain (make-spec-function nil)) :to-equal (spec-set))
    (expect (spec-record-p (make-spec-record)) :to-be t)
    (expect (spec-record-fields (make-spec-record)) :to-equal nil)
    (expect (spec-sequence-p (spec-sequence)) :to-be t)
    (expect (spec-sequence-elements (spec-sequence)) :to-equal nil)
    (expect (spec-set-member-p nil (spec-set nil)) :to-be t)
    (expect (spec-set-member-p nil (spec-set)) :to-be nil))

  (it "performs set operations and comprehensions"
    (let ((a (spec-set 1 2 3)) (b (spec-set 3 4)))
      (expect (spec-set-union a b) :to-equal (spec-set 1 2 3 4))
      (expect (spec-set-intersection a b) :to-equal (spec-set 3))
      (expect (spec-set-difference a b) :to-equal (spec-set 1 2))
      (expect (spec-subset-p (spec-set 1 3) a) :to-be t)
      (expect (spec-subset-p b a) :to-be nil)
      (expect (spec-set-filter #'oddp a) :to-equal (spec-set 1 3))
      (expect (spec-set-map (lambda (x) (mod x 2)) a) :to-equal (spec-set 0 1))
      (expect (spec-set-of (* x 2) :for x :in a :when (oddp x))
              :to-equal (spec-set 2 6))))

  (it "constructs the powerset including empty and full subsets"
    (expect (spec-powerset (spec-set)) :to-equal (spec-set (spec-set)))
    (expect (spec-powerset (spec-set 1 2))
            :to-equal (spec-set (spec-set) (spec-set 1) (spec-set 2) (spec-set 1 2)))
    (expect (handler-case (progn (spec-powerset (make-spec-set (loop for i below 21 collect i))) :no-error)
              (spec-value-error () :signalled))
            :to-be :signalled))

  (it "normalizes nested sets and function values"
    (expect (spec-set (spec-set 2 1) (spec-set 1 2))
            :to-equal (spec-set (spec-set 1 2)))
    (expect (make-spec-function (list (cons 2 (spec-set 2 1)) (cons 1 (spec-set 3))))
            :to-equal (make-spec-function (list (cons 1 (spec-set 3)) (cons 2 (spec-set 1 2))))))

  (it "preserves constructor inputs"
    (let* ((elements (list 3 1 2 1))
           (pairs (list (cons 2 'b) (cons 1 'a)))
           (seq (list 3 1 2)))
      (make-spec-set elements)
      (make-spec-function pairs)
      (make-spec-sequence seq)
      (expect elements :to-equal '(3 1 2 1))
      (expect pairs :to-equal '((2 . b) (1 . a)))
      (expect seq :to-equal '(3 1 2))))

  (it "constructs, applies and updates finite functions"
    (let* ((f (spec-function-over (spec-set 2 1) (lambda (x) (* x 10))))
           (updated (spec-function-except f 1 99)))
      (expect (spec-function-domain f) :to-equal (spec-set 1 2))
      (expect (spec-function-apply f 1) :to-be 10)
      (expect (spec-function-apply updated 1) :to-be 99)
      (expect (spec-function-apply updated 2) :to-be 20)
      (expect (spec-function-apply f 1) :to-be 10)
      (expect (length (spec-function-pairs f)) :to-be 2)))

  (it "rejects duplicate function keys and outside-domain access"
    (dolist (thunk (list (lambda () (make-spec-function '((1 . a) (1 . b))))
                         (lambda () (spec-function-apply (make-spec-function '((1 . a))) 2))
                         (lambda () (spec-function-except (make-spec-function '((1 . a))) 2 'b))))
      (expect (handler-case (progn (funcall thunk) :no-error)
                (spec-value-error () :signalled)) :to-be :signalled)))

  (it "normalizes records and updates existing fields"
    (let* ((r (make-spec-record 'b 2 'a 1))
           (updated (spec-record-except r 'a 7)))
      (expect r :to-equal (make-spec-record 'a 1 'b 2))
      (expect (spec-record-ref r 'a) :to-be 1)
      (expect (spec-record-ref updated 'a) :to-be 7)
      (expect (spec-record-ref updated 'b) :to-be 2)
      (expect (spec-record-ref r 'a) :to-be 1)))

  (it "rejects duplicate or non-symbol fields and missing fields"
    (dolist (thunk (list (lambda () (make-spec-record 'a 1 'a 2))
                         (lambda () (make-spec-record 1 2))
                         (lambda () (spec-record-ref (make-spec-record 'a 1) 'b))
                         (lambda () (spec-record-except (make-spec-record 'a 1) 'b 2))))
      (expect (handler-case (progn (funcall thunk) :no-error)
                (spec-value-error () :signalled)) :to-be :signalled)))

  (it "concatenates and indexes sequences from zero"
    (let ((s (spec-sequence-concat (spec-sequence 'a 'b) (spec-sequence 'c))))
      (expect (spec-sequence-elements s) :to-equal '(a b c))
      (expect (spec-sequence-length s) :to-be 3)
      (expect (spec-sequence-ref s 0) :to-be 'a)
      (expect (spec-sequence-ref s 2) :to-be 'c)
      (dolist (index '(-1 3))
        (expect (handler-case (progn (spec-sequence-ref s index) :no-error)
                  (spec-value-error () :signalled)) :to-be :signalled))))

  (it "maps atoms through nested values and renormalizes"
    (let* ((value (spec-sequence (spec-set 1 2)
                                 (make-spec-function (list (cons 1 (spec-set 2))))
                                 (make-spec-record 'field 2)))
           (mapped (map-value-atoms (lambda (x) (if (eql x 2) 1 x)) value)))
      (expect mapped :to-equal
              (spec-sequence (spec-set 1)
                             (make-spec-function (list (cons 1 (spec-set 1))))
                             (make-spec-record 'field 1))))))

(describe "spec value symbol ordering"
  (it "orders uninterned symbols before packages and names within a package"
    (let ((uninterned (make-symbol "Z")))
      (expect (spec-set-elements (spec-set :b 'cl:car :a uninterned))
              :to-equal (list uninterned 'cl:car :a :b)))))

(describe "spec value atom mapping"
  (it "rejects colliding function keys even when their values agree"
    (let ((f (make-spec-function '((1 . a) (2 . a)))))
      (expect (handler-case
                  (progn (map-value-atoms (lambda (x) (if (eql x 2) 1 x)) f)
                         :no-error)
                (spec-value-error () :signalled))
              :to-be :signalled))))
