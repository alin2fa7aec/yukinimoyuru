# home-manager configuration for alin. Each imported file covers one area; the commit scopes follow the same split:
# desktop.nix and theme.nix are desktop, shell.nix and tools.nix are home, claude.nix is claude
{
  config,
  inputs,
  ...
}:
{
  imports = [
    ./desktop.nix
    ./theme.nix
    ./shell.nix
    ./tools.nix
    ./claude.nix
  ];

  # The dotfiles are used in two ways, and both are passed to every module as arguments:
  # - dot: the copy pinned by flake.lock, for files nix reads or transforms (readFile, generated colors, service arguments)
  # - liveDot: a link straight into the checkout, for files placed as they are. Edits take effect without a rebuild
  # Assumes the checkout lives at ~/!metier/dotfiles
  _module.args = {
    dot = inputs.dotfiles;
    liveDot =
      path: config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/!metier/dotfiles/${path}";
  };

  # Create only ~/downloads in the home directory.
  # xdg-user-dirs-update fills in directories missing from user-dirs.dirs with defaults like ~/Pictures,
  # so disable unused ones by setting them to $HOME (user-dirs.dirs(5)).
  # home-manager also writes enabled=False to user-dirs.conf, so they are not recreated at login
  xdg.userDirs =
    let
      home = config.home.homeDirectory;
    in
    {
      enable = true;
      createDirectories = true;
      download = "${home}/downloads";
      desktop = home;
      documents = home;
      music = home;
      pictures = home;
      projects = home;
      publicShare = home;
      templates = home;
      videos = home;
    };

  home.stateVersion = "26.05";
}
