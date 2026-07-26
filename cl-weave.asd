(in-package #:asdf-user)

(defsystem "cl-weave"
  ;; All eight metadata fields are mandatory across the org: :homepage,
  ;; :bug-tracker and :source-control are what let a consumer find the project
  ;; from an ASDF or Quicklisp listing alone.
  :description "A modern Common Lisp testing framework inspired by Vitest."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  ;; Single source of truth for the version. flake.nix reads this form, and
  ;; release.yml refuses to publish a tag that disagrees with it.
  :version "1.0.0"
  :homepage "https://github.com/nerima-lisp/cl-weave"
  :bug-tracker "https://github.com/nerima-lisp/cl-weave/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-weave.git")
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "package")
     (:file "platform-protocol")
     (:file "platform-portable")
     (:file "platform-sbcl")
     (:file "model")
     (:file "model-registry")
     (:file "model-registration")
     (:file "journal")
     (:file "replay")
     (:file "soft")
     (:file "benchmark")
     (:file "logic")
     (:file "isolation")
     (:file "snapshots")
     (:file "mocks")
     (:file "matcher-core")
     (:file "matcher-structural")
     (:file "matcher-runtime")
     (:file "matcher-builtins")
     (:file "expectation")
     (:file "property-core")
     (:file "property-generators-equality")
     (:file "property-generators-shrinking")
     (:file "property-generators-primitives")
     (:file "property-generators")
     (:file "property-runner")
     (:file "mutation-model")
     (:file "mutation-operators")
     (:file "mutation-walker")
     (:file "mutation-runner")
     (:file "registration")
     (:file "fixtures")
     (:file "continuations")
     (:file "expect-runtime")
     (:file "expect")
     (:file "reporter-schema")
     (:file "reporter-schema-data")
     (:file "reporter-json")
     (:file "reporter-results")
     (:file "reporter-tap")
     (:file "reporter-github")
     (:file "reporter-plan")
     (:file "reporter-mutation")
     (:file "reporter-junit")
     (:file "runner-control")
     (:file "runner-hooks")
     (:file "runner-attempts")
     (:file "runner-selection")
     (:file "runner-planning")
     (:file "runner-concurrency")
     (:file "runner-collection")
     (:file "runner-coverage")
     (:file "runner-api")
     (:file "watch-discovery")
     (:file "watch-scope")
     (:file "watch-suite-diff")
     (:file "watch")
     (:file "cli-options")
     (:file "cli-options-data")
     (:file "cli-metadata-project-data")
     (:file "cli-metadata-quality-data")
     (:file "cli-metadata-option-data")
     (:file "cli-metadata-capability-data")
     (:file "cli-metadata-core")
     (:file "cli-metadata-doctor")
     (:file "cli-metadata-json-core")
     (:file "cli-metadata-json-schema")
     (:file "cli-metadata-json-schema-data")
     (:file "cli-metadata-reporting")
     (:file "cli")
     (:file "cli-execution"))))
  :in-order-to ((test-op (test-op "cl-weave/test"))))

;;; The test system is `cl-weave/test` (singular, slash-separated) with its
;;; sources under t/. It is NOT `cl-weave-test` and NOT `cl-weave/tests`.
(defsystem "cl-weave/test"
  :description "Self tests for cl-weave."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.0"
  :homepage "https://github.com/nerima-lisp/cl-weave"
  :bug-tracker "https://github.com/nerima-lisp/cl-weave/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-weave.git")
  ;; cl-weave is its own test framework, so the suite depends on nothing else.
  :depends-on ("cl-weave")
  :serial t
  :components
  ((:module "t"
    :serial t
    :components
    ((:file "package")
     (:file "support")
     (:file "expect-core")
     (:file "snapshots-runtime")
     (:file "expect-failures")
     (:file "expect-extensions")
     (:file "expect-records")
     (:file "macros")
     (:file "isolation")
     (:file "property-support")
     (:file "property-generators")
     (:file "property-generators-shrinking")
     (:file "property-shrinking")
     (:file "property-environment")
     (:file "fuzz")
     (:file "mutation")
     (:file "fixtures")
     (:file "cps")
     (:file "platform-timeout")
     (:file "tag-filter-normalization")
     (:file "run-all-preflight")
     (:file "retry-timeout")
     (:file "concurrent")
     (:file "coverage-preflight")
     (:file "coverage")
     (:file "expected-failures")
     (:file "skips")
     (:file "todos")
     (:file "focus")
     (:file "filtering")
     (:file "sharding")
     (:file "sequence")
     (:file "list-mode")
     (:file "list-mode-logic")
     (:file "bail")
     (:file "cli-support")
     (:file "cli-options")
     (:file "cli-execution")
     (:file "cli-metadata-schema")
     (:file "cli-metadata-core")
     (:file "cli-metadata-doctor")
     (:file "cli-metadata-public-links")
     (:file "cli-metadata-artifact")
     (:file "cli-metadata-ci")
     (:file "cli-metadata-capabilities")
     (:file "cli-metadata-contracts")
     (:file "cli-entrypoint")
     (:file "community-health")
     (:file "asdf-integration")
     (:file "watch-discovery")
     (:file "watch-scope")
     (:file "watch-suite-diff")
     (:file "watch-run")
     (:file "watch-state-refresh")
     (:file "benchmark")
     (:file "mocking")
     (:file "mocking-spy-lifecycle")
     (:file "reporter-formats")
     (:file "reporter-plans")
     (:file "reporter-schemas")
     (:file "reporter-ci")
     (:file "reporter-status")
     (:file "reporter-runtime")
     (:file "journal")
     (:file "replay")
     (:file "soft")
     (:file "runner-public-api"))))
  :perform (test-op (op c)
             (declare (ignore op c))
             (unless (uiop:symbol-call :cl-weave :run-all :reporter :spec :pass-with-no-tests nil)
               (error "cl-weave self test suite failed."))))
