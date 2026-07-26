{
  description = "cl-weave: a modern Common Lisp testing framework";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # `inputs.nixpkgs.follows` is mandatory on every input: without it each one
    # drags in its own nixpkgs, inflating flake.lock and rebuilding the same
    # derivations.
    paredit-cli = {
      url = "github:takeokunn/paredit-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      paredit-cli,
      treefmt-nix,
    }:
    let
      # Only what is verified: x86_64-linux by CI, aarch64-darwin by the
      # maintainer's local `nix flake check`. aarch64-linux and x86_64-darwin
      # are not declared because nothing runs them, and a platform no runner
      # can build makes `nix flake check --all-systems` fail with "platform
      # mismatch" rather than skip it. See ADR-0078.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems =
        function: nixpkgs.lib.genAttrs systems (system: function (import nixpkgs { inherit system; }));
      source = nixpkgs.lib.cleanSourceWith {
        src = self;
        filter =
          path: type: nixpkgs.lib.cleanSourceFilter path type && builtins.baseNameOf path != ".direnv";
      };

      # Single source of truth for the package version: the `:version` form in
      # cl-weave.asd. A release only ever edits the .asd file and every Nix
      # package (default + docs) follows automatically. Nix regexes are
      # whole-string anchored and `.` never spans newlines, so the version is
      # extracted line-by-line rather than with one multi-line match.
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile ./cl-weave.asd);
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "[[:space:]]*:version \"[^\"]*\"" line != null) lines
          );
        in
        builtins.head (builtins.match "[[:space:]]*:version \"([^\"]*)\"" versionLine);

      # treefmt drives `nix fmt` and the `checks.<system>.formatting` gate, so
      # the formatter and the CI gate can never disagree about what "formatted"
      # means. Scope is Nix only: nixfmt (RFC style) is a low-diff formatter,
      # whereas a YAML formatter mangles the GitHub Actions `on:` key and
      # reformatting Markdown would churn the whole docs tree.
      treefmtEval = forAllSystems (
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );

      mkDocs =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-weave-docs";
          inherit version;
          # Rooted at the repository, not at ./docs, because
          # docs/src/changelog.md is a pymdownx.snippets include of the
          # top-level CHANGELOG.md and snippets resolves base_path against the
          # working directory mkdocs runs in.
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./docs/mkdocs.yml
              ./docs/src
              ./CHANGELOG.md
            ];
          };
          nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
          # Build fully offline: Material for MkDocs bundles all of its assets,
          # so no network access is required inside the Nix sandbox. --strict
          # promotes broken links and unlisted pages to build failures.
          buildPhase = ''
            runHook preBuild
            mkdocs build --strict --config-file docs/mkdocs.yml --site-dir "$out"
            runHook postBuild
          '';
          dontInstall = true;
          meta = {
            description = "Rendered MkDocs (Material) documentation for cl-weave";
            homepage = "https://github.com/nerima-lisp/cl-weave";
            license = pkgs.lib.licenses.mit;
          };
        };
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.coreutils
            pkgs.jq
            pkgs.libxml2
            pkgs.nixfmt
            pkgs.perl
            pkgs.sbcl
            paredit-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];
        };
      });

      # `nix fmt` entry point.
      formatter = forAllSystems (
        pkgs: treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper
      );

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel, with
      # build caching. Add a check here rather than a job in ci.yml.
      checks = forAllSystems (
        pkgs:
        let
          lib = pkgs.lib;
          packaged-cli = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/cl-weave";
          mkCheck =
            {
              name,
              timeoutSeconds,
              command,
              artifacts ? [ ],
              validationCommands ? [ ],
            }:
            pkgs.stdenv.mkDerivation {
              inherit name;
              src = source;
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.jq
                pkgs.libxml2
                pkgs.perl
                pkgs.sbcl
              ];
              buildPhase = ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                export CL_SOURCE_REGISTRY="$PWD//:"
                timeout ${toString timeoutSeconds}s \
                  ${lib.escapeShellArgs command}
                ${lib.concatMapStringsSep "\n" (artifact: "test -e ${lib.escapeShellArg artifact}") artifacts}
                ${lib.concatStringsSep "\n" validationCommands}
              '';
              installPhase = ''
                mkdir -p "$out"
                ${lib.concatMapStringsSep "\n" (
                  artifact: "cp -R ${lib.escapeShellArg artifact} \"$out/\""
                ) artifacts}
              '';
            };
        in
        {
          # The whole self-test suite. Named `default` because that is the
          # attribute the org standard reserves for a package's test run, so
          # `nix flake check` reports the same thing everywhere.
          default = mkCheck {
            name = "cl-weave-test";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/test"
            ];
          };

          json-results-artifact = mkCheck {
            name = "cl-weave-json-results-artifact";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/test"
              "--reporter"
              "json"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
              "--output"
              "cl-weave-results.json"
            ];
            artifacts = [ "cl-weave-results.json" ];
            validationCommands = [
              ''jq -e '.schemaVersion == 6 and .kind == "test-results" and (.events | type == "array") and (.events | length > 0)' cl-weave-results.json >/dev/null''
            ];
          };

          jsonl-events-artifact = mkCheck {
            name = "cl-weave-jsonl-events-artifact";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/test"
              "--reporter"
              "jsonl"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
              "--output"
              "cl-weave-events.jsonl"
            ];
            artifacts = [ "cl-weave-events.jsonl" ];
            validationCommands = [
              ''jq -s -e 'length >= 3 and .[0].schemaVersion == 1 and .[0].kind == "test-results-start" and .[-1].schemaVersion == 1 and .[-1].kind == "test-results-summary" and all(.[1:-1][]; .schemaVersion == 3 and .kind == "test-event")' cl-weave-events.jsonl >/dev/null''
            ];
          };

          cli-json-results = mkCheck {
            name = "cl-weave-cli-json-results";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/test"
              "--reporter"
              "json"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
              "--output"
              "cl-weave-cli-results.json"
            ];
            artifacts = [ "cl-weave-cli-results.json" ];
            validationCommands = [
              ''jq -e '.schemaVersion == 6 and .kind == "test-results" and (.events | type == "array") and (.events | length > 0)' cl-weave-cli-results.json >/dev/null''
            ];
          };

          ai-metadata-artifact = mkCheck {
            name = "cl-weave-ai-metadata-artifact";
            timeoutSeconds = 120;
            command = [
              packaged-cli
              "metadata"
              "cl-weave/test"
              "--reporter"
              "json"
              "--output"
              "cl-weave-metadata.json"
            ];
            artifacts = [ "cl-weave-metadata.json" ];
            validationCommands = [
              ''jq -e '.schemaVersion == 23 and .kind == "cl-weave-metadata"' cl-weave-metadata.json >/dev/null''
            ];
          };

          plan-artifact = mkCheck {
            name = "cl-weave-plan-artifact";
            timeoutSeconds = 120;
            command = [
              packaged-cli
              "list"
              "cl-weave/test"
              "--reporter"
              "json"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
              "--output"
              "cl-weave-plan.json"
            ];
            artifacts = [ "cl-weave-plan.json" ];
            validationCommands = [
              ''jq -e '.schemaVersion == 3 and .kind == "test-plan" and (.tests | type == "array") and (.tests | length > 0)' cl-weave-plan.json >/dev/null''
            ];
          };

          watch-once-artifact = mkCheck {
            name = "cl-weave-watch-once-artifact";
            timeoutSeconds = 120;
            command = [
              packaged-cli
              "watch"
              "cl-weave/test"
              "--once"
              "--reporter"
              "json"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
              "--output"
              "cl-weave-watch-once.json"
            ];
            artifacts = [ "cl-weave-watch-once.json" ];
            validationCommands = [
              ''jq -e '.schemaVersion == 6 and .kind == "test-results" and (.events | type == "array") and (.events | length > 0)' cl-weave-watch-once.json >/dev/null''
            ];
          };

          tap-artifact = mkCheck {
            name = "cl-weave-tap-artifact";
            timeoutSeconds = 120;
            command = [
              packaged-cli
              "run"
              "cl-weave/test"
              "--reporter"
              "tap"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
              "--output"
              "cl-weave-tap.txt"
            ];
            artifacts = [ "cl-weave-tap.txt" ];
            validationCommands = [
              ''perl -ne 'chomp; $seen = 1 if $_ eq "TAP version 13"; END { exit !$seen }' cl-weave-tap.txt''
            ];
          };

          filtered-smoke = mkCheck {
            name = "cl-weave-filtered-smoke";
            timeoutSeconds = 60;
            command = [
              packaged-cli
              "run"
              "cl-weave/test"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
            ];
          };

          junit-artifact = mkCheck {
            name = "cl-weave-junit-artifact";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/test"
              "--reporter"
              "junit"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
              "--output"
              "cl-weave-junit.xml"
            ];
            artifacts = [ "cl-weave-junit.xml" ];
            validationCommands = [
              "xmllint --noout cl-weave-junit.xml"
              ''test "$(xmllint --xpath 'name(/*)' cl-weave-junit.xml)" = testsuite''
            ];
          };

          coverage-artifact = mkCheck {
            name = "cl-weave-coverage-artifact";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/test"
              "--coverage"
              "--coverage-output"
              "cl-weave.coverage"
              "--coverage-report-directory"
              "cl-weave-coverage-report/"
              "--coverage-system"
              "cl-weave"
              "--coverage-min-expression"
              "1"
              "--coverage-min-branch"
              "1"
            ];
            artifacts = [
              "cl-weave.coverage"
              "cl-weave-coverage-report/"
            ];
            validationCommands = [
              "test -s cl-weave.coverage"
              "test -s cl-weave-coverage-report/cover-index.html"
            ];
          };

          paredit-lint = paredit-cli.lib.${pkgs.stdenv.hostPlatform.system}.mkLintCheck {
            src = source;
            name = "cl-weave-paredit-lint";
          };

          # Enforce the formatter that `nix fmt` already applies, so drift is
          # caught by `nix flake check` (and therefore CI) rather than in review.
          formatting = treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.check self;

          # The docs package builds with `mkdocs --strict`, so a broken link or
          # a page missing from the nav fails the build. Without this the docs
          # are only ever built by the publish workflow, which runs after a
          # merge to main, meaning such a break surfaces as a failed deploy
          # rather than as a failed pull request.
          docs = self.packages.${pkgs.stdenv.hostPlatform.system}.docs;
        }
      );

      packages = forAllSystems (pkgs: {
        docs = mkDocs pkgs;

        default = pkgs.stdenv.mkDerivation {
          pname = "cl-weave";
          inherit version;
          src = source;
          dontBuild = true;
          dontStrip = true;
          nativeBuildInputs = [ pkgs.sbcl ];
          installPhase = ''
            mkdir -p $out/share/common-lisp/source/cl-weave
            mkdir -p $out/bin
            cp -R . $out/share/common-lisp/source/cl-weave
            export HOME=/var/empty
            # Keep ASDF compilation output scoped to this Nix build.  A fixed
            # /tmp cache is shared by concurrent macOS builds and races on FASLs.
            export XDG_CACHE_HOME="$TMPDIR/cl-weave-cache"
            mkdir -p "$XDG_CACHE_HOME"
            export CL_SOURCE_REGISTRY="$out/share/common-lisp/source//:"
            sbcl --dynamic-space-size 4096 --noinform --non-interactive \
              --eval '(require :asdf)' \
              --eval '(require :sb-cover)' \
              --eval '(asdf:load-system :cl-weave)' \
              --eval "(defparameter cl-weave/cli::*installed-source-root* #p\"$out/share/common-lisp/source/\")" \
              --eval '(defun cl-weave/cli::saved-image-main () (setf *default-pathname-defaults* (uiop:getcwd) sb-ext:*runtime-pathname* #p"${pkgs.sbcl}/bin/sbcl") (uiop:setup-temporary-directory) (asdf:initialize-source-registry (list :source-registry (list :tree cl-weave/cli::*installed-source-root*) :inherit-configuration)) (asdf:initialize-output-translations (quote (:output-translations (t (:home ".cache" "common-lisp" :implementation)) :ignore-inherited-configuration))) (cl-weave/cli:main))' \
              --eval '(asdf:clear-output-translations)' \
              --eval '(finish-output *standard-output*)' \
              --eval '(finish-output *error-output*)' \
              --eval "(sb-ext:save-lisp-and-die \"$out/bin/cl-weave\" :toplevel #'cl-weave/cli::saved-image-main :executable t :save-runtime-options t)"
            rm -rf "$XDG_CACHE_HOME"
          '';
          meta = {
            description = "A modern, Vitest-inspired Common Lisp testing framework";
            homepage = "https://github.com/nerima-lisp/cl-weave";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.unix;
            mainProgram = "cl-weave";
          };
        };
      });

      overlays.default = final: prev: {
        cl-weave = self.packages.${final.stdenv.hostPlatform.system}.default;
      };

      apps = forAllSystems (
        pkgs:
        let
          package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          program = "${package}/bin/cl-weave";
        in
        {
          default = {
            type = "app";
            inherit program;
            meta = {
              description = "cl-weave CLI application";
              mainProgram = "cl-weave";
            };
          };

          cl-weave = {
            type = "app";
            inherit program;
            meta = {
              description = "cl-weave CLI application";
              mainProgram = "cl-weave";
            };
          };

          # `nix run .#test` — the org-standard test entry point. It drives the
          # root run-tests.lisp rather than the packaged CLI so that the plain
          # `sbcl --script run-tests.lisp` path (the one a contributor uses in
          # a REPL-less shell, and the one every sibling repository exposes)
          # keeps being exercised. `checks.default` covers the packaged CLI.
          test =
            let
              runner = pkgs.writeShellApplication {
                name = "cl-weave-test";
                runtimeInputs = [
                  pkgs.coreutils
                  pkgs.sbcl
                ];
                text = ''
                  export HOME="''${TMPDIR:-/tmp}/cl-weave-home"
                  mkdir -p "$HOME"
                  export CL_SOURCE_REGISTRY="${source}//:"
                  exec timeout 600s sbcl --script ${source}/run-tests.lisp
                '';
              };
            in
            {
              type = "app";
              program = "${runner}/bin/cl-weave-test";
              meta = {
                description = "Run the cl-weave self-test suite";
                mainProgram = "cl-weave-test";
              };
            };
        }
      );
    };
}
