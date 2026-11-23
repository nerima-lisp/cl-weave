(in-package #:cl-weave/spec-test)

;;; Registration macros (FR-012). Each test registers into a fresh root suite
;;; and runs it through the core runner, so the events show what the it family
;;; reports. Expected values are computed by hand from the fixtures below.
;;; The checks pass :symmetry nil because spec-state-canonicalizer is not
;;; implemented yet in this workspace (symmetry.lisp is empty).

;;; Reachable states: x = 0, 1, 2. The invariant SMALL fails at x = 2, reached
;;; by two steps from the initial state, so the shortest trace has 3 states.
(defspec small-invariant-fails ()
  (:variables x)
  (:init (x 0))
  (:action inc
    (:guard (< x 3))
    (:next (x (1+ x))))
  (:invariant small (< x 2)))

(defun registration-events (thunk)
  "Call THUNK, which registers tests, under a fresh root suite; return the events."
  (let ((root (cl-weave::make-suite :name "root")))
    (let ((cl-weave::*root-suite* root)
          (cl-weave::*current-suite* nil))
      (funcall thunk))
    (cl-weave::collect-events root)))

(defun registered-test (thunk)
  "Call THUNK, which registers one test, under a fresh root suite; return that test case."
  (let ((root (cl-weave::make-suite :name "root")))
    (let ((cl-weave::*root-suite* root)
          (cl-weave::*current-suite* nil))
      (funcall thunk))
    (first (cl-weave::suite-children root))))

(defun registration-error-p (form)
  "True when fully macroexpanding FORM signals an error."
  (handler-case (progn (macroexpand form) nil)
    (error () t)))

(describe "spec registration"
  (it "expands it-spec to it with the check form reported through report-spec-result"
    (expect (macroexpand-1 '(it-spec "counter explores clean" (explore-spec (counter))))
            :to-equal
            '(cl-weave:it "counter explores clean"
              (report-spec-result (explore-spec (counter)) :form '(explore-spec (counter))))))

  (it "expands it-spec-only to it-only with the check form reported through report-spec-result"
    (expect (macroexpand-1 '(it-spec-only "counter explores clean" (explore-spec (counter))))
            :to-equal
            '(cl-weave:it-only "counter explores clean"
              (report-spec-result (explore-spec (counter)) :form '(explore-spec (counter))))))

  (it "passes a check that holds"
    (let ((events (registration-events
                   (lambda ()
                     (it-spec "counter explores clean"
                       (explore-spec (counter) :check-deadlock nil :symmetry nil))))))
      (expect (mapcar #'cl-weave::test-event-status events) :to-equal '(:pass))))

  (it "reports a failing check through the assertion-failure route"
    (let* ((event (first (registration-events
                          (lambda ()
                            (it-spec "small invariant"
                              (explore-spec (small-invariant-fails) :symmetry nil))))))
           (detail (cl-weave::test-event-assertion event))
           (actual (cl-weave::assertion-detail-actual detail)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::assertion-detail-matcher detail) :to-be :spec)
      (expect (getf actual :kind) :to-be :invariant)
      (expect (getf actual :property) :to-be 'small)
      (expect (length (getf actual :minimal)) :to-be 3)))

  (it "focuses it-spec-only so the unfocused check does not run"
    (let ((events (registration-events
                   (lambda ()
                     (it-spec "unfocused fails"
                       (explore-spec (small-invariant-fails) :symmetry nil))
                     (it-spec-only "focused passes"
                       (explore-spec (counter) :check-deadlock nil :symmetry nil))))))
      (expect (mapcar #'cl-weave::test-event-path events)
              :to-equal '(("focused passes")))
      (expect (mapcar #'cl-weave::test-event-status events) :to-equal '(:pass))
      (expect (cl-weave::test-case-focus
               (registered-test
                (lambda ()
                  (it-spec-only "focused passes"
                    (explore-spec (counter) :check-deadlock nil :symmetry nil)))))
              :to-be t)))

  (it "passes the tag option through to it"
    (let ((test (registered-test
                 (lambda ()
                   (it-spec "tagged" (:tags '("slow"))
                     (explore-spec (counter) :check-deadlock nil :symmetry nil))))))
      (expect (cl-weave::test-case-tags test) :to-equal '("SLOW"))))

  (it "filters it-spec tests by name, so a filtered-out check does not run"
    (let ((root (cl-weave::make-suite :name "root")))
      (let ((cl-weave::*root-suite* root)
            (cl-weave::*current-suite* nil))
        (it-spec "wanted check"
          (explore-spec (counter) :check-deadlock nil :symmetry nil))
        (it-spec "other check"
          (explore-spec (small-invariant-fails) :symmetry nil)))
      (expect (mapcar #'cl-weave::test-event-path
                      (cl-weave::collect-events root :name-filter "wanted"))
              :to-equal '(("wanted check")))))

  (it "rejects a body with two check forms"
    (expect (registration-error-p
             '(it-spec "two checks" (explore-spec (counter)) (explore-spec (counter))))
            :to-be t))

  (it "rejects a body with no check form, with or without options"
    (expect (registration-error-p '(it-spec "no check")) :to-be t)
    (expect (registration-error-p '(it-spec "options only" (:tags '("slow")))) :to-be t))

  (it "leaves an unknown option to it"
    (expect (registration-error-p
             '(it-spec "bogus option" (:bogus 1) (explore-spec (counter))))
            :to-be t))

  (it "registers at the top level and inside describe"
    (let ((events (registration-events
                   (lambda ()
                     (it-spec "outside"
                       (explore-spec (counter) :check-deadlock nil :symmetry nil))
                     (describe "outer"
                       (it-spec "inside"
                         (explore-spec (counter) :check-deadlock nil :symmetry nil)))))))
      (expect (mapcar #'cl-weave::test-event-path events)
              :to-equal '(("outside") ("outer" "inside")))))

  (it "aggregates a failing check inside with-soft-assertions"
    (let* ((test (registered-test
                  (lambda ()
                    (it-spec "soft small invariant"
                      (explore-spec (small-invariant-fails) :symmetry nil)))))
           (wrapper (cl-weave::make-test-case
                     :name "soft wrapper"
                     :function (lambda ()
                                 (cl-weave:with-soft-assertions
                                   (funcall (cl-weave::test-case-function test))))))
           (event (cl-weave::run-test-case (cl-weave::make-suite :name "root") wrapper))
           (detail (cl-weave::test-event-assertion event))
           (failures (getf (cl-weave::assertion-detail-actual detail) :details)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::assertion-detail-matcher detail) :to-be :soft-assertions)
      (expect (length failures) :to-be 1)
      (expect (getf (first failures) :matcher) :to-be :spec))))
