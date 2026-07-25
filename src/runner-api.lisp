(in-package #:cl-weave)

(defun passed-event-p (event)
  (member (test-event-status event) '(:pass :skip :todo)))


(defparameter *run-reporters*
  '(:spec :sexp :json :jsonl :tap :github :junit))

(defparameter *list-reporters* '(:spec :sexp :json :jsonl))

(defun run-reporters ()
  (copy-list *run-reporters*))

(defun list-reporters ()
  (copy-list *list-reporters*))

(defun ensure-run-reporter (reporter)
  (unless (member reporter (run-reporters))
    (error "cl-weave: run mode supports spec, sexp, json, jsonl, tap, github, and junit reporters."))
  reporter)

(defun ensure-list-reporter (reporter)
  (unless (member reporter (list-reporters))
    (error "cl-weave: list mode supports spec, sexp, json, and jsonl reporters."))
  reporter)

(defun ensure-output-stream (stream)
  (unless (and (streamp stream)
               (open-stream-p stream)
               (output-stream-p stream))
    (error "cl-weave: expected an open output stream."))
  stream)

(defun emit-run-report (reporter events stream)
  (when reporter
    (ensure-run-reporter reporter)
    (ecase reporter
      (:spec (report-spec events stream))
      (:sexp (report-sexp events stream))
      (:json (report-json events stream))
      (:jsonl (report-jsonl events stream))
      (:tap (report-tap events stream))
      (:github (report-github events stream))
      (:junit (report-junit events stream)))))

(progn
  (defun find-suite-by-designator-unlocked (suite-designator suite)
    (let ((target (named-suite-key suite-designator))
          (stack (list suite)))
      (loop while stack
            for node = (pop stack)
            do (when (suite-p node)
                 (when (equal (named-suite-key (suite-name node)) target)
                   (return node))
                 (let ((children nil))
                   (dolist (child (suite-children node))
                     (when (suite-p child)
                       (push child children)))
                   (dolist (child children)
                     (push child stack)))))))

  (defun find-suite-by-designator
      (suite-designator &optional (suite nil suite-supplied-p))
    (with-test-registry-lock
      (find-suite-by-designator-unlocked
       suite-designator
       (if suite-supplied-p suite *root-suite*)))))

(defun resolve-suite-designator (suite-designator)
  (cond
    ((null suite-designator) (root-suite))
    ((suite-p suite-designator) suite-designator)
    (t
     (let ((key (named-suite-key suite-designator))
           (suite nil))
       (with-test-registry-lock
         (multiple-value-bind (named-suite presentp)
             (gethash key *named-suites*)
           (setf suite
                 (if presentp
                     named-suite
                     (find-suite-by-designator-unlocked
                      suite-designator
                      *root-suite*)))
           (when (and suite (not presentp))
             (setf (gethash key *named-suites*) suite)
             (note-test-registry-change-unlocked))))
       (or suite
           (error "cl-weave: unknown suite designator ~S."
                  suite-designator))))))

(defun normalize-run-results (results)
  (let ((events nil)
        (active-conses (make-hash-table :test (function eq)))
        (work (list (cons :visit results))))
    (loop while work
          for item = (pop work)
          for action = (car item)
          for value = (cdr item)
          do (ecase action
               (:visit
                (cond
                  ((null value))
                  ((test-event-p value)
                   (push value events))
                  ((consp value)
                   (when (gethash value active-conses)
                     (error "cl-weave: circular nested event lists are not supported."))
                   (setf (gethash value active-conses) t)
                   (push (cons :leave value) work)
                   (push (cons :visit (cdr value)) work)
                   (push (cons :visit (car value)) work))
                  (t
                   (error "cl-weave: expected test events or nested event lists, got ~S."
                          value))))
               (:leave
                (remhash value active-conses))))
    (nreverse events)))

(defun run (suite-designator
            &key reporter
              (stream *standard-output*)
              (name-filter *test-name-filter*)
              location-filter
              include-tags
              exclude-tags
              shard
              order
              seed
              bail
              retry
              timeout-ms
              max-workers)
  (when reporter
    (ensure-run-reporter reporter)
    (ensure-output-stream stream))
  (let* ((collection-options
           (normalize-collection-options
            :name-filter name-filter
            :location-filter location-filter
            :include-tags include-tags
            :exclude-tags exclude-tags
            :shard shard
            :order order
            :seed seed
            :bail bail
            :retry retry
            :timeout-ms timeout-ms
            :max-workers max-workers))
         (events
           (collect-events-with-options
            (resolve-suite-designator suite-designator)
            collection-options)))
    (emit-run-report reporter events stream)
    events))

(defun explain! (results &optional (stream *standard-output*))
  (ensure-output-stream stream)
  (report-spec (normalize-run-results results) stream)
  (values))

(defun results-status (results)
  (let ((passedp t)
        (leave-marker (list nil))
        (active-conses (make-hash-table :test (function eq)))
        (work (list results)))
    (loop while work
          for item = (pop work)
          do (if (and (consp item)
                      (eq (car item) leave-marker))
                 (remhash (cdr item) active-conses)
                 (cond
                   ((null item))
                   ((test-event-p item)
                    (unless (passed-event-p item)
                      (setf passedp nil)))
                   ((consp item)
                    (when (gethash item active-conses)
                      (error "cl-weave: circular nested event lists are not supported."))
                    (setf (gethash item active-conses) t)
                    (push (cons leave-marker item) work)
                    (push (cdr item) work)
                    (push (car item) work))
                   (t
                    (error "cl-weave: expected test events or nested event lists, got ~S."
                           item)))))
    passedp))

(defun run-all (&key (reporter :spec)
                  (stream *standard-output*)
                  (name-filter *test-name-filter*)
                  location-filter
                  test-path-filter
                  include-tags
                  exclude-tags
                  shard
                  order
                  seed
                  bail
                  retry
                  timeout-ms
                  max-workers
                  coverage
                  coverage-output
                  coverage-report-directory
                  coverage-include-pathnames
                  coverage-exclude-pathnames
                  coverage-minimum-expression
                  coverage-minimum-branch
                  (pass-with-no-tests t)
                  (coverage-reset t))
  (ensure-run-reporter reporter)
  (ensure-output-stream stream)
  (let ((collection-options
          (normalize-collection-options
           :name-filter name-filter
           :location-filter location-filter
           :test-path-filter test-path-filter
           :include-tags include-tags
           :exclude-tags exclude-tags
           :shard shard
           :order order
           :seed seed
           :bail bail
           :retry retry
           :timeout-ms timeout-ms
           :max-workers max-workers)))
    (call-with-coverage
     coverage
     coverage-output
     coverage-report-directory
     coverage-reset
     (lambda ()
       (let ((events
               (collect-events-with-options
                (root-suite)
                collection-options)))
         (emit-run-report reporter events stream)
         (and (or pass-with-no-tests events)
              (every #'passed-event-p events))))
     :include-pathnames coverage-include-pathnames
     :exclude-pathnames coverage-exclude-pathnames
     :minimum-expression coverage-minimum-expression
     :minimum-branch coverage-minimum-branch)))

(defun list-tests (&key (reporter :spec)
                     (stream *standard-output*)
                     (name-filter *test-name-filter*)
                     location-filter
                     include-tags
                     exclude-tags
                     shard
                     order
                     seed
                     retry
                     timeout-ms)
  (ensure-list-reporter reporter)
  (ensure-output-stream stream)
  (let* ((collection-options
           (normalize-collection-options
            :name-filter name-filter
            :location-filter location-filter
            :include-tags include-tags
            :exclude-tags exclude-tags
            :shard shard
            :order order
            :seed seed
            :retry retry
            :timeout-ms timeout-ms))
         (plan
           (collect-test-plan-with-options
            (root-suite)
            collection-options)))
    (ecase reporter
      (:spec (report-plan-spec plan stream))
      (:sexp (report-plan-sexp plan stream))
      (:json (report-plan-json plan stream))
      (:jsonl (report-plan-jsonl plan stream)))
    plan))
