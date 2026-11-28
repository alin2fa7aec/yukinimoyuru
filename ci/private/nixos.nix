# Placeholder for the private input, so CI can evaluate the system without it:
#   nix eval --override-input private path:./ci/private ...
# It turns on every module under modules/nixos with made-up values. The real values live in the private repository
{
  yuki.lan.interface = "eth0";

  yuki.lanShare = {
    enable = true;
    path = "/srv/share";
    user = "alin";
    subdirs = [ "inbox" ];
    hostsAllow = [ "192.168.1." ];
  };

  yuki.photoMuseums = {
    owner = "alin";
    museums.example = {
      port = 8080;
      source = "/srv/photos";
    };
  };
}
