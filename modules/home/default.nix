# home-manager modules that hold no values of their own. Each declares options under `yuki` and does nothing until they are set;
# the values come from the private input (see flake.nix)
{
  imports = [
    ./desktop-outputs.nix
    ./dotfiles.nix
    ./rclone-mounts.nix
  ];
}
