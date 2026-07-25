(in-package #:cl-weave)

;;;; Deterministic Replay
;;;;
;;;; Layer two of the time-travel toolkit. The execution journal (layer one)
;;;; tells you WHAT happened; deterministic replay lets you make it happen
;;;; again, bit-for-bit. The lever is CL:*RANDOM-STATE*: when *TEST-RANDOM-SEED*
;;;; is set, every test attempt runs with a random state derived from that base
;;;; seed and the test's own path, so CL:RANDOM inside a test is reproducible
;;;; and independent of execution order (sharding, concurrency, focus, and
;;;; random sequencing cannot perturb it). Re-running the suite with the same
;;;; base seed reproduces the same randomness everywhere.
;;;;
;;;; Off by default so nothing touches the global random state unless asked.
;;;; Deterministic seeding uses SBCL's SB-EXT:SEED-RANDOM-STATE; on other
;;;; implementations the seed is still recorded but randomness is left alone.

(defvar *test-random-seed* nil
  "Base seed for deterministic per-test randomness. When a non-negative integer,
each test attempt binds CL:*RANDOM-STATE* to a state derived from this seed and
the test's path, making CL:RANDOM reproducible across runs and independent of
execution order. NIL (default) leaves the random state untouched. Deterministic
seeding requires SBCL.")

(defvar *attempt-replay-seed* nil
  "The effective per-test seed for the current attempt, or NIL. Read when an
event is constructed so reporters can surface it for replay.")

;; FNV-1a over the test path, mixed with the base seed. Mirrors
;; STABLE-STRING-HASH in runner-selection, duplicated here because that helper
;; loads after the runner internals that call us.
(defun replay-path-string (path)
  (format nil "~{~A~^ > ~}" path))

(defun replay-string-hash (string base)
  (let ((hash (mod (+ 2166136261 base) 4294967296)))
    (loop for char across string
          do (setf hash
                   (mod (* (logxor hash (char-code char)) 16777619)
                        4294967296)))
    hash))

(defun normalize-test-random-seed (seed)
  (cond
    ((null seed) nil)
    ((and (integerp seed) (not (minusp seed))) seed)
    (t (error "cl-weave: *test-random-seed* must be NIL or a non-negative integer, got ~S."
              seed))))

(defun test-replay-seed (base-seed path)
  "Return the deterministic 32-bit seed for PATH under BASE-SEED."
  (replay-string-hash (replay-path-string path) base-seed))

(defun replay-seed-for-attempt (path)
  "Return the effective replay seed for PATH, or NIL when replay is disabled."
  (let ((base (normalize-test-random-seed *test-random-seed*)))
    (when base
      (test-replay-seed base path))))

#+sbcl
(defun call-with-test-randomness (replay-seed thunk)
  (if replay-seed
      (let ((*random-state* (sb-ext:seed-random-state replay-seed)))
        (funcall thunk))
      (funcall thunk)))

#-sbcl
(defun call-with-test-randomness (replay-seed thunk)
  (declare (ignore replay-seed))
  (funcall thunk))
