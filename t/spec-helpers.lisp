(in-package #:cl-weave/spec-test)

;;;; Small specifications shared by the cl-weave/spec test files. Their state
;;;; spaces are small enough to enumerate by hand; the hand-computed answers
;;;; live in the tests, not here. Add new shared fixtures below, never edit
;;;; these.

;;; One variable counting up to LIMIT. Reachable states: x = 0..LIMIT, one
;;; action, and a deadlock at x = LIMIT.
(defspec counter ((limit 3))
  (:variables x)
  (:init (x 0))
  (:action inc
    (:guard (< x limit))
    (:next (x (1+ x))))
  (:invariant within-limit (<= x limit)))

;;; Two initial states and a quantified action. SET-X may pick any value in
;;; (0 1 2) different from the current x; BUMP-Y raises y once.
(defspec chooser ()
  (:variables x y)
  (:init (x (:in (list 0 1))) (y 0))
  (:action set-x
    (:for (v (list 0 1 2)))
    (:guard (/= x v))
    (:next (x v)))
  (:action bump-y
    (:guard (< y 1))
    (:next (y (1+ y)))))

(defun transition-summaries (transitions)
  "List of (ACTION PARAMS TO) for TRANSITIONS, to compare against hand-computed answers."
  (mapcar (lambda (transition)
            (list (spec-transition-action transition)
                  (spec-transition-params transition)
                  (spec-transition-to transition)))
          transitions))
