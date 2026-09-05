{
  description = "cl-weave: a modern Common Lisp testing framework";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.3.0";
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
      cl-nix-forge,
      paredit-cli,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      meta = {
        description = "A modern, Vitest-inspired Common Lisp testing framework";
        homepage = "https://github.com/nerima-lisp/cl-weave";
        license = lib.licenses.mit;
        platforms = lib.platforms.unix;
        mainProgram = "cl-weave";
      };

    in
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit
        self
        systems
        nixpkgs
        meta
        ;
      pname = "cl-weave";
      asd = ./cl-weave.asd;
      root = ./.;
      sourceInclude = [
        ./README.md
        ./LICENSE
        ./flake.nix
        ./.github
        ./docs
      ];
      executable = {
        dynamicSpaceSize = 4096;
        installSource = true;
      };
      timeoutSeconds = 600;
      docs = {
        root = ./.;
        fileset = lib.fileset.unions [
          ./docs/mkdocs.yml
          ./docs/src
        ];
        mkdocsYmlName = "docs/mkdocs.yml";
      };
      treefmt.evalModule = treefmt-nix.lib.evalModule;
      devShellPackages = ctx: [
        ctx.pkgs.coreutils
        ctx.pkgs.jq
        ctx.pkgs.libxml2
        ctx.pkgs.nixfmt
        ctx.pkgs.perl
        paredit-cli.packages.${ctx.system}.default
      ];
      extraOutputs =
        ctx:
        let
          packaged-cli = lib.getExe ctx.executable;
          mkCheck =
            args:
            ctx.cl.mkCommandCheck (
              {
                drv = ctx.package;
                nativeBuildInputs = [
                  ctx.pkgs.jq
                  ctx.pkgs.libxml2
                  ctx.pkgs.perl
                ];
              }
              // args
            );
        in
        {
          checks = {
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
                "test -s cl-weave-coverage-report/cover-index.html"
              ];
            };
            packaged-cli-suite = ctx.cl.mkCommandCheck {
              drv = ctx.package;
              name = "cl-weave-packaged-cli-suite";
              timeoutSeconds = 360;
              command = [
                packaged-cli
                "run"
                "cl-weave/test"
              ];
            };

            paredit-lint = paredit-cli.lib.${ctx.system}.mkLintCheck {
              inherit (ctx) src;
              name = "cl-weave-paredit-lint";
            };
          };
        };
    };
}
