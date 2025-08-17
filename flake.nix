{
  description = "My resume";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      pre-commit-hooks,
    }:
    with flake-utils.lib;
    eachSystem allSystems (
      system:
      let
        documentName = "main";
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;

        # use this to get everything
        # tex = pkgs.texlive.combined.scheme-full;
        tex = pkgs.texlive.combine {
          inherit (pkgs.texlive)
            collection-fontsrecommended
            enumitem
            latexmk
            fontspec
            scheme-basic
            titlesec
            ;
        };

        generateReadme = pkgs.writeShellApplication {
          name = "generateReadme";
          text = ''
            ${lib.getExe pkgs.pandoc} -s ${documentName}.tex -o README.md
          '';
        };

      in
      {
        packages = {
          default = self.packages.${system}.document;
          document = pkgs.stdenvNoCC.mkDerivation rec {
            name = "resume";
            src = self;
            buildInputs = with pkgs; [
              tex
              coreutils
              gzip
              perl
              gawk
            ];
            phases = [
              "unpackPhase"
              "buildPhase"
              "installPhase"
            ];

            buildPhase = ''
              export PATH="${pkgs.lib.makeBinPath buildInputs}";
              mkdir -p .cache/texmf-var
              env TEXMFHOME=.cache TEXMFVAR=.cache/texmf-var \
                SOURCE_DATE_EPOCH=${toString self.lastModified} \
                latexmk -interaction=nonstopmode -pdflatex \
                -pretex="\pdftrailerid{}" \
                -usepretex -synctex=1 ${documentName}.tex
            '';

            installPhase = ''
              mkdir -p $out
              gzip -d ${documentName}.synctex.gz
              perl -i -pe 's|^(Input:\d+:)/build/source(.*)$|\1..\2|g' ${documentName}.synctex
              gzip ${documentName}.synctex
              cp ${documentName}.pdf $out/
              cp ${documentName}.synctex.gz $out/
            '';
          };
          watch = pkgs.writeShellApplication {
            name = "watch";
            text = ''
              ${lib.getExe pkgs.watchexec} -e tex nix build .#document
            '';
          };
        };

        apps = {
          generateReadme = {
            type = "app";
            program = lib.getExe generateReadme;
          };
        };

        devShells = {
          default =
            with pkgs;
            mkShell {
              buildInputs = [
                generateReadme
                self.checks.${system}.pre-commit-check.enabledPackages
                self.packages.${system}.default.buildInputs
              ];
              inherit (self.checks.${system}.pre-commit-check) shellHook;
            };
        };
        checks = {
          pre-commit-check = pre-commit-hooks.lib.${pkgs.system}.run {
            src = ./.;
            hooks = {
              git-add-pdf = {
                enable = true;
                stages = [ "pre-commit" ];
                entry = lib.getExe (
                  pkgs.writeShellApplication {
                    name = "git-add-pdf";
                    runtimeInputs = with pkgs; [
                      coreutils
                      poppler-utils
                    ];
                    text = ''
                      before="$(git ls-files -s ${documentName}.pdf ${documentName}.png 2>/dev/null)"

                      cp -f result/${documentName}.pdf ./
                      pdftoppm ${documentName}.pdf ${documentName} -png -singlefile
                      ${lib.getExe pkgs.git} add ${documentName}.pdf ${documentName}.png

                      after="$(git ls-files -s ${documentName}.pdf ${documentName}.png 2>/dev/null)"

                      if [ "$before" != "$after" ]; then
                        echo "media files updated & staged. Commit again"
                        exit 1
                      fi
                    '';
                  }
                );
              };
              check-added-large-files.enable = true;
              check-merge-conflicts.enable = true;
              latexindent = {
                enable = true;
                settings.flags = lib.concatStringsSep " " [
                  "--local"
                  "--silent"
                  "--overwriteIfDifferent"
                  "--cruft .cruft"
                ];
              };
              generate-readme = {
                enable = false;
                entry = lib.getExe generateReadme;
              };
              nixfmt-rfc-style.enable = true;
              proselint = {
                enable = true;
                entry = lib.getExe pkgs.proselint;
                files = "\\.tex$";
              };
              statix.enable = true;
              trim-trailing-whitespace.enable = true;
              typos = {
                enable = true;
                settings = {
                  diff = false;
                };
              };
            };
          };
        };
      }
    );
}
