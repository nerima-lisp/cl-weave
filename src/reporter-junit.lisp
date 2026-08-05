(in-package #:cl-weave)

(defun junit-classname (path)
  (dotted-path-string (butlast path)))

(defun junit-test-name (path)
  (or (car (last path)) "anonymous"))

(defun write-junit-child-element (stream tag message &optional body)
  "Write a JUnit XML child element named TAG with a message attribute.
Writes a self-closing element unless BODY is supplied, in which case BODY
becomes the escaped element text content."
  (if body
      (format stream "    <~A message=\"~A\">~A</~A>~%"
              tag (xml-escaped-string message) (xml-escaped-string body) tag)
      (format stream "    <~A message=\"~A\"/>~%"
              tag (xml-escaped-string message))))

(defun report-junit-event (event stream)
  (let ((status (test-event-status event)))
    (format stream "  <testcase classname=\"~A\" name=\"~A\" time=\"~,3F\">~%"
            (xml-escaped-string (junit-classname (test-event-path event)))
            (xml-escaped-string (junit-test-name (test-event-path event)))
            (event-duration-seconds event))
    (ecase status
      (:pass)
      (:skip
       (write-junit-child-element stream "skipped" (event-message event)))
      (:todo
       (write-junit-child-element
        stream "skipped" (format nil "TODO: ~A" (event-message event))))
      (:fail
       (write-junit-child-element
        stream "failure" (event-message event) (event-detail-string event)))
      (:error
       (write-junit-child-element
        stream "error" (event-message event) (event-detail-string event))))
    (format stream "  </testcase>~%")))

(defun report-junit (events stream)
  (let ((summary (result-summary events))
        (duration (reduce #'+ events :key #'event-duration-seconds
                                      :initial-value 0.0d0)))
    (format stream "<?xml version=\"1.0\" encoding=\"UTF-8\"?>~%")
    (format stream "<testsuite name=\"cl-weave\" tests=\"~D\" failures=\"~D\" ~
                    errors=\"~D\" skipped=\"~D\" time=\"~,3F\">~%"
            (getf summary :total)
            (getf summary :failed)
            (getf summary :errored)
            (+ (getf summary :skipped) (getf summary :todos))
            duration)
    (dolist (event events)
      (report-junit-event event stream))
    (format stream "</testsuite>~%")
    (values)))
