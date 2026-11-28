# System modules that hold no values of their own. Each declares options under `yuki` and does nothing until they are set;
# the values come from the private input (see flake.nix)
{ lib, ... }:
{
  imports = [
    ./kanata.nix
    ./lan-share.nix
    ./photo-museums.nix
  ];

  options.yuki = {
    # The one desktop user. The host configuration creates it and home-manager builds its environment from home/
    user = lib.mkOption {
      type = lib.types.str;
      description = "Name of the desktop user.";
    };

    # Services meant only for the local network listen on, or open the firewall only on, this interface
    lan.interface = lib.mkOption {
      type = lib.types.str;
      example = "eth0";
      description = "Network interface facing the LAN.";
    };
  };
}
