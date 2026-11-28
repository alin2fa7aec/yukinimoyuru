# System modules that hold no values of their own. Each declares options under `yuki` and does nothing until they are set;
# the values come from the private input (see flake.nix)
{ lib, ... }:
{
  imports = [
    ./lan-share.nix
    ./photo-museums.nix
  ];

  # Services meant only for the local network listen on, or open the firewall only on, this interface
  options.yuki.lan.interface = lib.mkOption {
    type = lib.types.str;
    example = "eth0";
    description = "Network interface facing the LAN.";
  };
}
