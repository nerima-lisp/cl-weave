(in-package #:cl-weave/test)

(describe "CI reporters"
  (it "prints CI-readable JUnit XML results"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-junit
                     (list (make-sample-event
                            :status :pass
                            :path '("reporters" "passes"))
                           (make-sample-event
                            :status :skip
                            :path '("reporters" "skips")
                            :reason "needs <thing>")
                           (make-sample-event
                            :status :todo
                            :path '("reporters" "todos")
                            :reason "pending")
                           (make-sample-event
                            :status :fail
                            :path '("reporters" "fails")
                            :reason "bad <value> & reason"
                            :condition "primary"
                            :secondary-conditions '("cleanup <one>" "cleanup & two")))
                     stream))))
        (expect output :to-contain "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        (expect output :to-contain "<testsuite name=\"cl-weave\" tests=\"4\"")
        (expect output :to-contain "failures=\"1\"")
        (expect output :to-contain "errors=\"0\"")
        (expect output :to-contain "skipped=\"2\"")
        (expect output :to-contain "time=\"0.000\"")
        (expect output :to-contain "<skipped message=\"needs &lt;thing&gt;\"/>")
        (expect output :to-contain "<skipped message=\"TODO: pending\"/>")
        (expect output :to-contain "<failure message=\"bad &lt;value&gt; &amp; reason\">")
        (expect output :to-contain
                (format nil "secondary condition: cleanup &lt;one&gt;~%secondary condition: cleanup &amp; two"))))

  (it "sanitizes JUnit XML strings with portable control-character rules"
    (let ((escaped (cl-weave::xml-escaped-string
                    (coerce (list #\< #\> #\& #\"
                                  (code-char 39)
                                  (code-char 9)
                                  (code-char 10)
                                  (code-char 13)
                                  (code-char 1))
                            (quote string)))))
      (expect escaped :to-equal
              (concatenate (quote string)
                           "&lt;"
                           "&gt;"
                           "&amp;"
                           "&quot;"
                           "&apos;"
                           (string (code-char 9))
                           (string (code-char 10))
                           (string (code-char 13))
                           "?"))))

  (it "replaces XML 1.0 noncharacters when representable"
    (dolist (code '(#xfffe #xffff))
      (let ((character (code-char code)))
        (when character
          (expect (cl-weave::xml-escaped-string (string character))
                  :to-equal "?")))))

  (it "replaces characters outside the valid XML 1.0 range with ?"
    (let ((escaped (cl-weave::xml-escaped-string
                    (coerce (list #\A
                                  (code-char #xd800)
                                  (code-char #xdfff)
                                  (code-char #xfffe)
                                  (code-char #xffff)
                                  (code-char #x2603)
                                  (code-char #x1f600))
                            'string))))
      (expect escaped :to-equal
              (concatenate 'string
                           "A"
                           "?"
                           "?"
                           "?"
                           "?"
                           (string (code-char #x2603))
                           (string (code-char #x1f600))))))

  (it-fuzz "escapes arbitrary strings into XML with no raw markup character"
      ((text (gen-string
              :min-length 0 :max-length 40
              :alphabet (coerce (list #\< #\> #\& #\" #\'
                                      (code-char 9) (code-char 10) (code-char 13)
                                      (code-char 1) (code-char 31)
                                      #\a #\z #\Space #\0)
                                'string))))
      (:trials 300 :timeout-per-trial 1)
    (expect (xml-escaped-output-safe-p (cl-weave::xml-escaped-string text))
            :to-be-truthy))
  (it "prints CI-readable TAP results"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-tap
                     (list (make-sample-event
                            :status :pass
                            :path '("reporters" "passes"))
                           (make-sample-event
                            :status :skip
                            :path '("reporters" "skips")
                            :reason "needs terminal")
                           (make-sample-event
                            :status :todo
                            :path '("reporters" "todos")
                            :reason "pending")
                           (make-sample-event
                            :status :fail
                            :path '("reporters" "fails")
                            :condition "bad value"
                            :secondary-conditions
                            (list (format nil "cleanup~%one") "cleanup \"two\"")
                            :assertion (cl-weave::make-assertion-detail
                                        :form '(expect 1 :to-be 2)
                                        :matcher :to-be
                                        :actual 1
                                        :expected 2
                                        :negated nil
                                        :pass nil))
                           (make-sample-event
                            :status :error
                            :path '("reporters" "errors")
                            :condition "boom"))
                     stream))))
      (expect output :to-contain "TAP version 13")
      (expect output :to-contain "1..5")
      (expect output :to-contain "ok 1 - reporters > passes")
      (expect output :to-contain "ok 2 - reporters > skips # SKIP needs terminal")
      (expect output :to-contain "ok 3 - reporters > todos # TODO pending")
      (expect output :to-contain "not ok 4 - reporters > fails")
      (expect output :to-contain "not ok 5 - reporters > errors")
      (expect output :to-contain "status: \"fail\"")
      (expect output :to-contain "condition: \"bad value\"")
      (expect output :to-contain "secondary condition: \"cleanup one\"")
      (expect output :to-contain "secondary condition: \"cleanup \\\"two\\\"\"")
      (expect output :to-contain "matcher: \":TO-BE\"")))

  (it "preserves unicode while normalizing TAP line breaks"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-tap
                     (list (make-sample-event
                            :status :skip
                            :path '("parser" "handles λ")
                            :reason (format nil "line1~%line2~C絵文字😀" #\Tab))
                           (make-sample-event
                            :status :fail
                            :path '("parser" "keeps 雪")
                            :condition (format nil "壊れた~%入力")))
                     stream))))
      (expect output :to-contain "ok 1 - parser > handles λ # SKIP line1 line2 絵文字😀")
      (expect output :to-contain "not ok 2 - parser > keeps 雪")
      (expect output :to-contain "condition: \"壊れた 入力\"")))

  (it "prints GitHub Actions annotations for failures and errors"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-github
                     (list (make-sample-event
                            :status :pass
                            :path '("reporters" "passes"))
                           (make-sample-event
                            :status :skip
                            :path '("reporters" "skips")
                            :reason "needs terminal")
                           (make-sample-event
                            :status :fail
                            :path '("reporters" "fails")
                            :location '(:file "tests/reporters,case:lisp")
                            :condition (format nil "bad%~%value, x:y")
                            :secondary-conditions
                            (list (format nil "cleanup%~%one") "cleanup two")
                            :assertion (cl-weave::make-assertion-detail
                                        :form '(expect 1 :to-be 2)
                                        :matcher :to-be
                                        :actual 1
                                        :expected 2
                                        :negated nil
                                        :pass nil))
                           (make-sample-event
                            :status :error
                            :path '("reporters" "errors")
                            :condition "boom"))
                     stream))))
      (expect output :to-contain "::error file=tests/reporters%2Ccase%3Alisp::")
      (expect output :to-contain "reporters > fails [fail]%0Abad%25%0Avalue, x:y")
      (expect output :to-contain
              "secondary condition: cleanup%25%0Aone%0Asecondary condition: cleanup two")
      (expect output :to-contain "matcher: :TO-BE")
      (expect output :to-contain "::error::reporters > errors [error]%0Aboom")
      (expect output :not :to-contain "reporters > passes [pass]")
      (expect output :not :to-contain "reporters > skips [skip]")
      (expect output :to-contain "cl-weave: 1 passed, 1 skipped, 0 todo, 1 failed, 1 errored, 4 total")))

  (it "preserves unicode while percent-encoding GitHub annotation control characters"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-github
                     (list (make-sample-event
                            :status :fail
                            :path '("parser" "handles λ")
                            :location '(:file "tests/雪,λ.lisp")
                            :condition (format nil "bad%~%絵文字😀")))
                     stream))))
      (expect output :to-contain "::error file=tests/雪%2Cλ.lisp::")
      (expect output :to-contain "parser > handles λ [fail]%0Abad%25%0A絵文字😀")
      (expect output :to-contain "cl-weave: 0 passed, 0 skipped, 0 todo, 1 failed, 0 errored, 1 total"))))
