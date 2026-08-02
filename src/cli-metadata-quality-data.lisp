(in-package #:cl-weave/metadata)

(defparameter *metadata-quality-gates*
  '((:name "flake-check"
     :kind "nix"
     :command ("nix" "flake" "check" "--print-build-logs")
     :timeout-seconds 900
     :artifacts nil
     :description "Run the complete Nix flake validation suite.")
    (:name "cli-json-results"
     :kind "cli"
     :command ("nix" "run" "." "--" "run" "cl-weave/test"
               "--reporter" "json" "--filter"
               "filtering > runs only tests matching a path substring"
               "--fail-with-no-tests" "--output" "cl-weave-cli-results.json")
     :timeout-seconds 360
     :artifacts ("cl-weave-cli-results.json")
     :description "Verify the packaged CLI can emit schema-versioned JSON results.")
    (:name "json-results-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "run" "cl-weave/test"
               "--reporter" "json" "--output" "cl-weave-results.json")
     :timeout-seconds 360
     :artifacts ("cl-weave-results.json")
     :description "Verify the ASDF test system can emit JSON results through the packaged CLI.")
    (:name "ai-metadata-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "metadata" "cl-weave/test"
               "--reporter" "json" "--output" "cl-weave-metadata.json")
     :timeout-seconds 120
     :artifacts ("cl-weave-metadata.json")
     :description "Verify agent discovery metadata through the packaged CLI.")
    (:name "jsonl-events-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "run" "cl-weave/test"
               "--reporter" "jsonl" "--output" "cl-weave-events.jsonl")
     :timeout-seconds 360
     :artifacts ("cl-weave-events.jsonl")
     :description "Verify JSONL streaming event output for automation.")
    (:name "plan-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "list" "cl-weave/test"
               "--reporter" "json" "--filter"
               "filtering > runs only tests matching a path substring"
               "--fail-with-no-tests" "--output" "cl-weave-plan.json")
     :timeout-seconds 120
     :artifacts ("cl-weave-plan.json")
     :description "Verify machine-readable test discovery output for agents.")
    (:name "watch-once-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "watch" "cl-weave/test"
               "--once" "--reporter" "json" "--filter"
               "filtering > runs only tests matching a path substring"
               "--fail-with-no-tests" "--output" "cl-weave-watch-once.json")
     :timeout-seconds 120
     :artifacts ("cl-weave-watch-once.json")
     :description "Verify one-shot watch mode through the packaged CLI.")
    (:name "tap-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "run" "cl-weave/test"
               "--reporter" "tap" "--filter"
               "filtering > runs only tests matching a path substring"
               "--fail-with-no-tests" "--output" "cl-weave-tap.txt")
     :timeout-seconds 120
     :artifacts ("cl-weave-tap.txt")
     :description "Verify TAP output for line-oriented CI logs.")
    (:name "filtered-smoke"
     :kind "cli"
     :command ("nix" "run" "." "--" "run" "cl-weave/test"
               "--filter" "filtering > runs only tests matching a path substring"
               "--fail-with-no-tests")
     :timeout-seconds 60
     :artifacts nil
     :description "Verify filtered execution through the packaged CLI.")
    (:name "junit-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "run" "cl-weave/test"
               "--reporter" "junit" "--output" "cl-weave-junit.xml")
     :timeout-seconds 360
     :artifacts ("cl-weave-junit.xml")
     :description "Verify CI-oriented JUnit report generation.")
    (:name "coverage-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "run" "cl-weave/test"
               "--coverage" "--coverage-output" "cl-weave.coverage"
               "--coverage-report-directory" "cl-weave-coverage-report/")
     :timeout-seconds 360
     :artifacts ("cl-weave.coverage" "cl-weave-coverage-report/")
     :description "Verify SBCL coverage state and populated HTML report generation.")))
