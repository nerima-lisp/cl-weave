(in-package #:cl-weave/test)

(defun workflow-step-blocks (workflow)
  (loop with marker = "      - name:"
        with length = (length workflow)
        for start = (search marker workflow)
          then (and end (search marker workflow :start2 end))
        while start
        for end = (or (search marker workflow :start2 (+ start (length marker)))
                      length)
        collect (subseq workflow start end)))

(defun workflow-artifact-section (workflow)
  (let ((section-position (search "path: |" workflow)))
    (if section-position
        (subseq workflow section-position)
        "")))

(defun flake-check-names (flake)
  (loop with marker = " = mkCheck {"
        for line in (uiop:split-string flake :separator '(#\Newline))
        for trimmed = (string-trim '(#\Space #\Tab) line)
        for position = (search marker trimmed)
        when position
          collect (subseq trimmed 0 position)))

(defun packaged-cli-initializes-output-translations-p (flake)
  (not (null
        (search
         "(asdf:initialize-output-translations (quote (:output-translations (t (:home \".cache\" \"common-lisp\" :implementation)) :ignore-inherited-configuration)))"
         flake
         :test (function char=)))))

(defun workflow-action-reference (line)
  (let ((uses-position (search "uses:" line)))
    (when uses-position
      (let* ((reference-start (+ uses-position (length "uses:")))
             (comment-position (position #\# line :start reference-start))
             (reference-end (or comment-position (length line))))
        (string-trim (list #\Space #\Tab)
                     (subseq line reference-start reference-end))))))

(defun workflow-remote-action-lines (workflow)
  (loop for line in (uiop:split-string workflow :separator (list #\Newline))
        for reference = (workflow-action-reference line)
        when (and reference
                  (position #\@ reference)
                  (not (uiop:string-prefix-p "./" reference)))
          collect line))

(defun workflow-action-immutably-pinned-p (line)
  (let* ((reference (workflow-action-reference line))
         (at-position (and reference (position #\@ reference :from-end t)))
         (revision (and at-position (subseq reference (1+ at-position)))))
    (and revision
         (= (length revision) 40)
         (every (lambda (character)
                  (or (digit-char-p character)
                      (find character "abcdef" :test (function char=))))
                revision))))

(defun workflow-step-for-name (workflow name)
  (let ((marker (format nil "- name: ~A" name)))
    (find-if (lambda (step)
               (search marker step))
             (workflow-step-blocks workflow))))

(defun workflow-job-block (workflow name)
  (let* ((marker (format nil "~%  ~A:~%" name))
         (job-indent (format nil "~%  "))
         (start (search marker workflow)))
    (when start
      (let* ((contents-start (+ start (length marker)))
             (end
               (loop for candidate = (search job-indent workflow
                                             :start2 contents-start)
                       then (search job-indent workflow
                                    :start2 (1+ candidate))
                     while candidate
                     when (let ((name-start (+ candidate (length job-indent))))
                            (and (< name-start (length workflow))
                                 (not (member (char workflow name-start)
                                              (list #\Space #\Tab)))))
                       return candidate
                     finally (return (length workflow)))))
        (subseq workflow start end)))))

(defun workflow-job-preamble (workflow name)
  (let ((job (workflow-job-block workflow name)))
    (when job
      (let ((steps-position (search "    steps:" job)))
        (subseq job 0 (or steps-position (length job)))))))

(defparameter +nix-setup-action-path+
  #P".github/actions/nix-setup/action.yml"
  "Composite action that every workflow delegates Nix/Cachix setup to. The name
is fixed by the nerima-lisp package standard, and the Cachix pull-vs-push gating
lives here so the workflows share one source.")

(defun action-step-blocks (action)
  "Split a composite-action body into per-step blocks. Composite-action steps are
indented two columns less than workflow-job steps (`    - name:` vs `      - name:`)."
  (loop with marker = "    - name:"
        with length = (length action)
        for start = (search marker action)
          then (and end (search marker action :start2 end))
        while start
        for end = (or (search marker action :start2 (+ start (length marker)))
                      length)
        collect (subseq action start end)))

(defun action-step-for-name (action name)
  (let ((marker (format nil "- name: ~A" name)))
    (find-if (lambda (step)
               (search marker step))
             (action-step-blocks action))))

(defun ci-templated-artifact-bundle (ci)
  "The metadata artifact-bundle name with its concrete system replaced by the
workflow matrix template, so the contract accepts the matrix-ready workflow while
staying derived from the metadata (bundle name + declared system)."
  (let* ((bundle (getf ci :artifact-bundle))
         (system (first (getf ci :systems)))
         (position (and system (search system bundle))))
    (if position
        (concatenate 'string
                     (subseq bundle 0 position)
                     "${{ matrix.system }}"
                     (subseq bundle (+ position (length system))))
        bundle)))
