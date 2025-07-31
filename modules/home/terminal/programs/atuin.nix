{
  config,
  ...
}:

{

  programs.atuin = {
    enable = true;
    settings = {
      keymap_mode = "vim-normal";
      key_path = config.sops.secrets.atuin_key.path;
    };
  };
}
