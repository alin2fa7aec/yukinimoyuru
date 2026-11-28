# Placeholder for the private input, so CI can evaluate the system without it:
#   nix eval --override-input private path:./ci/private ...
# It stands in for the hardware with the minimum NixOS needs and turns on every module under modules/nixos with made-up values.
# The real values live in the private repository
{
  yuki.user = "user";

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  boot.loader.systemd-boot.enable = true;
  nixpkgs.hostPlatform = "x86_64-linux";

  yuki.kanata.reconnectDevices = [ "Example Keyboard" ];

  yuki.lan.interface = "eth0";

  yuki.lanShare = {
    enable = true;
    path = "/srv/share";
    user = "user";
    subdirs = [ "inbox" ];
    hostsAllow = [ "192.168.1." ];
  };

  yuki.photoMuseums = {
    owner = "user";
    museums.example = {
      port = 8080;
      source = "/srv/photos";
    };
  };
}
