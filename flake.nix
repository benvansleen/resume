{
  description = "My resume";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    secrets = {
      url = "git+ssh://git@github.com/benvansleen/secrets.git";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      secrets,
      flake-utils,
      pre-commit-hooks,
      ...
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
            ${lib.getExe pkgs.pandoc} -s src/${documentName}.tex -o README.md
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
              export PHONE="${lib.concatStringsSep "." secrets.personal-info.phone}"
              export EMAIL="${secrets.personal-info.email}"

              export PATH="${pkgs.lib.makeBinPath buildInputs}";
              mkdir -p .cache/texmf-var
              env TEXMFHOME=.cache TEXMFVAR=.cache/texmf-var \
                SOURCE_DATE_EPOCH=${toString self.lastModified} \
                latexmk -interaction=nonstopmode -pdflatex -outdir=. \
                -pretex="\pdftrailerid{}" \
                -usepretex -synctex=1 src/${documentName}.tex
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
                      perl
                    ];
                    text = ''
                      set -euo pipefail
                      before="$(git ls-files -s media/ README.md 2>/dev/null)"

                      if [ ! -f "result/${documentName}.pdf" ]; then
                        echo "missing result/${documentName}.pdf; run nix build .#document" >&2
                        exit 1
                      fi

                      mkdir -p media
                      cp -f result/${documentName}.pdf media/${documentName}.pdf
                      rm -f ${documentName}.pdf
                      pdftoppm -png -singlefile media/${documentName}.pdf media/${documentName}
                      if [ ! -f "media/${documentName}.png" ] && [ -f "media/${documentName}-1.png" ]; then
                        mv -f "media/${documentName}-1.png" "media/${documentName}.png"
                      fi
                      if [ ! -f "media/${documentName}.png" ] && [ -f "media/${documentName}-01.png" ]; then
                        mv -f "media/${documentName}-01.png" "media/${documentName}.png"
                      fi
                      if [ ! -f "media/${documentName}.png" ]; then
                        echo "failed to generate media/${documentName}.png" >&2
                        exit 1
                      fi

                      cache_hash="$(${lib.getExe pkgs.git} hash-object media/${documentName}.png | cut -c1-7)"
                      cp -f "media/${documentName}.png" "media/${documentName}-$cache_hash.png"
                      for file in media/${documentName}-*.png; do
                        if [ "$file" != "media/${documentName}-$cache_hash.png" ]; then
                          rm -f "$file"
                        fi
                      done

                      ${lib.getExe pkgs.perl} -i -pe "s|media/${documentName}(?:-[0-9a-f]{7})?\\.png(?:\\?cache=[^\"\s>]*)?|media/${documentName}-$cache_hash.png|g" README.md
                      ${lib.getExe pkgs.git} add media/ README.md

                      after="$(git ls-files -s media/ README.md 2>/dev/null)"

                      if [ "$before" != "$after" ]; then
                        echo "media files updated & staged. Commit again"
                        exit 1
                      fi
                    '';
                  }
                );
              };
              check-added-large-files.enable = false;
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
