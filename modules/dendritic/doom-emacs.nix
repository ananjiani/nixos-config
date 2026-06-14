# Dendritic Doom Emacs Module
# Platform-aware Doom Emacs configuration supporting both GUI (pgtk) and terminal (nox) variants
# This module follows the dendritic pattern - aspect-oriented configuration
_:
let
  doomDir = "$HOME/.dotfiles/modules/home/editors/doom-emacs";
in
{
  flake.aspects.doom-emacs.homeManager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      treesitGrammars = pkgs.emacs.pkgs.treesit-grammars.with-all-grammars;
    in
    {
      options.doom-emacs = {
        enable = lib.mkEnableOption "Doom Emacs";

        variant = lib.mkOption {
          type = lib.types.enum [
            "pgtk"
            "nox"
          ];
          default = "pgtk";
          description = "Emacs variant: pgtk (GUI) or nox (terminal-only)";
        };

        autoSync = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Auto-run doom sync on activation";
        };

        service.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run Emacs daemon service";
        };

        secrets.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Decrypt SOPS secrets for Emacs";
        };
      };

      config = lib.mkIf config.doom-emacs.enable (
        lib.mkMerge [
          # Common config (all variants)
          {
            home = {
              shellAliases = {
                ec = "emacsclient";
                ecn = "emacsclient -nw";
              };

              packages = with pkgs; [
                # Doom dependencies
                fd
                ripgrep
                nodejs
                prettier
                mermaid-cli
                gcc # tree-sitter grammar compilation fallback
                (aspellWithDicts (
                  d: with d; [
                    en
                    en-computers
                    en-science
                  ]
                ))
              ];

              sessionVariables = {
                DOOMDIR = doomDir;
                TREESIT_GRAMMAR_PATH = "${treesitGrammars}/lib";
              };
              sessionPath = [ "$HOME/.emacs.d/bin" ];

              # Clone Doom Emacs
              activation.installDoomEmacs = lib.hm.dag.entryAfter [ "installPackages" ] ''
                if [ ! -d "$HOME/.emacs.d" ]; then
                  PATH="${config.home.path}/bin:$PATH"
                  git clone --depth=1 --single-branch https://github.com/doomemacs/doomemacs $HOME/.emacs.d
                fi
              '';
            };
          }

          # pgtk variant (GUI Emacs)
          (lib.mkIf (config.doom-emacs.variant == "pgtk") {
            home.shellAliases.ecc = "emacsclient -c";

            home.packages = with pkgs; [
              xclip
              gzip
              findutils
              vscode-langservers-extracted
            ];

            programs.emacs = {
              enable = true;
              package = pkgs.emacs-pgtk;
              extraPackages = epkgs: [
                epkgs.vterm
                treesitGrammars
              ];
            };

            services.emacs = lib.mkIf config.doom-emacs.service.enable {
              enable = true;
              package = pkgs.emacs-pgtk;
            };

            # The GUI Emacs daemon is WantedBy=default.target, which starts it at
            # boot before the compositor imports WAYLAND_DISPLAY / XDG_SESSION_TYPE
            # into the systemd user manager. Without these, org-download-clipboard
            # falls back to xclip (which can't read Wayland image clipboards, -> 0KB
            # files) and wl-paste can't connect to the compositor. Ordering the
            # service after the graphical session makes it inherit the imported env.
            systemd.user.services.emacs.Unit.After = [ "graphical-session.target" ];
          })

          # nox variant (terminal Emacs)
          (lib.mkIf (config.doom-emacs.variant == "nox") {
            home.sessionVariables.EDITOR = "emacs -nw";

            programs.emacs = {
              enable = true;
              package = pkgs.emacs-nox;
              extraPackages = _epkgs: [
                treesitGrammars
              ];
            };

            services.emacs = lib.mkIf config.doom-emacs.service.enable {
              enable = true;
              package = pkgs.emacs-nox;
            };
          })

          # Doom sync activation
          (lib.mkIf config.doom-emacs.autoSync {
            home.activation.doomSync = lib.hm.dag.entryAfter [ "installDoomEmacs" ] ''
              PATH="${config.home.path}/bin:$PATH"
              export DOOMDIR=${doomDir}
              $HOME/.emacs.d/bin/doom sync
            '';
          })

          # SOPS secrets decryption
          (lib.mkIf config.doom-emacs.secrets.enable {
            home.activation.decryptEmacs = lib.hm.dag.entryAfter [ "installDoomEmacs" ] ''
              PATH="${config.home.path}/bin:$PATH"
              sops -d ~/.dotfiles/secrets/emacs/emacs.sops > ~/.dotfiles/secrets/emacs/emacs
              sops -d ~/.dotfiles/secrets/emacs/emacs.pub.sops > ~/.dotfiles/secrets/emacs/emacs.pub
            '';
          })
        ]
      );
    };
}
