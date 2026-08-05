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
  :version "1.2.0"
  :homepage "https://github.com/nerima-lisp/cl-weave"
  :bug-tracker "https://github.com/nerima-lisp/cl-weave/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-weave.git")
  ;; How the `cl-weave` executable is delivered belongs here, not in a build
  ;; system: `(asdf:operate 'asdf:program-op "cl-weave")` and `nix build` must
  ;; produce the same binary, and a save-lisp-and-die chain written out in Nix
  ;; gives the two places to disagree about the entry point.
  :build-operation "program-op"
  ;; `:build-pathname` is merged against this *system's own* :pathname, which
  ;; is "src" below -- so a bare "cl-weave" here would land the executable at
  ;; src/cl-weave, not at the project root where cl-nix-forge's packaging step
  ;; (and a developer running `asdf:make` from this directory) expects it. The
  ;; ".." walks back out of "src" to the .asd's own directory.
  :build-pathname "../cl-weave"
  :entry-point "cl-weave/cli::image-entry-point"
  ;; sb-cover ships with SBCL, so this is not an external dependency; it is
  ;; declared because `cl-weave run --coverage` needs it *inside* a dumped
  ;; image, where REQUIRE can no longer reach SBCL's contrib directory.
  ;; Saying it here rather than in the build makes the image, a plain
  ;; `sbcl --script`, and a REPL all agree on what the system needs.
  ;;
  ;; Guarded `#+sbcl`: src/runner-coverage.lisp (this system's one consumer
  ;; of SB-COVER) already handles its absence gracefully at runtime --
  ;; every reference is a dynamic FIND-PACKAGE/FIND-SYSTEM lookup or sits
  ;; inside its own `#+sbcl`/`#-sbcl` split in REQUIRE-COVERAGE-SUPPORT,
  ;; which signals COVERAGE-UNAVAILABLE on a non-SBCL implementation rather
  ;; than assuming SB-COVER exists. An unconditional `:depends-on` here
  ;; overrode that portable design and made the whole system, needed just to
  ;; use the test DSL, fail to load on any non-SBCL implementation at all --
  ;; found when a downstream consumer (cl-cli) tried bumping past v1.0.0 and
  ;; hit "Module error: Don't know how to REQUIRE sb-cover" building for
  ;; ECL. `#+sbcl` here reproduces the exact same dependency on SBCL (so the
  ;; dumped-image behavior above is unchanged) while producing an empty
  ;; `:depends-on ()` everywhere else.
  :depends-on (#+sbcl (:require "sb-cover"))
  ;; :pathname, not a (:module "src" ...) wrapper. The module added no nesting
  ;; -- it named the same one directory :pathname names -- and cost every
  ;; component an extra indent level. PACKAGE_STANDARD.md normalises that shape
  ;; to :pathname so one structure has one spelling across the org.
  :pathname "src"
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
   (:file "logic-queries")
   (:file "isolation")
   (:file "snapshots-storage")
   (:file "snapshots-session")
   (:file "snapshots")
   (:file "mocks-data")
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
   (:file "runner-control-data")
   (:file "runner-control")
   (:file "runner-hooks")
   (:file "runner-attempts")
   (:file "runner-selection")
   (:file "runner-planning")
   (:file "runner-concurrency")
   (:file "runner-collection")
   (:file "runner-collection-plan")
   (:file "runner-coverage")
   (:file "runner-api")
   (:file "watch-discovery")
   (:file "watch-scope")
   (:file "watch-suite-diff")
   (:file "watch")
   (:file "cli-options")
   (:file "cli-options-parsers")
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
   (:file "cli-execution")
   (:file "cli-image"))
  :in-order-to ((test-op (test-op "cl-weave/test"))))

;;; The test system is `cl-weave/test` (singular, slash-separated) with its
;;; sources under t/. It is NOT `cl-weave-test` and NOT `cl-weave/tests`.
(defsystem "cl-weave/test"
  :description "Self tests for cl-weave."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.2.0"
  :homepage "https://github.com/nerima-lisp/cl-weave"
  :bug-tracker "https://github.com/nerima-lisp/cl-weave/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-weave.git")
  ;; cl-weave is its own test framework, so the suite depends on nothing else.
  :depends-on ("cl-weave")
  :pathname "t"
  :serial t
  :components
  ((:file "package")
   (:file "helpers-support")
   (:file "expect-core-test")
   (:file "snapshots-runtime-test")
   (:file "expect-failures-test")
   (:file "matcher-core-extensions-test")
   (:file "matcher-core-records-test")
   (:file "registration-macros-test")
   (:file "isolation-test")
   (:file "helpers-property")
   (:file "property-generators-test")
   (:file "property-generators-shrinking-test")
   (:file "property-runner-shrinking-test")
   (:file "property-runner-environment-test")
   (:file "registration-fuzz-test")
   (:file "mutation-runner-test")
   (:file "fixtures-test")
   (:file "continuations-test")
   (:file "platform-protocol-timeout-test")
   (:file "runner-collection-tag-filter-test")
   (:file "runner-api-preflight-test")
   (:file "runner-attempts-test")
   (:file "runner-concurrency-test")
   (:file "runner-coverage-preflight-test")
   (:file "runner-coverage-test")
   (:file "registration-expected-failures-test")
   (:file "registration-skips-test")
   (:file "registration-todos-test")
   (:file "runner-selection-focus-test")
   (:file "runner-selection-filtering-test")
   (:file "runner-selection-sharding-test")
   (:file "runner-selection-sequence-test")
   (:file "runner-api-list-mode-test")
   (:file "logic-test")
   (:file "runner-control-bail-test")
   (:file "helpers-workflow")
   (:file "cli-options-test")
   (:file "cli-execution-test")
   (:file "cli-metadata-json-schema-test")
   (:file "cli-metadata-reporting-test")
   (:file "cli-metadata-doctor-test")
   (:file "cli-metadata-project-data-links-test")
   (:file "cli-metadata-reporting-artifact-test")
   (:file "cli-metadata-quality-data-test")
   (:file "cli-metadata-capability-data-test")
   (:file "cli-metadata-project-data-contracts-test")
   (:file "cli-execution-entrypoint-test")
   (:file "cli-image-test")
   (:file "cli-metadata-project-data-community-health-test")
   (:file "watch-asdf-integration-test")
   (:file "watch-discovery-test")
   (:file "watch-scope-test")
   (:file "watch-suite-diff-test")
   (:file "watch-run-test")
   (:file "watch-state-refresh-test")
   (:file "benchmark-test")
   (:file "mocks-test")
   (:file "mocks-spy-lifecycle-test")
   (:file "reporter-results-test")
   (:file "reporter-plan-test")
   (:file "reporter-schema-test")
   (:file "reporter-ci-test")
   (:file "runner-api-status-test")
   (:file "runner-control-runtime-test")
   (:file "journal-test")
   (:file "replay-test")
   (:file "soft-test")
   (:file "runner-api-test"))
  :perform (test-op (op c)
             (declare (ignore op c))
             (unless (uiop:symbol-call :cl-weave :run-all :reporter :spec :pass-with-no-tests nil)
               (error "cl-weave self test suite failed."))))
