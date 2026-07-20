# Dendritic Doom Emacs Module
# Platform-aware Doom Emacs configuration supporting both GUI (pgtk) and terminal (nox) variants
# This module follows the dendritic pattern - aspect-oriented configuration
_: {
  flake.aspects.doom-emacs.homeManager =
    {
      pkgs,
      lib,
      config,
      inputs,
      ...
    }:
    let
      cfg = config.doom-emacs;
    in
    {
      imports = [ inputs.nix-doom-emacs-unstraightened.homeModule ];

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

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          # Common config (all variants)
          {
            home = {
              shellAliases = {
                ec = "emacsclient";
                ecn = "emacsclient -nw";
              };

              packages = with pkgs; [
                # Doom runtime deps (interactive use; Unstraightened supplies git/rg/fd on Doom $PATH)
                fd
                ripgrep
                nodejs
                prettier
                mermaid-cli
                (aspellWithDicts (
                  d: with d; [
                    en
                    en-computers
                    en-science
                  ]
                ))
              ];
            };

            programs.doom-emacs = {
              enable = true;
              emacs = if cfg.variant == "pgtk" then pkgs.emacs-pgtk else pkgs.emacs-nox;
              extraPackages = epkgs: [ epkgs.treesit-grammars.with-all-grammars ];
            };

            services.emacs = lib.mkIf cfg.service.enable {
              enable = true;
            };
          }

          # pgtk variant (GUI Emacs)
          (lib.mkIf (cfg.variant == "pgtk") {
            home = {
              shellAliases.ecc = "emacsclient -c";

              packages = with pkgs; [
                xclip
                gzip
                findutils
                vscode-langservers-extracted
              ];
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
          (lib.mkIf (cfg.variant == "nox") {
            home.sessionVariables.EDITOR = "emacs -nw";
          })

          # SOPS secrets decryption
          (lib.mkIf cfg.secrets.enable {
            home.activation.decryptEmacs = lib.hm.dag.entryAfter [ "installPackages" ] ''
              PATH="${config.home.path}/bin:$PATH"
              sops -d ~/.dotfiles/secrets/emacs/emacs.sops > ~/.dotfiles/secrets/emacs/emacs
              sops -d ~/.dotfiles/secrets/emacs/emacs.pub.sops > ~/.dotfiles/secrets/emacs/emacs.pub
            '';
          })
        ]
      );
    };
}
