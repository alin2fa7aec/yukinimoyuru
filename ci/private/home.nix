# Placeholder for the private input's home-manager module (see nixos.nix next to it)
{
  yuki.dotfiles.checkout = "/home/user/dotfiles";

  yuki.desktop.outputs = {
    left = {
      name = "DP-1";
      scale = 1;
      x = 0;
    };
    right = {
      name = "DP-2";
      x = 2560;
    };
  };

  yuki.rcloneMounts.example.mountpoint = "%h/cloud";
}
