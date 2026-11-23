(in-package #:cl-weave/spec-test)

;;;; Self-verification of the snapshot session and the mock lifecycle (FR-014).
;;;;
;;;; Each area has an abstract specification, broken variants of it, and a
;;;; conformance check that drives the real code from outside. The model mirrors
;;;; the code as it is, not as one might wish it to be: cl-weave has no
;;;; rollback. A snapshot session flushes whatever is staged when its scope
;;;; exits, normally or not, so the closing action of the snapshot model is
;;;; always a flush.
;;;;
;;;; Isolation: every operation binds the snapshot special variables to a
;;;; private temporary directory and to the session stored in the SUT, so the
;;;; session the test runner holds is never touched. Mock tests spy on a fresh
;;;; uninterned symbol per SUT and discard it when the next SUT is created.

;;; ------------------------------------------------------------------
;;; Temporary directories
;;; ------------------------------------------------------------------

(defvar *selfv-temp-counter* 0)

(defun selfv-make-temp-root ()
  ;; TRUENAME resolves symlinked temporary directories: the snapshot session
  ;; keys its files by a canonical pathname, and an unresolved parent would
  ;; make that key change once the file exists (see the report notes).
  (loop repeat 100
        for directory = (uiop:ensure-directory-pathname
                         (merge-pathnames
                          (format nil "cl-weave-selfv-~D-~36R-~D/"
                                  #+sbcl (sb-posix:getpid) #-sbcl 0
                                  (get-universal-time) (incf *selfv-temp-counter*))
                          (uiop:temporary-directory)))
        unless (probe-file directory)
          do (ensure-directories-exist directory)
             (return (truename directory))
        finally (error "Could not allocate a temporary directory.")))

(defun selfv-delete-tree (directory)
  (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))

;;; ------------------------------------------------------------------
;;; Snapshot specification
;;; ------------------------------------------------------------------
;;;
;;; DISK is the snapshot file as an ordered alist of (key . string). SESSION
;;; is :none or :open. VIEW is what the open session reads: :unloaded until
;;; the first access, then the file contents as of that access plus the staged
;;; operations (so an external write after loading leaves it stale). OPS is the
;;; list of staged operations, oldest first. An operation is (:set key value)
;;; or (:seq prefix values); a sequence operation replaces every prefix[i]
;;; entry and appends the new ones.
;;;
;;; Writes outside a session go straight to disk (DIRECT-WRITE). Inside a
;;; session they are staged (STAGE-WRITE). A flush re-applies the staged
;;; operations to the file as it is at flush time, so another writer's changes
;;; to other keys survive. END-SESSION is a flush followed by closing.

(defparameter *selfv-default-snapshot-ops*
  '((:set "a" "1") (:set "a" "2") (:set "b" "1")
    (:seq "s" ()) (:seq "s" ("1")) (:seq "s" ("1" "2"))))

