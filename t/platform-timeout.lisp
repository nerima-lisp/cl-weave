(in-package #:cl-weave/test)

(describe "platform timeout protocol"
  (it "reports whether bounded execution is available"
    #+sbcl
    (expect (cl-weave::platform-capability-available-p :timeout) :to-be t)
    #-sbcl
    (expect (cl-weave::platform-capability-available-p :timeout) :to-be nil))

  (it "runs through the continuation when no timeout is requested"
    (expect (cl-weave::call-with-platform-timeout/k
             nil (lambda () :completed) #'identity)
            :to-be :completed))

  (it "does not silently ignore an unavailable timeout capability"
    (let ((cl-weave::*platform-capabilities* nil)
          (cl-weave::*platform-timeout-caller* nil))
      (expect
       (lambda ()
         (cl-weave::call-with-platform-timeout/k
          0.01 (lambda () :not-run) #'identity))
       :to-throw 'cl-weave::platform-capability-unavailable)))

  #+sbcl
  (it "normalizes the implementation timeout condition"
    (expect
     (lambda ()
       (cl-weave::call-with-platform-timeout/k
        0.01
        (lambda () (sleep 0.1))
        #'identity))
     :to-throw 'cl-weave::platform-timeout)))
