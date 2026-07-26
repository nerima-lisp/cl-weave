(in-package #:cl-weave/test)

(cl-weave:clear-tests)

(defun add-tripwire-test-case (suite flag-setter)
  "Register a test case named \"must not run\" under SUITE that calls
FLAG-SETTER if it ever executes; used to assert a test is skipped entirely."
  (cl-weave::add-child
   suite
   (cl-weave::make-test-case :name "must not run" :function flag-setter)))

(defun ensure-directory-suffix (value)
  (let ((string (namestring (pathname value))))
    (if (and (plusp (length string))
             (char= (char string (1- (length string))) #\/))
        string
        (concatenate 'string string "/"))))

(defun usable-temporary-root-p (value)
  (and value
       (plusp (length value))
       (not (search "/homeless-shelter" value))))

(defun test-temporary-root ()
  (let* ((tmp #+sbcl (sb-ext:posix-getenv "TMPDIR")
              #-sbcl nil)
         (nix-build-top #+sbcl (sb-ext:posix-getenv "NIX_BUILD_TOP")
                        #-sbcl nil)
         (pwd #+sbcl (sb-ext:posix-getenv "PWD")
              #-sbcl nil)
         (cwd (ignore-errors (namestring (uiop:getcwd))))
         (root (find-if #'usable-temporary-root-p
                        (list nix-build-top pwd tmp cwd))))
    (unless root
      (error "No usable temporary root is available."))
    (pathname (ensure-directory-suffix root))))

(defun json-escaped-output-safe-p (escaped)
  "True when ESCAPED contains no raw double-quote or control character
outside of a recognized backslash escape sequence."
  (let ((length (length escaped)))
    (loop with index = 0
          while (< index length)
          for char = (char escaped index)
          do (cond
               ((char= char #\\)
                (let ((next (and (< (1+ index) length) (char escaped (1+ index)))))
                  (unless (member next '(#\" #\\ #\/ #\b #\t #\n #\f #\r #\u))
                    (return-from json-escaped-output-safe-p nil))
                  (incf index (if (eql next #\u) 6 2))))
               ((or (char= char #\") (< (char-code char) 32))
                (return-from json-escaped-output-safe-p nil))
               (t (incf index)))
          finally (return t))))

(defun xml-escaped-output-safe-p (escaped)
  "True when ESCAPED contains no raw <, >, &, \", or ' character outside of
a recognized XML entity reference."
  (let ((length (length escaped)))
    (loop with index = 0
          while (< index length)
          for char = (char escaped index)
          do (cond
               ((char= char #\&)
                (let ((entity (find-if (lambda (candidate)
                                         (let ((end (+ index (length candidate))))
                                           (and (<= end length)
                                                (string= escaped candidate
                                                        :start1 index :end1 end))))
                                       '("&lt;" "&gt;" "&amp;" "&quot;" "&apos;"))))
                  (unless entity
                    (return-from xml-escaped-output-safe-p nil))
                  (incf index (length entity))))
               ((member char '(#\< #\> #\" #\'))
                (return-from xml-escaped-output-safe-p nil))
               (t (incf index)))
          finally (return t))))

(defun find-metadata-entry (plist-key value entries)
  "Return the plist in ENTRIES whose PLIST-KEY value is string= to VALUE."
  (find value entries :key (lambda (entry) (getf entry plist-key)) :test #'string=))

(defun test-snapshot-directory (name)
  (merge-pathnames
   (make-pathname :directory (list :relative name))
   (test-temporary-root)))

(defun test-temporary-pathname (name)
  (merge-pathnames
   name
   (test-temporary-root)))

(defun make-test-temporary-directory (prefix)
  (loop repeat 100
        for directory = (merge-pathnames
                         (make-pathname
                          :directory
                          (list :relative
                                (format nil "~A-~36R-~36R"
                                        prefix
                                        (get-universal-time)
                                        (random (expt 36 6)))))
                         (test-temporary-root))
        unless (probe-file directory)
          do (ensure-directories-exist (merge-pathnames #P".keep" directory))
             (return directory)
        finally (error "Failed to allocate test temporary directory for ~A." prefix)))

(defun read-text-file (pathname)
  (with-open-file (stream pathname :direction :input)
    (let ((contents (make-string (file-length stream))))
      (read-sequence contents stream)
      contents)))

(defun collapse-normalized-text (text ignored-characters)
  (with-output-to-string (stream)
    (loop with spacing = t
          for character across text
          do (cond
               ((member character ignored-characters)
                nil)
               ((member character '(#\Newline #\Tab #\Return #\Space))
                (unless spacing
                  (write-char #\Space stream)
                  (setf spacing t)))
               (t
                (write-char character stream)
                (setf spacing nil))))))

(defun normalize-shell-text (text)
  (collapse-normalized-text text '(#\')))

(defun normalize-markdown-text (text)
  (labels ((tight-punctuation-p (character)
             (member character '(#\, #\. #\: #\; #\) #\]))))
    (let* ((collapsed (string-trim '(#\Space)
                                   (collapse-normalized-text text '(#\`)))))
      (with-output-to-string (stream)
        (loop for index from 0 below (length collapsed)
              for character = (char collapsed index)
              for next = (and (< (1+ index) (length collapsed))
                              (char collapsed (1+ index)))
              unless (and (char= character #\Space)
                          next
                          (tight-punctuation-p next))
                do (write-char character stream))))))

(defun workflow-command-string (command)
  (format nil "~{~A~^ ~}" command))

(defun parse-cli (arguments)
  "Parse ARGUMENTS into a fresh CLI options record."
  (cl-weave/cli::parse-cli-arguments arguments (cl-weave/cli::make-cli-options)))

(defun framework-metadata-output (options)
  "Capture the framework metadata report for OPTIONS as a string."
  (with-output-to-string (stream)
    (cl-weave/cli::report-framework-metadata options stream)))

(defun make-sample-event (&rest initargs)
  "Build a test event for reporter tests, defaulting elapsed time to zero."
  (apply #'cl-weave::make-test-event
         (append initargs (list :elapsed-internal-time 0))))

(defun normalize-command-document-text (text)
  (collapse-normalized-text text '(#\`)))

(defun split-normalized-words (text)
  (remove ""
          (uiop:split-string text :separator '(#\Space))
          :test #'string=))

(defun ordered-word-subsequence-p (needle haystack)
  (loop with haystack-length = (length haystack)
        with position = 0
        for word in needle
        do (loop while (and (< position haystack-length)
                            (not (string= word (nth position haystack))))
                 do (incf position))
           (when (>= position haystack-length)
             (return-from ordered-word-subsequence-p nil))
           (incf position)
        finally (return t)))

(defun markdown-contains-command-p (markdown command)
  (ordered-word-subsequence-p
   (split-normalized-words
    (normalize-shell-text (workflow-command-string command)))
   (split-normalized-words
    (normalize-command-document-text markdown))))

(defvar *fixture-value* nil)
(defvar *fixture-events* nil)
(defun sample-size (value) (length value))

(defclass sample-widget ()
  ((name :initarg :name :reader sample-widget-name)
   (state :initarg :state :initform :new :reader sample-widget-state)))

(defun sample-widget-render-value (widget)
  (sample-widget-name widget))

(defgeneric render-widget (widget stream))

(defmethod render-widget ((widget sample-widget) stream)
  (declare (ignore stream))
  (sample-widget-render-value widget))

(defgeneric render-widget-mode (mode stream))

(defmethod render-widget-mode ((mode (eql :preview)) stream)
  (declare (ignore stream))
  mode)

(defmethod render-widget-mode ((mode sample-widget) stream)
  (declare (ignore stream))
  (sample-widget-render-value mode))

(defmacro sample-unless (condition &body body)
  `(if ,condition
       nil
       (progn ,@body)))

(defmacro matcher-pass-cases (&body cases)
  `(progn
     ,@(loop for (name form) in cases
             collect `(it ,name ,form))))

(defmacro with-assertion-detail ((detail condition &optional actual expected)
                                 &body assertions)
  "Bind the structured payload of an expected assertion failure."
  `(let* ((,detail (cl-weave::failure-detail ,condition))
          ,@(when actual
              `((,actual (cl-weave::assertion-detail-actual ,detail))))
          ,@(when expected
              `((,expected (cl-weave::assertion-detail-expected ,detail)))))
     ,@assertions))

(defmacro with-captured-output ((output stream &key stop-tag) &body body)
  "Capture BODY output in OUTPUT using STREAM.
When STOP-TAG is provided, wrap BODY in a CATCH for that tag."
  `(setf ,output
         (with-output-to-string (,stream)
           ,(if stop-tag
                `(catch ,stop-tag ,@body)
                `(progn ,@body)))))

(defun tree-contains-p (tree value)
  (cond
    ((equal tree value) t)
    ((consp tree)
     (or (tree-contains-p (car tree) value)
         (tree-contains-p (cdr tree) value)))
    (t nil)))

#+sbcl
(defun quiet-nan ()
  (sb-kernel:make-double-float #x7ff80000 0))

(defun tree-depth (tree)
  (if (consp tree)
      (1+ (reduce #'max tree :key #'tree-depth :initial-value 0))
      0))

(defun parity-match-values (actual predicate matching-parity opposite-parity)
  (let ((matches (and (integerp actual) (funcall predicate actual))))
    (values matches
            `(:value ,actual :parity ,(if matches matching-parity opposite-parity))
            `(:parity ,matching-parity))))

(defmatcher :to-be-even (actual expected)
  "Passes when ACTUAL is an even integer."
  (declare (ignore expected))
  (parity-match-values actual #'evenp :even :odd))

(expect-extend
  (:to-be-odd (actual expected)
    "Passes when ACTUAL is an odd integer."
    (declare (ignore expected))
    (parity-match-values actual #'oddp :odd :even)))

(extend-expect
  (list
  (list :to-be-between
        (lambda (actual expected)
          (destructuring-bind (low high) expected
            (values (and (realp actual) (<= low actual high))
                    `(:value ,actual :range (,low ,high))
                    `(:range (,low ,high)))))
        :description
        "Passes when ACTUAL is within the inclusive numeric range.")))
