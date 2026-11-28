# Restart kanata when a listed keyboard connects, so it rescans for devices.
# kanata sometimes misses a Bluetooth keyboard because it cannot grab it yet when rescanning right after it connects.
# A device that creates several event nodes would restart it repeatedly and hit StartLimitBurst, so devices are matched by name.
# Assumes the kanata keyboard is named main (kanata-main.service)
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.yuki.kanata.reconnectDevices = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Input device names (ATTRS{name} in udev) whose connection restarts kanata.";
  };

  config.services.udev.extraRules = lib.concatMapStrings (name: ''
    ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", ATTRS{name}=="${name}", RUN+="${pkgs.systemd}/bin/systemctl --no-block try-restart kanata-main.service"
  '') config.yuki.kanata.reconnectDevices;
}
