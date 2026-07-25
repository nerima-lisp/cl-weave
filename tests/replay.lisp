(in-package #:cl-weave/tests)

(defun run-random-capture (name seed)
  "Run a test named NAME under base SEED, returning the CL:RANDOM it draws."
  (let ((captured nil)
        (cl-weave::*test-random-seed* seed))
    (let ((test (cl-weave::make-test-case
                 :name name
                 :function (lambda () (setf captured (random 1000000))))))
      (cl-weave::run-test-case (cl-weave::root-suite) test)
      captured)))

(defun run-seeded-event (name seed)
  (let ((cl-weave::*test-random-seed* seed)
        (test (cl-weave::make-test-case
               :name name
               :function (lambda () (expect t :to-be t)))))
    (cl-weave::run-test-case (cl-weave::root-suite) test)))

(describe "deterministic replay"
  (it "leaves the random state untouched by default"
    (let* ((test (cl-weave::make-test-case
                  :name "unseeded"
                  :function (lambda () (expect t :to-be t))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-replay-seed event) :to-be nil)))

  (it "reproduces the same randomness for the same base seed"
    (expect (run-random-capture "repeatable" 42)
            :to-be
            (run-random-capture "repeatable" 42)))

  (it "derives independent seeds for different test paths"
    (expect (cl-weave::test-replay-seed 42 '("alpha"))
            :not :to-be (cl-weave::test-replay-seed 42 '("beta"))))

  (it "derives different seeds for different base seeds"
    (expect (cl-weave::test-replay-seed 1 '("same"))
            :not :to-be (cl-weave::test-replay-seed 2 '("same"))))

  (it "records the effective replay seed on the event"
    (let ((event (run-seeded-event "seeded" 99)))
      (expect (cl-weave::test-event-status event) :to-be :pass)
      (expect (cl-weave::test-event-replay-seed event)
              :to-be (cl-weave::test-replay-seed 99 '("seeded")))))

  (it "accepts NIL and non-negative integer seeds only"
    (expect (cl-weave::normalize-test-random-seed nil) :to-be nil)
    (expect (cl-weave::normalize-test-random-seed 0) :to-be 0)
    (expect (cl-weave::normalize-test-random-seed 123) :to-be 123)
    (signals error (cl-weave::normalize-test-random-seed -1))
    (signals error (cl-weave::normalize-test-random-seed 1.5))))

(describe "replay-test"
  (it "replays a registered test by path and returns its timeline"
    (let* ((suite (cl-weave::make-suite :name "root"))
           (test (cl-weave::make-test-case
                  :name "adds numbers"
                  :function (lambda () (expect (+ 1 1) :to-be 2))))
           (cl-weave::*root-suite* suite))
      (cl-weave::add-child suite test)
      (multiple-value-bind (event frames)
          (cl-weave:replay-test '("adds numbers"))
        (expect (cl-weave::test-event-status event) :to-be :pass)
        (expect (length frames) :to-be 1)
        (expect (cl-weave:journal-frame-pass (first frames)) :to-be t))))

  (it "accepts a ' > '-joined path string and reproduces randomness by seed"
    (let* ((suite (cl-weave::make-suite :name "root"))
           (group (cl-weave::make-suite :name "math" :parent suite))
           (captured nil)
           (test (cl-weave::make-test-case
                  :name "random draw"
                  :function (lambda ()
                              (setf captured (random 1000000))
                              (expect t :to-be t))))
           (cl-weave::*root-suite* suite))
      (cl-weave::add-child suite group)
      (cl-weave::add-child group test)
      (cl-weave:replay-test "math > random draw" :seed 42)
      (let ((first-draw captured))
        (cl-weave:replay-test "math > random draw" :seed 42)
        (expect captured :to-be first-draw))))

  (it "signals when the path matches no registered test"
    (let* ((suite (cl-weave::make-suite :name "root"))
           (cl-weave::*root-suite* suite))
      (expect (lambda () (cl-weave:replay-test '("missing")))
              :to-throw 'error)))

  (it "rejects malformed replay paths"
    (expect (lambda () (cl-weave::normalize-replay-path 42))
            :to-throw 'error))

  (it "signals journal-breakpoint-hit at the requested frame index"
    (let* ((suite (cl-weave::make-suite :name "root"))
           (test (cl-weave::make-test-case
                  :name "two assertions"
                  :function (lambda ()
                              (expect 1 :to-be 1)
                              (expect 2 :to-be 2))))
           (cl-weave::*root-suite* suite)
           (seen nil))
      (cl-weave::add-child suite test)
      (handler-bind ((cl-weave:journal-breakpoint-hit
                       (lambda (condition)
                         (push (cl-weave:journal-frame-index
                                (cl-weave:journal-breakpoint-hit-frame condition))
                               seen)
                         (invoke-restart 'continue))))
        (cl-weave:replay-test '("two assertions") :breakpoint 1))
      (expect seen :to-equal '(1))))

  (it "never breaks when breakpoint is omitted"
    (let* ((suite (cl-weave::make-suite :name "root"))
           (test (cl-weave::make-test-case
                  :name "plain"
                  :function (lambda () (expect t :to-be t))))
           (cl-weave::*root-suite* suite)
           (hit nil))
      (cl-weave::add-child suite test)
      (handler-bind ((cl-weave:journal-breakpoint-hit
                       (lambda (condition)
                         (declare (ignore condition))
                         (setf hit t)
                         (invoke-restart 'continue))))
        (cl-weave:replay-test '("plain")))
      (expect hit :to-be nil))))

(describe "deterministic replay JSON reporter"
  (it "emits a null replaySeed for unseeded events"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-json
                     (list (make-sample-event
                            :status :pass
                            :path '("replay" "none")))
                     stream))))
      (expect output :to-contain "\"replaySeed\":null")))

  (it "emits the integer replaySeed for seeded events"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-json
                     (list (make-sample-event
                            :status :pass
                            :path '("replay" "seeded")
                            :replay-seed 12345))
                     stream))))
      (expect output :to-contain "\"replaySeed\":12345"))))
