# home-manager configuration for the desktop user (yuki.user). Each imported file covers one area; the commit scopes follow the same split:
# desktop.nix and theme.nix are desktop, shell.nix and tools.nix are home, claude.nix is claude
{ config, ... }:
{
  imports = [
    ./desktop.nix
    ./theme.nix
    ./shell.nix
    ./tools.nix
    ./claude.nix
  ];

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
