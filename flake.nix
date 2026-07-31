{
  description = "cl-weave: a modern Common Lisp testing framework";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # `inputs.nixpkgs.follows` is mandatory on every input: without it each one
    # drags in its own nixpkgs, inflating flake.lock and rebuilding the same
    # derivations.

    # The org flake preset. Everything this file used to spell out by hand --
    # the `.asd` version extraction, `forAllSystems`, the treefmt eval wired to
    # both `formatter` and `checks.formatting`, the mkdocs package plus its
    # check, the run-tests.lisp gate, the `apps.test`/`apps.default` pair, the
    # devShell and the overlay -- is one `mkPackageFlake` call below. Pinned to
    # a release TAG, never to the branch: a bare `github:nerima-lisp/cl-nix-forge`
    # follows that repository's default branch and would change this build
    # without warning.
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
      cl-nix-forge,
      paredit-cli,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;

      # x86_64-linux and nothing else. Only what a gate verifies is declared,
      # and the only gate is CI. aarch64-darwin was declared until the
      # 2026-08-01 revision on the strength of the maintainer running
      # `nix flake check` locally; running something by hand is not a gate, so
      # the promise was withdrawn. aarch64-linux and x86_64-darwin were already
      # absent for the same reason. Development happens on Linux, and every
      # output -- packages, checks, apps AND devShells -- comes from this one
      # list. See PACKAGE_STANDARD.md "systems".
      systems = [
        "x86_64-linux"
      ];

      meta = {
        description = "A modern, Vitest-inspired Common Lisp testing framework";
        homepage = "https://github.com/nerima-lisp/cl-weave";
        license = lib.licenses.mit;
        platforms = lib.platforms.unix;
        mainProgram = "cl-weave";
      };

    in
    # `mkPackageFlake` spans systems -- it obtains a `pkgs` and its own
    # cl-nix-forge instance per entry in `systems` -- so the per-system `lib`
    # instance this function is *taken from* contributes nothing but the
    # function itself.
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit
        self
        systems
        nixpkgs
        meta
        ;
      pname = "cl-weave";

      # Single source of truth for the package version: the `:version` form in
      # cl-weave.asd. A release only ever edits the .asd file and every Nix
      # package (default + docs) follows automatically.
      asd = ./cl-weave.asd;

      # Required, and it must be a path literal rather than `self`: a flake's
      # `self` is string-like and `lib.fileset` refuses it ("Paths in strings
      # are not supported by `lib.fileset`"). `./.` is the same directory as a
      # path. `self` is still what the preset hands the treefmt gate, which
      # wants the UNFILTERED tree and takes a store path happily.
      root = ./.;

      # `mkLispSource` is an allowlist: `*.asd` and `*.lisp` under the root, and
      # nothing else unless named here. That is what keeps this tree's
      # `coverage-report-*/`, `coverage-filter-*/` and
      # `watch-forward-dependencies-*/` leftovers -- which a local
      # `sbcl --script run-tests.lisp` creates by the dozen -- from changing the
      # source hash and invalidating every build.
      #
      # Everything below is a file the SELF-TEST SUITE reads at run time, not a
      # file the build needs. cl-weave's metadata gates assert that its own
      # documentation, community-health files and CI workflow agree with
      # `cl-weave/metadata`'s tables (see t/cli-metadata-project-data-*.lisp and
      # t/cli-metadata-quality-data-test.lisp, which resolve paths against
      # `uiop:getcwd`), so the check's working tree has to contain them.
      # flake.nix is on the list for the same reason: a gate reads it back and
      # compares the check names it declares against the metadata quality-gate
      # table.
      sourceInclude = [
        ./README.md
        ./LICENSE
        ./flake.nix
        ./.github
        ./docs
      ];

      # The delivered `cl-weave` binary: `packages.default`, `apps.default` and
      # `apps.cl-weave`, all three built by the preset from the SAME
      # `lispDerivation` arguments it built `packages.cl-weave` from. That is
      # the point of stating it here rather than re-spelling the package's
      # identity in an escape hatch: a `lispDependencies` entry added to this
      # call reaches the binary by construction instead of reaching only
      # whatever got repeated.
      #
      # Nothing here repeats what cl-weave.asd already declares.
      # `:build-operation "program-op"`, `:build-pathname "cl-weave"`,
      # `:entry-point "cl-weave/cli::image-entry-point"` and
      # `:depends-on ((:require "sb-cover"))` live in the system definition, so
      # `(asdf:operate 'asdf:program-op "cl-weave")` in a REPL and `nix build`
      # produce the same binary. The hand-written `save-lisp-and-die --eval`
      # chain this replaces spelled the entry point, the sb-cover requirement
      # and the whole image-startup sequence a second time in Nix, where they
      # could drift from the .asd; the startup sequence now lives in
      # src/cli-image.lisp.
      #
      # `dynamicSpaceSize` is the one knob that is genuinely Nix's: it acts on
      # the *invocation* of the SBCL that performs the dump, not on what is
      # dumped. `:save-runtime-options t` is deliberately NOT respelled -- ASDF's
      # `program-op` path hardcodes it and mkExecutable makes the same
      # observable behaviour unconditional on its Darwin fallback; see
      # cl-nix-forge lib/batteries/app.nix, "WHAT NIX OWNS AND WHAT THE .asd
      # OWNS".
      #
      # `installSource` is what makes the delivered binary able to load its OWN
      # systems. A dumped image comes back knowing cl-weave with the source
      # directory it was compiled in -- a build sandbox that no longer exists --
      # and src/cli-image.lisp recovers from that by looking for
      # `share/common-lisp/source/` under the prefix the running image sits in.
      # This is the flag that puts it there, on both delivery paths. Without it
      # `cl-weave run cl-weave/test` from a delivered binary dies with "Failed
      # to find the TRUENAME of /nix/var/nix/builds/.../src/package.lisp"; the
      # CLI's own bootstrap does not rescue it, because that fires only when
      # `asdf:find-system` FAILS and here it succeeds and returns the stale
      # definition. Both halves verified by running the built binary.
      executable = {
        dynamicSpaceSize = 4096;
        installSource = true;
      };

      # `checks.default` and `apps.test` are both run-tests.lisp, driven from
      # this one number, so the command a contributor runs by hand and the gate
      # CI runs cannot drift apart. NOT `asdf:test-system`: cl-weave is its own
      # test subject and its suite performs `test-op` on cl-weave/test to assert
      # the ASDF integration's failure path, which an enclosing test-op turns
      # into a circular dependency ASDF rejects. run-tests.lisp says the same
      # thing at greater length.
      timeoutSeconds = 600;

      # Rooted at the repository rather than at ./docs so that mkdocsYmlName
      # below stays a repository-relative path and the site builds the same way
      # from any working directory. `mkDocsSite` builds with `--strict`, so a
      # broken link or a page missing from the nav fails the build, and
      # `checks.docs` runs it -- which is what keeps such a break inside a pull
      # request instead of surfacing as a failed post-merge deploy.
      docs = {
        root = ./.;
        fileset = lib.fileset.unions [
          ./docs/mkdocs.yml
          ./docs/src
        ];
        mkdocsYmlName = "docs/mkdocs.yml";
      };

      # ONE treefmt evaluation drives `nix fmt` and the `checks.formatting`
      # gate, so the formatter and the CI gate can never disagree about what
      # "formatted" means. Scope stays the preset's Nix-only default: nixfmt
      # (RFC style) is a low-diff formatter, whereas a YAML formatter mangles
      # the GitHub Actions `on:` key and reformatting Markdown would churn the
      # whole docs tree.
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      # sbcl arrives through `inputsFrom` on the package derivation; these are
      # the interactive-only extras -- the validators the artifact checks below
      # use, so a failing gate can be reproduced by hand, plus the formatter and
      # the structural linter.
      devShellPackages = ctx: [
        ctx.pkgs.coreutils
        ctx.pkgs.jq
        ctx.pkgs.libxml2
        ctx.pkgs.nixfmt
        ctx.pkgs.perl
        paredit-cli.packages.${ctx.system}.default
      ];

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel, with
      # build caching. Add a check here rather than a job in ci.yml.
      extraOutputs =
        ctx:
        let
          # `ctx.executable` is the binary `executable` above delivered -- the
          # same value `packages.default` and `apps.cl-weave` are, not a second
          # call that happens to hash the same.
          packaged-cli = lib.getExe ctx.executable;

          # Every artifact gate has the same shape -- run the packaged CLI with
          # an argv, assert named artifacts, validate them, publish them -- so
          # only the parts that differ are written out per gate. `drv` is the
          # ASDF system rather than the CLI: it supplies the writable working
          # tree and the resolved CL_SOURCE_REGISTRY, which is how the packaged
          # binary FINDS `cl-weave/test` to operate on.
          #
          # `command` is a LIST, never a concatenated string: the filter
          # expression below contains spaces and a `>` that a shell would read
          # as a redirection.
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
              # `mkCommandCheck` already asserts every artifact is present AND
              # non-empty, so the old `test -s cl-weave.coverage` is gone. The
              # index page is a file INSIDE an artifact directory, which that
              # rule does not reach.
              validationCommands = [
                "test -s cl-weave-coverage-report/cover-index.html"
              ];
            };

            # The whole suite, through the delivered image rather than through
            # `sbcl --script`. This is what `checks.default` used to be; it is
            # an extra gate now rather than the default one, because the org
            # standard reserves `checks.default` for run-tests.lisp and the
            # preset generates it there.
            #
            # It is kept rather than dropped as redundant. The ten gates above
            # each drive one CLI subcommand over a single filtered test, so
            # between them they prove the binary starts and that each reporter
            # writes its contract -- but nothing else runs the FULL suite inside
            # a dumped image, which is where cl-weave's own startup fixups
            # (src/cli-image.lisp: cwd, temporary directory, source registry,
            # output translations) either hold for every test or do not.
            # Deliberately NOT spelled with the `mkCheck` helper above: a
            # metadata gate reads this file back and requires the `= mkCheck {`
            # lines to be exactly the artifact gates named in
            # `cl-weave/metadata`'s quality-gate table.
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
