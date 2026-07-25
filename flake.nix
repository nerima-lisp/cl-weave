{
  description = "cl-weave: a modern Common Lisp testing framework";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.paredit-cli = {
    url = "github:takeokunn/paredit-cli";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      paredit-cli,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
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

      mkDocs =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-weave-docs";
          inherit version;
          src = pkgs.lib.fileset.toSource {
            root = ./docs;
            fileset = pkgs.lib.fileset.unions [
              ./docs/mkdocs.yml
              ./docs/src
            ];
          };
          nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
          # Build fully offline: Material for MkDocs bundles all of its assets,
          # so no network access is required inside the Nix sandbox. --strict
          # promotes broken links and unlisted pages to build failures.
          buildPhase = ''
            runHook preBuild
            mkdocs build --strict --config-file mkdocs.yml --site-dir "$out"
            runHook postBuild
          '';
          dontInstall = true;
          meta = {
            description = "Rendered MkDocs (Material) documentation for cl-weave";
            homepage = "https://github.com/takeokunn/cl-weave";
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

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

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
          test = mkCheck {
            name = "cl-weave-test";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/tests"
            ];
          };

          json-results-artifact = mkCheck {
            name = "cl-weave-json-results-artifact";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/tests"
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
              "cl-weave/tests"
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
              "cl-weave/tests"
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
              "cl-weave/tests"
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
              "cl-weave/tests"
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
              "cl-weave/tests"
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
              "cl-weave/tests"
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
              "cl-weave/tests"
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
              "cl-weave/tests"
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
              "cl-weave/tests"
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
          nixfmt = pkgs.stdenvNoCC.mkDerivation {
            name = "cl-weave-nixfmt-check";
            src = source;
            nativeBuildInputs = [ pkgs.nixfmt ];
            buildPhase = ''
              runHook preBuild
              find . -name '*.nix' -print0 | xargs -0 nixfmt --check
              runHook postBuild
            '';
            installPhase = ''
              touch "$out"
            '';
          };
        }
      );

      packages = forAllSystems (pkgs: {
        docs = mkDocs pkgs;

        default = pkgs.stdenv.mkDerivation {
          pname = "cl-weave";
          inherit version;
          src = source;
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/share/common-lisp/source/cl-weave
            mkdir -p $out/bin
            cp -R . $out/share/common-lisp/source/cl-weave
            cat > $out/bin/cl-weave <<EOF
            #!${pkgs.runtimeShell}
            set -eu
            export CL_SOURCE_REGISTRY="$out/share/common-lisp/source//:\''${CL_SOURCE_REGISTRY:-}"
            exec ${pkgs.sbcl}/bin/sbcl --dynamic-space-size 4096 --noinform --non-interactive \\
              --eval '(require :asdf)' \\
              --eval '(asdf:initialize-output-translations (quote (:output-translations (t (:home ".cache" "common-lisp" :implementation)) :ignore-inherited-configuration)))' \\
              --eval '(asdf:load-system :cl-weave)' \\
              --eval '(cl-weave/cli:main)' \\
              -- "\$@"
            EOF
            chmod +x $out/bin/cl-weave
          '';
          meta = {
            description = "A modern, Vitest-inspired Common Lisp testing framework";
            homepage = "https://github.com/takeokunn/cl-weave";
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
        }
      );
    };
}
