(in-package #:cl-weave)

;;;; Soft assertions
;;;;
;;;; A normal EXPECT aborts the test at the first failure. Inside
;;;; WITH-SOFT-ASSERTIONS every EXPECT runs to completion, failures are
;;;; collected, and the block reports them together as a single aggregated
;;;; failure. This leans on the condition system: SIGNAL-ASSERTION-FAILURE
;;;; simply records into *SOFT-ASSERTION-SINK* and returns rather than
;;;; unwinding, so the collector needs no per-expression rewriting. Real
;;;; (non-assertion) errors still propagate immediately.

(defun soft-detail-report (detail)
  "Render a collected assertion DETAIL as a serialization-friendly plist."
  (list :form (assertion-detail-form detail)
        :matcher (assertion-detail-matcher detail)
        :actual (assertion-detail-actual detail)
        :expected (assertion-detail-expected detail)
        :negated (assertion-detail-negated detail)
        :pass (assertion-detail-pass detail)))

(defun aggregated-soft-failure-detail (details)
  (make-assertion-detail
   :form '(with-soft-assertions)
   :matcher :soft-assertions
   :actual (list :failures (length details)
                 :details (mapcar #'soft-detail-report details))
   :expected '(:failures 0)
   :negated nil
   :pass nil))

(defun call-with-soft-assertions (thunk)
  "Run THUNK collecting assertion failures; afterward signal one aggregated
failure if any were collected. Non-assertion errors from THUNK propagate."
  (let ((sink (make-array 0 :adjustable t :fill-pointer 0)))
    (let ((*soft-assertion-sink* sink))
      (funcall thunk))
    ;; Back outside the soft dynamic extent: a genuine failure now unwinds.
    (when (plusp (fill-pointer sink))
      (signal-assertion-failure
       (aggregated-soft-failure-detail (coerce sink 'list))))
    t))

(defmacro with-soft-assertions (&body body)
  "Evaluate BODY, letting every EXPECT run even after earlier ones fail, then
report all collected failures together as a single assertion failure. Use it
inside a test when several independent expectations should all be checked in one
run. Real errors still abort immediately."
  `(call-with-soft-assertions (lambda () ,@body)))