(defun selfv-snap-seq-key-p (prefix key)
  (let ((n (length prefix)))
    (and (> (length key) (+ n 2))
         (string= prefix key :end2 n)
         (char= (char key n) #\[)
         (char= (char key (1- (length key))) #\])
         (every (lambda (c) (char<= #\0 c #\9)) (subseq key (1+ n) (1- (length key)))))))

(defun selfv-snap-apply-op (op entries)
  (ecase (first op)
    (:set (destructuring-bind (key value) (rest op)
            (if (assoc key entries :test #'string=)
                (mapcar (lambda (entry) (if (string= (car entry) key) (cons key value) entry))
                        entries)
                (append entries (list (cons key value))))))
    (:seq (destructuring-bind (prefix values) (rest op)
            (append (remove-if (lambda (entry) (selfv-snap-seq-key-p prefix (car entry))) entries)
                    (loop for value in values
                          for index from 0
                          collect (cons (format nil "~A[~D]" prefix index) value)))))))

(defun selfv-snap-fold (ops entries)
  (reduce (lambda (acc op) (selfv-snap-apply-op op acc)) ops :initial-value entries))

(defun selfv-snap-loaded (view disk)
  (if (eq view :unloaded) disk view))

(defun selfv-snap-touches-p (ops key)
  (some (lambda (op)
          (ecase (first op)
            (:set (string= (second op) key))
            (:seq (selfv-snap-seq-key-p (second op) key))))
        ops))

(defun selfv-snap-visible-p (op view)
  (ecase (first op)
    (:set (equal (assoc (second op) view :test #'string=) (cons (second op) (third op))))
    (:seq (equal (remove-if-not (lambda (entry) (selfv-snap-seq-key-p (second op) (car entry))) view)
                 (loop for value in (third op)
                       for index from 0
                       collect (cons (format nil "~A[~D]" (second op) index) value))))))

(defun selfv-snap-flushed (variant disk view ops)
  (cond ((null ops) disk)
        ((eq variant :flush-writes-view) view)
        (t (selfv-snap-fold ops disk))))

(defspec selfv-snapshot-session
    ((variant :correct)
     (ops-domain *selfv-default-snapshot-ops*)
     (max-staged 2))
  (:variables disk session view ops)
  (:init (disk nil) (session :none) (view :unloaded) (ops nil))

  (:action begin-session
    (:guard (eq session :none))
    (:next (session :open)))
  (:action stage-write
    (:for (op ops-domain))
    (:guard (and (eq session :open) (< (length ops) max-staged)))
    (:next (disk (if (eq variant :stage-writes-through) (selfv-snap-apply-op op disk) disk))
           (view (if (eq variant :stage-hides-write)
                     (selfv-snap-loaded view disk)
                     (selfv-snap-apply-op op (selfv-snap-loaded view disk))))
           (ops (append ops (list op)))))
  (:action read-view
    (:next (view (if (eq session :open) (selfv-snap-loaded view disk) view)))
    (:output (if (eq (next session) :open) (next view) (next disk))))
  (:action flush-session
    (:guard (eq session :open))
    (:next (disk (selfv-snap-flushed variant disk view ops))
           (view (if ops (selfv-snap-flushed variant disk view ops) view))
           (ops nil)))
  (:action end-session
    (:guard (eq session :open))
    (:next (disk (if (eq variant :end-discards-staged)
                     disk
                     (selfv-snap-flushed variant disk view ops)))
           (session :none)
           (view :unloaded)
           (ops nil)))
  (:action direct-write
    (:for (op ops-domain))
    (:guard (eq session :none))
    (:next (disk (selfv-snap-apply-op op disk))))
  (:action external-write
    (:for (op ops-domain))
    (:guard (eq session :open))
    (:next (disk (selfv-snap-apply-op op disk))))

  (:invariant staged-writes-need-open-session
    (or (null ops) (eq session :open)))
  (:invariant view-needs-open-session
    (or (eq view :unloaded) (eq session :open)))
  (:invariant staged-writes-have-loaded-view
    (or (null ops) (not (eq view :unloaded))))
  (:invariant last-staged-write-visible
    (or (null ops) (selfv-snap-visible-p (car (last ops)) view)))

  (:action-property staging-is-deferred
    (or (<= (length (next ops)) (length ops)) (equal (next disk) disk)))
  (:action-property flush-applies-staged-ops-to-current-disk
    (or (null ops) (next ops) (equal (next disk) (selfv-snap-fold ops disk))))
  (:action-property flush-keeps-unstaged-entries
    (or (null ops) (next ops)
        (every (lambda (entry)
                 (or (selfv-snap-touches-p ops (car entry))
                     (member entry (next disk) :test #'equal)))
               disk)))
  (:action-property flushed-view-is-disk
    (or (null ops) (next ops) (not (eq (next session) :open))
        (equal (next view) (next disk))))
  (:action-property ending-without-staged-writes-keeps-disk
    (or ops (not (eq session :open)) (eq (next session) :open)
        (equal (next disk) disk)))
  (:action-property disk-writes-are-attributed
    (or (equal (next disk) disk)
        (and ops (null (next ops)))
        (and (eq session :open) (eq (next session) :open) (equal ops (next ops)))
        (and (eq session :none) (eq (next session) :none)))))

(defparameter *selfv-snapshot-properties*
  '(staged-writes-need-open-session view-needs-open-session
    staged-writes-have-loaded-view last-staged-write-visible
    staging-is-deferred flush-applies-staged-ops-to-current-disk
    flush-keeps-unstaged-entries flushed-view-is-disk
    ending-without-staged-writes-keeps-disk disk-writes-are-attributed
    :deadlock))

;;; ------------------------------------------------------------------
;;; Snapshot system under test
;;; ------------------------------------------------------------------

(defstruct (selfv-snap-sut (:constructor make-selfv-snap-sut (directory bug)))
  directory bug (session nil))

(defun selfv-snap-in-env (sut thunk)
  (let ((cl-weave::*snapshot-directory* (selfv-snap-sut-directory sut))
        (cl-weave::*snapshot-file-name* "snapshots.sexp")
        (cl-weave::*update-snapshots* t)
        (cl-weave::*snapshot-session* (selfv-snap-sut-session sut)))
    (funcall thunk)))

(defun selfv-snap-write-op (sut op)
  "Stage OP when SUT has a session, write it through otherwise: the real
matcher entry points choose by the session special variable."
  (selfv-snap-in-env
   sut
   (lambda ()
     (ecase (first op)
       (:set (cl-weave::snapshot-match-or-update-p
              (parse-integer (third op)) (list (second op))))
       (:seq (cl-weave::snapshot-sequence-match-or-update-p
              (mapcar #'parse-integer (third op)) (list (second op)))))
     nil)))

(defun selfv-snap-external-write (sut op)
  "Write the snapshot file the way a second process would: at file level,
under the file lock, with no session involved."
  (selfv-snap-in-env
   (let ((copy (copy-selfv-snap-sut sut))) (setf (selfv-snap-sut-session copy) nil) copy)
   (lambda ()
     (let ((file (cl-weave::canonical-snapshot-file-pathname)))
       (cl-weave::call-with-snapshot-file-lock
        file
        (lambda ()
          (let ((entries (cl-weave::read-snapshot-file-unlocked file)))
            (cl-weave::write-snapshot-file-unlocked
             (ecase (first op)
               (:set (cl-weave::replace-snapshot-entry (second op) (third op) entries))
               (:seq (cl-weave::snapshot-sequence-replacement
                      (second op) (mapcar #'parse-integer (third op)) entries)))
             file)))))
     nil)))

(defun selfv-snap-read-view (sut)
  (selfv-snap-in-env sut (lambda () (copy-tree (cl-weave::snapshot-current-entries)))))

(defun selfv-snap-flush-with-view (session)
  "A broken flush: writes the session's own view over the file."
  (loop for session-file being the hash-values of (cl-weave::snapshot-session-files session)
        when (cl-weave::snapshot-session-file-dirty-p session-file)
          do (cl-weave::write-snapshot-file-unlocked
              (copy-tree (cl-weave::snapshot-session-file-entries session-file))
              (cl-weave::snapshot-session-file-file session-file))
             (setf (cl-weave::snapshot-session-file-operations session-file) nil
                   (cl-weave::snapshot-session-file-dirty-p session-file) nil)))

(defun selfv-snap-flush (sut)
  (let ((session (selfv-snap-sut-session sut)))
    (if (eq (selfv-snap-sut-bug sut) :flush-overwrites-with-view)
        (selfv-snap-flush-with-view session)
        (cl-weave::flush-snapshot-session session))
    nil))

(defun selfv-snap-begin (sut)
  (setf (selfv-snap-sut-session sut) (cl-weave::make-snapshot-session))
  nil)

(defun selfv-snap-end (sut)
  ;; Same two steps as the unwind-protect cleanup of CALL-WITH-SNAPSHOT-SESSION.
  (unless (eq (selfv-snap-sut-bug sut) :end-drops-session)
    (selfv-snap-flush sut))
  (setf (selfv-snap-sut-session sut) nil)
  nil)

(defun selfv-snap-model-op (operation)
  (ecase (first operation)
    (:replace (list :set (second operation) (third operation)))
    (:sequence (list :seq (second operation)
                     (mapcar (lambda (value) (format nil "~D" value)) (third operation))))))

(defun selfv-snap-abstraction (sut)
  (selfv-snap-in-env
   sut
   (lambda ()
     (let* ((session (selfv-snap-sut-session sut))
            (disk (copy-tree (cl-weave::read-snapshot-file-unlocked
                              (cl-weave::canonical-snapshot-file-pathname))))
            (files (when session
                     (loop for file being the hash-values of
                             (cl-weave::snapshot-session-files session)
                           collect file)))
            (single (and files (null (rest files)) (first files))))
       (list 'disk disk
             'session (if session :open :none)
             'view (cond ((null files) :unloaded)
                         ((rest files) (list :multiple-session-files (length files)))
                         (t (copy-tree (cl-weave::snapshot-session-file-entries single))))
             'ops (when single
                    (mapcar #'selfv-snap-model-op
                            (reverse (cl-weave::snapshot-session-file-operations single)))))))))

(defun selfv-snap-operations ()
  (list (cons 'begin-session #'selfv-snap-begin)
        (cons 'stage-write #'selfv-snap-write-op)
        (cons 'read-view #'selfv-snap-read-view)
        (cons 'flush-session #'selfv-snap-flush)
        (cons 'end-session #'selfv-snap-end)
        (cons 'direct-write #'selfv-snap-write-op)
        (cons 'external-write #'selfv-snap-external-write)))

(defun selfv-call-with-snap-suts (bug function)
  "Call FUNCTION with a RESET thunk that makes a fresh SUT in its own
directory and deletes the previous SUT's directory. Everything is deleted
on exit."
  (let ((root (selfv-make-temp-root))
        (count 0)
        (previous nil))
    (unwind-protect
         (funcall function
                  (lambda ()
                    (when previous (selfv-delete-tree (selfv-snap-sut-directory previous)))
                    (let ((directory (merge-pathnames (format nil "run-~D/" (incf count)) root)))
                      (ensure-directories-exist directory)
                      (setf previous (make-selfv-snap-sut directory bug)))))
      (selfv-delete-tree root))))

(defun selfv-check-snapshot-conformance (spec &rest options &key bug &allow-other-keys)
  (let ((options (loop for (key value) on options by #'cddr
                       unless (eq key :bug) append (list key value))))
    (selfv-call-with-snap-suts
     bug
     (lambda (reset)
       (apply #'check-sequential-conformance
              spec :reset reset :operations (selfv-snap-operations)
              :abstraction #'selfv-snap-abstraction options)))))


(defparameter *selfv-snapshot-conformance-ops*
  '((:set "a" "1") (:set "b" "1") (:seq "s" ()) (:seq "s" ("1" "2"))))

(defparameter *selfv-snapshot-overwrite-ops*
  '((:set "a" "1") (:set "a" "2")))

;;; ------------------------------------------------------------------
;;; Mock specification
;;; ------------------------------------------------------------------
;;;
;;; One target symbol, whose function cell holds FN: :original or the id of
;;; a spy. STACK lists the spy frames still registered for the symbol, newest
;;; first. SPIES holds (id status orig) per spy: the status is :new, :active,
;;; :restored (restore called, the frame may still be waiting on the stack
;;; under a newer active spy) or :disposed, and ORIG is what the function cell
;;; held when the spy was installed. PLAIN is an ordinary mock (:new, :live,
;;; :disposed) with CALLS recorded calls.
;;;
;;; Restoring pops every restored frame off the top of the stack, putting each
;;; frame's original back only while the function cell still holds that
;;; frame's mock. Disposing a spy whose frame is still on the stack fails, and
;;; so does disposing twice: the first dispose unregisters the mock.

(defun selfv-spy-status (spies id) (second (assoc id spies)))
(defun selfv-spy-orig (spies id) (third (assoc id spies)))

(defun selfv-put-spy (spies id status orig)
  (mapcar (lambda (entry) (if (eq (first entry) id) (list id status orig) entry)) spies))

(defun selfv-collapse (fn stack spies)
  (loop while (and stack (eq (selfv-spy-status spies (first stack)) :restored))
        do (let ((top (pop stack)))
             (when (eq fn top)
               (setf fn (selfv-spy-orig spies top)))))
  (list fn stack))

(defun selfv-restore (variant fn stack spies id)
  "Return (FN STACK SPIES) after restoring spy ID."
  (if (eq (selfv-spy-status spies id) :active)
      (let ((spies (selfv-put-spy spies id :restored (selfv-spy-orig spies id))))
        (if (eq variant :restore-skips-collapse)
            (list fn stack spies)
            (append (selfv-collapse fn stack spies) (list spies))))
      (list fn stack spies)))

(defspec selfv-mock-lifecycle
    ((variant :correct)
     (spy-ids (list :s1 :s2)))
  (:variables fn stack spies plain calls)
  (:init (fn :original) (stack nil)
         (spies (mapcar (lambda (id) (list id :new :none)) spy-ids))
         (plain :new) (calls 0))

  (:action spy-on
    (:for (id spy-ids))
    (:guard (eq (selfv-spy-status spies id) :new))
    (:next (fn id)
           (stack (cons id stack))
           (spies (selfv-put-spy spies id :active fn))))
  ;; Outputs depend only on constants: the sequential conformance check
  ;; evaluates an output with the wrong "from" state after the first step
  ;; (see the report notes), so each outcome is its own action.
  (:action restore-spy
    (:for (id spy-ids))
    (:guard (member (selfv-spy-status spies id) '(:active :restored)))
    (:next (fn (first (selfv-restore variant fn stack spies id)))
           (stack (second (selfv-restore variant fn stack spies id)))
           (spies (third (selfv-restore variant fn stack spies id))))
    (:output :ok))
  (:action restore-disposed-spy
    (:for (id spy-ids))
    (:guard (eq (selfv-spy-status spies id) :disposed))
    (:output :not-a-mock-error))
  (:action dispose-spy
    (:for (id spy-ids))
    (:guard (and (member (selfv-spy-status spies id) '(:active :restored))
                 (not (member id stack))))
    (:next (spies (selfv-put-spy spies id :disposed (selfv-spy-orig spies id))))
    (:output :ok))
  (:action dispose-active-spy
    (:for (id spy-ids))
    (:guard (and (member (selfv-spy-status spies id) '(:active :restored))
                 (member id stack)))
    (:next (spies (if (eq variant :dispose-ignores-residency)
                      (selfv-put-spy spies id :disposed (selfv-spy-orig spies id))
                      spies)))
    (:output (if (eq variant :dispose-ignores-residency) :ok :active-spy-error)))
  (:action dispose-disposed-spy
    (:for (id spy-ids))
    (:guard (eq (selfv-spy-status spies id) :disposed))
    (:output :not-a-mock-error))
  (:action make-plain
    (:guard (eq plain :new))
    (:next (plain :live)))
  (:action call-plain
    (:guard (and (eq plain :live) (< calls 2)))
    (:next (calls (1+ calls)))
    (:output :ok))
  (:action call-disposed-plain
    (:guard (eq plain :disposed))
    (:output :disposed-error))
  (:action clear-plain
    (:guard (eq plain :live))
    (:next (calls 0)))
  (:action dispose-plain
    (:guard (eq plain :live))
    (:next (plain :disposed)
           (calls (if (eq variant :dispose-keeps-history) calls 0)))
    (:output :ok))
  (:action dispose-disposed-plain
    (:guard (eq plain :disposed))
    (:output :not-a-mock-error))

  (:invariant disposed-not-resident
    (every (lambda (id) (not (eq (selfv-spy-status spies id) :disposed))) stack))
  (:invariant all-restored-means-original
    (or (some (lambda (entry) (eq (second entry) :active)) spies)
        (and (eq fn :original) (null stack))))
  (:invariant active-implies-resident
    (every (lambda (entry) (or (not (eq (second entry) :active)) (member (first entry) stack)))
           spies))
  (:invariant top-is-active
    (or (null stack) (eq (selfv-spy-status spies (first stack)) :active)))
  (:invariant fn-follows-stack
    (eq fn (if stack (first stack) :original)))
  (:invariant disposed-plain-has-no-history
    (or (not (member plain '(:new :disposed))) (zerop calls)))

  (:action-property disposed-spy-is-final
    (every (lambda (entry)
             (or (not (eq (second entry) :disposed))
                 (eq (selfv-spy-status (next spies) (first entry)) :disposed)))
           spies))
  (:action-property restored-spy-never-reactivates
    (every (lambda (entry)
             (or (not (eq (second entry) :restored))
                 (not (eq (selfv-spy-status (next spies) (first entry)) :active))))
           spies))
  (:action-property disposed-plain-is-final
    (or (not (eq plain :disposed)) (eq (next plain) :disposed))))

(defparameter *selfv-mock-properties*
  '(disposed-not-resident all-restored-means-original active-implies-resident
    top-is-active fn-follows-stack disposed-plain-has-no-history
    disposed-spy-is-final restored-spy-never-reactivates disposed-plain-is-final
    :deadlock))

;;; ------------------------------------------------------------------
;;; Mock system under test
;;; ------------------------------------------------------------------

(defstruct (selfv-handle (:constructor make-selfv-handle (mock state orig)))
  mock state orig)

(defstruct (selfv-mock-sut (:constructor %make-selfv-mock-sut (symbol original ids bug)))
  symbol original ids bug (spies nil) (plain nil) (plain-state nil))

(defun make-selfv-mock-sut (ids bug)
  (let ((original (lambda (&rest arguments) (declare (ignore arguments)) :original-function))
        (symbol (gensym "SELFV-TARGET-")))
    (setf (symbol-function symbol) original)
    (%make-selfv-mock-sut symbol original ids bug)))

(defun selfv-mock-function-id (sut function)
  (if (eq function (selfv-mock-sut-original sut))
      :original
      (or (car (find function (selfv-mock-sut-spies sut)
                     :key (lambda (entry) (selfv-handle-mock (cdr entry)))))
          :unknown)))

(defun selfv-mock-outcome (thunk)
  (handler-case (progn (funcall thunk) :ok)
    (cl-weave::active-spy-disposal-error () :active-spy-error)
    (cl-weave::mock-disposed-error () :disposed-error)
    (error (condition)
      (if (search "not a cl-weave mock function" (princ-to-string condition))
          :not-a-mock-error
          (error condition)))))

(defun selfv-mock-spy (sut id)
  (cdr (assoc id (selfv-mock-sut-spies sut))))

(defun selfv-mock-spy-on (sut id)
  (let* ((mock (cl-weave::spy-on (selfv-mock-sut-symbol sut)))
         (state (cl-weave::mock-state-for mock))
         (frame (cl-weave::mock-state-restore state)))
    (push (cons id (make-selfv-handle
                    mock state
                    (selfv-mock-function-id sut (cl-weave::spy-frame-original frame))))
          (selfv-mock-sut-spies sut))
    nil))

(defun selfv-mock-restore-spy (sut id)
  (selfv-mock-outcome
   (lambda () (cl-weave::mock-restore (selfv-handle-mock (selfv-mock-spy sut id))))))

(defun selfv-mock-dispose-spy (sut id)
  (let ((mock (selfv-handle-mock (selfv-mock-spy sut id))))
    (if (eq (selfv-mock-sut-bug sut) :dispose-forces)
        ;; Broken: an active spy is unregistered instead of rejected.
        (handler-case (progn (cl-weave::dispose-mock mock) :ok)
          (cl-weave::active-spy-disposal-error ()
            (remhash mock cl-weave::*mock-states*)
            :ok))
        (selfv-mock-outcome (lambda () (cl-weave::dispose-mock mock))))))

(defun selfv-mock-make-plain (sut)
  (let ((mock (cl-weave::make-mock-function)))
    (setf (selfv-mock-sut-plain sut) mock
          (selfv-mock-sut-plain-state sut) (cl-weave::mock-state-for mock))
    nil))

(defun selfv-mock-call-plain (sut)
  (let ((outcome (selfv-mock-outcome (lambda () (funcall (selfv-mock-sut-plain sut))))))
    (if (and (eq (selfv-mock-sut-bug sut) :disposed-call-succeeds)
             (eq outcome :disposed-error))
        :ok
        outcome)))

(defun selfv-mock-clear-plain (sut)
  (cl-weave::clear-mock (selfv-mock-sut-plain sut))
  nil)

(defun selfv-mock-dispose-plain (sut)
  (selfv-mock-outcome (lambda () (cl-weave::dispose-mock (selfv-mock-sut-plain sut)))))

(defun selfv-mock-spy-entry (sut id)
  (let ((spy (selfv-mock-spy sut id)))
    (if (null spy)
        (list id :new :none)
        (list id
              (cond ((not (cl-weave::mock-function-p (selfv-handle-mock spy))) :disposed)
                    ((cl-weave::mock-state-restore (selfv-handle-state spy)) :active)
                    (t :restored))
              (selfv-handle-orig spy)))))

(defun selfv-mock-abstraction (sut)
  (let* ((symbol (selfv-mock-sut-symbol sut))
         (plain (selfv-mock-sut-plain sut))
         (plain-state (selfv-mock-sut-plain-state sut)))
    (list 'fn (selfv-mock-function-id sut (symbol-function symbol))
          'stack (mapcar (lambda (frame)
                           (selfv-mock-function-id sut (cl-weave::spy-frame-mock frame)))
                         (gethash symbol cl-weave::*spy-stacks*))
          'spies (mapcar (lambda (id) (selfv-mock-spy-entry sut id)) (selfv-mock-sut-ids sut))
          'plain (cond ((null plain) :new)
                       ((cl-weave::mock-function-p plain) :live)
                       (t :disposed))
          'calls (if plain-state (fill-pointer (cl-weave::mock-state-calls plain-state)) 0))))

(defun selfv-mock-operations ()
  (list (cons 'spy-on #'selfv-mock-spy-on)
        (cons 'restore-spy #'selfv-mock-restore-spy)
        (cons 'restore-disposed-spy #'selfv-mock-restore-spy)
        (cons 'dispose-spy #'selfv-mock-dispose-spy)
        (cons 'dispose-active-spy #'selfv-mock-dispose-spy)
        (cons 'dispose-disposed-spy #'selfv-mock-dispose-spy)
        (cons 'make-plain #'selfv-mock-make-plain)
        (cons 'call-plain #'selfv-mock-call-plain)
        (cons 'call-disposed-plain #'selfv-mock-call-plain)
        (cons 'clear-plain #'selfv-mock-clear-plain)
        (cons 'dispose-plain #'selfv-mock-dispose-plain)
        (cons 'dispose-disposed-plain #'selfv-mock-dispose-plain)))

(defun selfv-mock-discard (sut)
  (let ((symbol (selfv-mock-sut-symbol sut)))
    (dolist (entry (selfv-mock-sut-spies sut))
      (ignore-errors (cl-weave::mock-restore (selfv-handle-mock (cdr entry)))))
    (dolist (entry (selfv-mock-sut-spies sut))
      (ignore-errors (cl-weave::dispose-mock (selfv-handle-mock (cdr entry)))))
    (when (selfv-mock-sut-plain sut)
      (ignore-errors (cl-weave::dispose-mock (selfv-mock-sut-plain sut))))
    (remhash symbol cl-weave::*spy-stacks*)
    (fmakunbound symbol)))

(defun selfv-check-mock-conformance (spec &rest options &key bug (ids (list :s1 :s2))
                                          &allow-other-keys)
  (let ((previous nil)
        (options (loop for (key value) on options by #'cddr
                       unless (member key '(:bug :ids)) append (list key value))))
    (unwind-protect
         (apply #'check-sequential-conformance
                spec
                :reset (lambda ()
                         (when previous (selfv-mock-discard previous))
                         (setf previous (make-selfv-mock-sut ids bug)))
                :operations (selfv-mock-operations)
                :abstraction #'selfv-mock-abstraction
                options)
      (when previous (selfv-mock-discard previous)))))

;;; ------------------------------------------------------------------
;;; Helpers for the tests
;;; ------------------------------------------------------------------

(defun selfv-violation-summary (result)
  "List of (kind property trace-length trace-actions) of RESULT's violation."
  (let ((violation (spec-result-violation result)))
    (when violation
      (list (spec-violation-kind violation)
            (spec-violation-property violation)
            (length (spec-violation-trace violation))
            (mapcar #'trace-step-action (spec-violation-trace violation))))))

(defun selfv-snap-file-entries ()
  (cl-weave::read-snapshot-file-unlocked (cl-weave::snapshot-file-pathname)))

(defun selfv-call-with-snap-directory (function)
  (let ((root (selfv-make-temp-root)))
    (unwind-protect
         (let ((cl-weave::*snapshot-directory* root)
               (cl-weave::*snapshot-file-name* "snapshots.sexp")
               (cl-weave::*update-snapshots* t)
               (cl-weave::*snapshot-session* nil))
           (funcall function))
      (selfv-delete-tree root))))

;;; ------------------------------------------------------------------
;;; Snapshot tests
;;; ------------------------------------------------------------------

(describe "self-verification of the snapshot session"
  (it-spec "satisfies every staging and flush property over all reachable states"
    (explore-spec (selfv-snapshot-session) :max-states 100000))

  (it "checks every declared property and does not truncate"
    (let ((result (explore-spec (selfv-snapshot-session) :max-states 100000)))
      (expect (spec-result-truncated result) :to-be nil)
      (expect (spec-result-checked-properties result) :to-equal *selfv-snapshot-properties*)
      (expect (> (spec-result-states-found result) 100) :to-be t)))

  (it "reaches exactly the nine hand-counted states of the one-operation model"
    ;; none: disk empty or holding a=1 (2). open, nothing staged: disk empty
    ;; with view unloaded or empty; disk a=1 with view unloaded, empty (stale)
    ;; or a=1 (5). open with a staged write: view a=1 with disk empty or
    ;; a=1 (2).
    (let ((result (explore-spec (selfv-snapshot-session
                                 :ops-domain (list (list :set "a" "1")) :max-staged 1))))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-states-found result) :to-be 9)))

  (it "detects a write that reaches the disk before the flush"
    (expect (selfv-violation-summary
             (explore-spec (selfv-snapshot-session :variant :stage-writes-through)
                           :max-states 100000))
            :to-equal '(:action-property staging-is-deferred 3
                        (nil begin-session stage-write))))

  (it "detects a staged write the session cannot read back"
    (expect (selfv-violation-summary
             (explore-spec (selfv-snapshot-session :variant :stage-hides-write)
                           :max-states 100000))
            :to-equal '(:invariant last-staged-write-visible 3
                        (nil begin-session stage-write))))

  (it "detects a flush that overwrites another writer's changes"
    (expect (selfv-violation-summary
             (explore-spec (selfv-snapshot-session :variant :flush-writes-view)
                           :max-states 100000))
            :to-equal '(:action-property flush-applies-staged-ops-to-current-disk 5
                        (nil begin-session stage-write external-write flush-session))))

  (it "detects a session that ends without flushing"
    (expect (selfv-violation-summary
             (explore-spec (selfv-snapshot-session :variant :end-discards-staged)
                           :max-states 100000))
            :to-equal '(:action-property flush-applies-staged-ops-to-current-disk 4
                        (nil begin-session stage-write end-session))))

  (it-spec "matches the real session in random conformance runs"
    (selfv-check-snapshot-conformance
     (selfv-snapshot-session :ops-domain *selfv-snapshot-conformance-ops*)
     :mode :random :seed 20 :runs 150 :max-steps 14))

  ;; The operation tree has loops (reads, repeated writes), so it is cut at the
  ;; depth bound by design and the bound is accepted explicitly.
  (it-spec "matches the real session on every path of the operation tree up to depth seven"
    (selfv-check-snapshot-conformance
     (selfv-snapshot-session :ops-domain (list (list :set "a" "1") (list :seq "s" (list "1" "2")))
                             :max-staged 2)
     :mode :tree :depth 7 :max-states 100000 :allow-bounded t))


  (it-spec "matches the real session when a staged write changes an existing value"
    (selfv-check-snapshot-conformance
     (selfv-snapshot-session :ops-domain *selfv-snapshot-overwrite-ops*)
     :mode :tree :depth 4 :max-states 100000 :allow-bounded t))

  (it "detects a real session that drops staged writes when it closes"
    (let* ((result (selfv-check-snapshot-conformance
                    (selfv-snapshot-session :ops-domain *selfv-snapshot-conformance-ops*)
                    :bug :end-drops-session :mode :random :seed 20 :runs 150 :max-steps 14))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (getf detail :action) :to-be 'end-session)
      (expect (getf detail :what) :to-be :state)
      (expect (getf detail :step) :to-be (1- (length (spec-violation-trace violation))))
      (expect (mapcar #'trace-step-action (last (spec-violation-trace violation) 3))
              :to-equal '(begin-session stage-write end-session))
      (expect (getf (getf detail :expected) 'session) :to-be :none)))

  (it "detects a real flush that overwrites a concurrent file change"
    (let* ((result (selfv-check-snapshot-conformance
                    (selfv-snapshot-session :ops-domain *selfv-snapshot-conformance-ops*)
                    :bug :flush-overwrites-with-view :mode :random :seed 20 :runs 400 :max-steps 14))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (getf detail :what) :to-be :state)
      (expect (member (getf detail :action) '(flush-session end-session)) :to-be-truthy)
      (expect (find 'external-write (spec-violation-trace violation)
                    :key #'trace-step-action)
              :to-be-truthy)))

  (it "flushes staged writes when the session scope exits with an error"
    (selfv-call-with-snap-directory
     (lambda ()
       (handler-case
           (cl-weave::call-with-snapshot-session
            (lambda ()
              (cl-weave::snapshot-match-or-update-p 1 (list "a"))
              (expect (selfv-snap-file-entries) :to-be nil)
              (error "abort the scope")))
         (error () nil))
       (expect (selfv-snap-file-entries) :to-equal '(("a" . "1"))))))

  (it "lets a nested scope share the outer session and flush only at the outer exit"
    (selfv-call-with-snap-directory
     (lambda ()
       (cl-weave::call-with-snapshot-session
        (lambda ()
          (let ((outer cl-weave::*snapshot-session*))
            (cl-weave::call-with-snapshot-session
             (lambda ()
               (expect cl-weave::*snapshot-session* :to-be outer)
               (cl-weave::snapshot-match-or-update-p 1 (list "a"))))
            (expect (selfv-snap-file-entries) :to-be nil))))
       (expect (selfv-snap-file-entries) :to-equal '(("a" . "1"))))))

  (it "keeps an empty session from creating the snapshot file"
    (selfv-call-with-snap-directory
     (lambda ()
       (cl-weave::call-with-snapshot-session (lambda () nil))
       (expect (probe-file (cl-weave::snapshot-file-pathname)) :to-be nil)))))

;;; ------------------------------------------------------------------
;;; Mock tests
;;; ------------------------------------------------------------------

(describe "self-verification of the mock lifecycle"
  (it-spec "satisfies every restore and dispose property over all reachable states"
    (explore-spec (selfv-mock-lifecycle) :max-states 100000))

  (it "checks every declared property and does not truncate"
    (let ((result (explore-spec (selfv-mock-lifecycle) :max-states 100000)))
      (expect (spec-result-truncated result) :to-be nil)
      (expect (spec-result-checked-properties result) :to-equal *selfv-mock-properties*)
      (expect (> (spec-result-states-found result) 100) :to-be t)))

  (it "reaches exactly the twenty hand-counted states of the one-spy model"
    ;; Spy: unused, active (on the stack), restored (collapsed), disposed.
    ;; Plain mock: unused, live with 0, 1 or 2 calls, disposed. 4 x 5.
    (let ((result (explore-spec (selfv-mock-lifecycle :spy-ids (list :s1)))))
      (expect (spec-result-passed-p result) :to-be t)
      (expect (spec-result-states-found result) :to-be 20)))

  (it "detects a dispose that succeeds while the spy is still installed"
    (expect (selfv-violation-summary
             (explore-spec (selfv-mock-lifecycle :variant :dispose-ignores-residency)
                           :max-states 100000))
            :to-equal '(:invariant disposed-not-resident 3 (nil spy-on dispose-active-spy))))

  (it "detects a restore that leaves the spy installed"
    (expect (selfv-violation-summary
             (explore-spec (selfv-mock-lifecycle :variant :restore-skips-collapse)
                           :max-states 100000))
            :to-equal '(:invariant all-restored-means-original 3 (nil spy-on restore-spy))))

  (it "detects a dispose that keeps the call history"
    (expect (selfv-violation-summary
             (explore-spec (selfv-mock-lifecycle :variant :dispose-keeps-history)
                           :max-states 100000))
            :to-equal '(:invariant disposed-plain-has-no-history 4
                        (nil make-plain call-plain dispose-plain))))

  (it-spec "matches the real mocks in random conformance runs"
    (selfv-check-mock-conformance
     (selfv-mock-lifecycle) :mode :random :seed 7 :runs 300 :max-steps 16))

  (it-spec "matches the real mocks on every path of the operation tree up to depth eight"
    (selfv-check-mock-conformance
     (selfv-mock-lifecycle :spy-ids (list :s1 :s2))
     :mode :tree :depth 8 :max-states 100000 :allow-bounded t))

  (it "detects a real dispose that unregisters an installed spy"
    (let* ((result (selfv-check-mock-conformance
                    (selfv-mock-lifecycle)
                    :bug :dispose-forces :mode :random :seed 7 :runs 300 :max-steps 16))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (getf detail :action) :to-be 'dispose-active-spy)
      (expect (getf detail :what) :to-be :state)
      (expect (getf detail :step) :to-be 2)
      (expect (mapcar #'trace-step-action (spec-violation-trace violation))
              :to-equal '(nil spy-on dispose-active-spy))))

  (it "detects a real call on a disposed mock that succeeds"
    (let* ((result (selfv-check-mock-conformance
                    (selfv-mock-lifecycle)
                    :bug :disposed-call-succeeds :mode :random :seed 7 :runs 300 :max-steps 16))
           (violation (spec-result-violation result))
           (detail (spec-violation-detail violation)))
      (expect (spec-violation-kind violation) :to-be :conformance)
      (expect (getf detail :action) :to-be 'call-disposed-plain)
      (expect (getf detail :what) :to-be :output)
      (expect (getf detail :expected) :to-be :disposed-error)
      (expect (getf detail :actual) :to-be :ok)
      (expect (mapcar #'trace-step-action (spec-violation-trace violation))
              :to-equal '(nil make-plain dispose-plain call-disposed-plain))))

  (it "leaves no spy stack or mock registration behind"
    (let ((stacks (hash-table-count cl-weave::*spy-stacks*))
          (mocks (hash-table-count cl-weave::*mock-states*)))
      (selfv-check-mock-conformance
       (selfv-mock-lifecycle) :mode :random :seed 3 :runs 40 :max-steps 12)
      (expect (hash-table-count cl-weave::*spy-stacks*) :to-be stacks)
      (expect (hash-table-count cl-weave::*mock-states*) :to-be mocks))))
