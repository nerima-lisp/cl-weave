(in-package #:cl-weave/test)

(describe "it-fuzz"
  (it-fuzz "passes when the body never signals an error"
      ((n (gen-integer :min -50 :max 50)))
      (:trials 20 :timeout-per-trial 1)
    (+ n 1))

  (it-fuzz "treats a per-trial timeout as neither a pass nor a failure"
      ((n (gen-integer :min 0 :max 5)))
      (:trials 5 :timeout-per-trial 1)
    (when (= n 3)
      #+sbcl (sleep 2)
      #-sbcl nil)
    n)

  (it "fails when the body signals an error on some generated input"
    ;; IT-FUZZ expands to (IT name (RUN-PROPERTY ...)); IT only registers a
    ;; test for deferred execution, so EVAL-ing an IT-FUZZ form can't be used
    ;; to observe a failure directly. Call the same RUN-PROPERTY mechanism
    ;; IT-FUZZ's expansion calls, which runs synchronously.
    (expect (lambda ()
              (cl-weave::run-property
               (list (gen-integer :min -100 :max 100))
               (lambda (n)
                 (handler-case
                     (cl-weave::call-with-platform-timeout/k
                      1
                      (lambda () (when (minusp n) (error "negative! ~A" n)) n)
                      (function identity))
                   (cl-weave::platform-timeout () :fuzz-trial-timed-out)))
               '(n)
               '(fuzz-crash-probe)))
            :to-throw))

  (it "rejects an unknown option key at macroexpansion time"
    (expect (lambda ()
              (eval '(cl-weave:it-fuzz "bad options" ((n (cl-weave:gen-integer)))
                          (:unsupported-option t)
                        n)))
            :to-throw))

  (it "rejects malformed IT-FUZZ options and bindings at macroexpansion time"
    (expect (lambda ()
              (eval '(cl-weave:it-fuzz "bad options shape" ((n (cl-weave:gen-integer)))
                          (:trials . 1)
                        n)))
            :to-throw
            "IT-FUZZ requires OPTIONS to be a literal proper list")
    (expect (lambda ()
              (eval '(cl-weave:it-fuzz "bad bindings shape" ((n (cl-weave:gen-integer)) . 5)
                          (:trials 1)
                        n)))
            :to-throw
            "IT-FUZZ requires BINDINGS to be a literal proper list")
    (expect (lambda ()
              (eval '(cl-weave:it-fuzz "malformed binding" ((n))
                          (:trials 1)
                        n)))
            :to-throw
            "must have the form (NAME GENERATOR)")))
