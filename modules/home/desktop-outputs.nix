# The two monitors the desktop is laid out for, by their role rather than their connector names.
# The dotfiles name no outputs: waybar's bars, the clock ring and the wallpapers refer to the left and right monitors,
# and home/desktop.nix turns these values into the files and arguments that need the actual names
{ lib, ... }:
let
  output = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        example = "DP-1";
        description = "Connector name, as `niri msg outputs` lists it.";
      };
      scale = lib.mkOption {
        type = lib.types.nullOr (lib.types.either lib.types.int lib.types.float);
        default = null;
        description = "Output scale. null leaves it to niri.";
      };
      x = lib.mkOption {
        type = lib.types.int;
        description = "Horizontal position in logical pixels.";
      };
    };
  };
in
{
  options.yuki.desktop.outputs = {
    left = lib.mkOption {
      type = output;
      description = "Left monitor. It carries the always-visible bar with the tray, and the clock ring.";
    };
    right = lib.mkOption {
      type = output;
      description = "Right monitor. Its bar is hidden until toggled.";
    };
  };
}
