(in-package #:cl-weave)

(defun gen-integer (&key (min -100) (max 100))
  (check-type min integer)
  (check-type max integer)
  (when (> min max)
    (error "cl-weave: gen-integer requires MIN <= MAX, got ~S and ~S." min max))
  (locally
      (declare (notinline make-integer-producer make-integer-shrinker))
    (let ((shrinker (make-integer-shrinker min max)))
      (make-property-generator
       :name :integer
       :produce (make-integer-producer min max)
       :shrink (lambda (value)
                 (when (integerp value)
                   (funcall shrinker value)))))))

(defun gen-boolean ()
  (make-property-generator
   :name :boolean
   :produce (lambda (rng)
              (zerop (property-random-below rng 2)))
   :shrink (lambda (value)
             (when (typep value 'boolean)
               (if value (list nil) nil)))))

(defun gen-character (&key (alphabet "abcdefghijklmnopqrstuvwxyz"))
  (let ((choices (ensure-non-empty-sequence alphabet "gen-character ALPHABET")))
    (make-property-generator
     :name :character
     :produce (lambda (rng)
                (elt choices (property-random-below rng (length choices))))
     :shrink (lambda (value)
               (when (characterp value)
                 (let ((first-character (elt choices 0)))
                   (unless (char= value first-character)
                     (list first-character))))))))

(defun gen-member (values)
  (when (null values)
    (error "cl-weave: gen-member requires at least one value."))
  (make-property-generator
   :name :member
   :produce (lambda (rng)
              (nth (property-random-below rng (length values)) values))
   :shrink (lambda (value)
             (when (member value values :test #'equal)
               (let ((first-value (first values)))
                 (unless (equal value first-value)
                   (list first-value)))))))

(defun gen-map (function generator &key (name :map))
  (ensure-property-generator generator "gen-map")
  (unless (functionp function)
    (error "cl-weave: gen-map requires FUNCTION to be a function, got ~S."
           function))
  (make-property-generator
   :name name
   :produce (lambda (rng)
              (funcall function
                       (funcall (property-generator-produce generator) rng)))
   :shrink (lambda (value)
             (declare (ignore value))
             nil)))

(defun gen-list (element-generator &key (min-length 0) (max-length 8))
  (make-bounded-sequence-generator :list element-generator min-length max-length "gen-list"
                                   #'finite-proper-list-p nil #'identity))

(defun gen-string (&key (min-length 0)
                        (max-length 16)
                        (alphabet "abcdefghijklmnopqrstuvwxyz"))
  (let ((character-generator (gen-character :alphabet alphabet)))
    (make-bounded-sequence-generator :string character-generator
                                     min-length max-length
                                     "gen-string" #'stringp ""
                                     (lambda (items) (coerce items 'string))
                                     :hash-test #'equal)))

(defun gen-vector (element-generator &key (min-length 0) (max-length 8))
  (make-bounded-sequence-generator :vector element-generator min-length max-length "gen-vector"
                                   #'vectorp #() (lambda (items) (coerce items 'vector))
                                   :hash-test #'equalp))

(defun gen-symbol (&key (names '("x" "y" "value" "state")) package)
  (gen-map
   (lambda (name)
     (if package
         (intern name package)
         (make-symbol name)))
   (gen-member names)
   :name :symbol))

(defun gen-keyword (&optional (names '("x" "y" "value" "state")))
  (gen-map
   (lambda (name)
     (intern name "KEYWORD"))
   (gen-member names)
   :name :keyword))
