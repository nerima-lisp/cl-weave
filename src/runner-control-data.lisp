(in-package #:cl-weave)

(defvar *test-name-filter* nil)
(defvar *test-sequence-order* :defined)
(defvar *test-sequence-seed* 0)
(defvar *default-retry* 0)
(defvar *default-timeout-ms* nil)
(defconstant +default-max-workers-cap+ 32)

(defconstant +default-max-workers-floor+ 2)
(defconstant +maximum-retry-count+ 1000)
(defconstant +maximum-timeout-ms+ 86400000)
(defconstant +maximum-worker-count+ 4096)
(defconstant +maximum-bail-limit+ 1000000)
(defconstant +maximum-shard-count+ 1000000)

(defparameter *failing-event-statuses* '(:fail :error))

(defvar *max-workers* nil)
(defvar *retry-budget-remaining* 0)
(defvar *runner-default-condition-handler-disabled* nil)
(defvar *runner-propagate-conditions* t)
(defvar *attempt-secondary-conditions* nil)

(defparameter *runner-dynamic-environment-variables*
  '(*root-suite*
    *current-suite*
    *test-context*
    *test-name-filter*
    *test-sequence-order*
    *test-sequence-seed*
    *default-retry*
    *retry-budget-remaining*
    *runner-propagate-conditions*
    *default-timeout-ms*
    *max-workers*
    *default-max-workers*
    *isolated-timeout-seconds*
    *snapshot-directory*
    *snapshot-file-name*
    *update-snapshots*
    *snapshot-session*
    *property-test-count*
    *property-seed*
    *recursive-generator-depth*
    *journal-enabled*
    *test-random-seed*))

(defconstant +stable-hash-modulus+ 4294967296)
(defconstant +stable-hash-offset+ 2166136261)
(defconstant +stable-hash-prime+ 16777619)
