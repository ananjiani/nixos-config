{
  pkgs,
  pkgs-stable,
  ...
}:

{
  home.shellAliases = {
    ls = "eza -a";
    ll = "eza -alh";
    tree = "eza -tree";
    lg = "lazygit";
    cat = "bat";
    df = "duf";
    du = "dust";
    rd = "ripdrag";
    frd = "ripdrag $(fzf)";
    fo = "open $(fzf)";
    fe = "$EDITOR $(fzf)";
    fc = "emacsclient $(fzf)";
    fv = "vi $(fzf)";
    # nrs = "nh os switch";
    # hms = "nh home switch";
  };

  programs = {
    eza = {
      enable = true;
      git = true;
      icons = "auto";
    };
    bat.enable = true;

    git = {
      enable = true;
      userName = "Ammar Nanjiani";
      userEmail = "ammar.nanjiani@gmail.com";
      extraConfig = {
        init.defaultBranch = "main";
        credential.helper = "store";
        pull.rebase = false;
      };
    };
    lazygit.enable = true;
    # thefuck.enable = true;
    zoxide = {
      enable = true;
      options = [
        "--cmd cd" # doesn't work on nushell and posix shells
      ];
    };
    ripgrep.enable = true;
    fzf = {
      enable = true;
      defaultCommand = "fd --type f";
      changeDirWidgetCommand = "fd --type d";
      colors = {
        fg = "#ebdbb2";
        bg = "#282828";
        hl = "#fabd2f";
        "fg+" = "#ebdbb2";
        "bg+" = "#3c3836";
        "hl+" = "#fabd2f";
        info = "#83a598";
        prompt = "#bdae93";
        spinner = "#fabd2f";
        pointer = "#83a598";
        marker = "#fe8019";
        header = "#665c54";
      };
    };

  };

  home.packages =
    (with pkgs; [
      chafa
      ripdrag
      atool
      ffmpeg
      gnupg
      jq
      poppler_utils
      ffmpegthumbnailer
      pandoc
      tealdeer
      du-dust
      duf
      ripgrep-all
      fd
      sshfs
      pinentry
      rage
      unrar
      p7zip
    ])

    ++

      (with pkgs-stable; [
        sops
        visidata
      ]);
}
