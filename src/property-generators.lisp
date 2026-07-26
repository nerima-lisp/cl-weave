(in-package #:cl-weave)

;;;; Generator combinators: generators built out of other generators, as
;;;; opposed to the leaf generators in property-generators-primitives.lisp.

(defun state-machine-trace (initial-state transition events)
  (let ((state initial-state)
        (states (list initial-state)))
    (dolist (event events)
      (setf state (funcall transition state event))
      (push state states))
    (let ((ordered-states (nreverse states)))
      (list :initial initial-state
            :events events
            :states ordered-states
            :final (car (last ordered-states))))))

(defun state-machine-trace-p (trace)
    (and (finite-proper-list-p trace)
         (= (length trace) 8)
         (eq (first trace) :initial)
         (eq (third trace) :events)
         (finite-proper-list-p (fourth trace))
         (eq (fifth trace) :states)
         (finite-proper-list-p (sixth trace))
         (= (length (sixth trace)) (1+ (length (fourth trace))))
         (eq (seventh trace) :final)))

  (defun state-machine-trace-events (trace)
    (getf trace :events))

(defun gen-state-machine (initial-state transition event-generator
                          &key (min-length 0) (max-length 16))
  (unless (functionp transition)
    (error "cl-weave: gen-state-machine requires TRANSITION to be a function, got ~S."
           transition))
  (let ((events-generator (gen-list event-generator
                                    :min-length min-length
                                    :max-length max-length)))
    (make-property-generator
     :name :state-machine
     :produce (lambda (rng)
                (state-machine-trace
                 initial-state
                 transition
                 (funcall (property-generator-produce events-generator) rng)))
     :shrink (lambda (trace)
               (when (state-machine-trace-p trace)
                 (let ((trace-events (state-machine-trace-events trace)))
                   (when (<= min-length (length trace-events) max-length)
                     (loop for events in
                           (property-shrink-candidates events-generator trace-events)
                           collect (state-machine-trace initial-state
                                                        transition
                                                        events)))))))))

(defun gen-one-of (&rest generators)
  (let ((choices (ensure-property-generators generators "gen-one-of")))
    (make-property-generator
     :name :one-of
     :produce (lambda (rng)
                (let ((generator (nth (property-random-below rng (length choices))
                                      choices)))
                  (funcall (property-generator-produce generator) rng)))
     :shrink (lambda (value)
               (let ((candidates nil))
                 (dolist (generator choices)
                   (dolist (candidate
                            (property-shrink-candidates generator value))
                     (push candidate candidates)))
                 (remove-duplicate-shrink-candidates
                  (nreverse candidates) #'equal))))))

(defun gen-tuple (&rest generators)
  (let ((elements (ensure-property-generators generators "gen-tuple")))
    (make-property-generator
     :name :tuple
     :produce (lambda (rng)
                (loop for generator in elements
                      collect (funcall (property-generator-produce generator) rng)))
     :shrink (lambda (value)
               (when (and (finite-proper-list-p value)
                          (= (length value) (length elements)))
                 (let ((candidates nil))
                   (loop for generator in elements
                         for index from 0
                         for element in value
                         do (dolist
                                (shrunk
                                 (property-shrink-candidates generator element))
                              (push
                               (copy-sequence-and-set-item value index shrunk)
                               candidates)))
                   (remove-duplicate-shrink-candidates
                    (nreverse candidates) #'equal)))))))



(defun gen-such-that (predicate generator &key (attempts 100))
  (ensure-property-generator generator "gen-such-that")
  (unless (functionp predicate)
    (error "cl-weave: gen-such-that requires PREDICATE to be a function, got ~S."
           predicate))
  (unless (and (integerp attempts) (plusp attempts))
    (error "cl-weave: gen-such-that requires a positive integer ATTEMPTS, got ~S."
           attempts))
  (make-property-generator
   :name :such-that
   :produce (lambda (rng)
              (loop repeat attempts
                    for value = (funcall (property-generator-produce generator) rng)
                    when (funcall predicate value)
                      return value
                    finally
                       (error "cl-weave: gen-such-that could not produce a ~
                               matching value in ~D attempts."
                              attempts)))
   :shrink (lambda (value)
             (remove-if-not predicate
                            (property-shrink-candidates generator value)))))

(defun gen-recursive (base-generator builder &key (max-depth 4))
  (ensure-property-generator base-generator "gen-recursive")
  (unless (functionp builder)
    (error "cl-weave: gen-recursive requires BUILDER to be a function, got ~S."
           builder))
  (unless (and (integerp max-depth) (not (minusp max-depth)))
    (error "cl-weave: gen-recursive requires a non-negative integer MAX-DEPTH, got ~S."
           max-depth))
  (let (self step)
    (labels ((produce-value (rng)
               (let ((depth (or *recursive-generator-depth* max-depth)))
                 (if (<= depth 0)
                     (funcall (property-generator-produce base-generator) rng)
                     (let ((*recursive-generator-depth* (1- depth)))
                       (if (zerop (property-random-below rng 3))
                           (funcall (property-generator-produce base-generator) rng)
                           (funcall (property-generator-produce step) rng))))))
             (shrink-value (value)
               (remove-duplicate-shrink-candidates
                (append (property-shrink-candidates base-generator value)
                        (property-shrink-candidates step value))
                #'equal)))
      (setf self
            (make-property-generator
             :name :recursive-self
             :produce #'produce-value
             :shrink #'shrink-value))
      (setf step (funcall builder self))
      (ensure-property-generator step "gen-recursive builder")
      (make-property-generator
       :name :recursive
       :produce #'produce-value
       :shrink #'shrink-value))))

(defun gen-sexp (&key
                   (atoms (gen-one-of (gen-integer :min -8 :max 8)
                                      (gen-boolean)
                                      (gen-keyword)))
                   (max-depth 4)
                   (max-list-length 4))
  (gen-recursive
   atoms
   (lambda (self)
     (gen-list self :min-length 0 :max-length max-list-length))
   :max-depth max-depth))

(defun gen-form (&key
                   (atoms (gen-one-of (gen-integer :min -8 :max 8)
                                      (gen-boolean)
                                      (gen-symbol :package "CL-USER")))
                   (operators '(progn list cons + - *))
                   (max-depth 4)
                   (max-arguments 3))
  (gen-recursive
   atoms
   (lambda (self)
     (gen-map
      (lambda (parts)
        (destructuring-bind (operator arguments) parts
          (cons operator arguments)))
      (gen-tuple (gen-member operators)
                 (gen-list self :min-length 0 :max-length max-arguments))
      :name :form))
   :max-depth max-depth))
