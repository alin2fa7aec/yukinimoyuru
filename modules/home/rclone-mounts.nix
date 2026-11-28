# rclone remotes mounted as directories, one user service (rclone-<name>) each.
# The remotes and their OAuth tokens live in ~/.config/rclone/rclone.conf, written by `rclone config`, so they stay out of the store;
# until it exists the units are skipped.
# The full VFS cache keeps opened files locally and uploads changes in the background, and --poll-interval picks up remote changes.
# They are in default.target, so with linger enabled for the user they mount at boot, before login
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.yuki.rcloneMounts;
  # The user manager has no network-online.target, so wait until systemd-timesyncd has synchronized the clock instead.
  # That also covers a clock that starts hours off, as when the RTC is kept in local time: an OAuth token refreshed
  # before NTP corrects the clock is saved with a wrong expiry, and rclone keeps sending the expired token and gets 401 until then
  waitForTimeSync = pkgs.writeShellScript "wait-for-time-sync" ''
    until [ -e /run/systemd/timesync/synchronized ]; do ${pkgs.coreutils}/bin/sleep 1; done
  '';
in
{
  options.yuki.rcloneMounts = lib.mkOption {
    default = { };
    description = "rclone remotes to mount, keyed by the remote's name in rclone.conf.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.mountpoint = lib.mkOption {
          type = lib.types.str;
          example = "%h/cloud";
          description = "Where to mount the remote. %h expands to the home directory.";
        };
      }
    );
  };

  config = lib.mkIf (cfg != { }) {
    home.packages = [ pkgs.rclone ];

    systemd.user.services = lib.mapAttrs' (
      name: m:
      let
        inherit (m) mountpoint;
      in
      lib.nameValuePair "rclone-${name}" {
        Unit = {
          Description = "rclone remote ${name} mounted at ${mountpoint}";
          ConditionPathExists = "%h/.config/rclone/rclone.conf";
        };
        Service = {
          Type = "notify";
          ExecStartPre = [
            "${waitForTimeSync}"
            "${pkgs.coreutils}/bin/mkdir -p ${mountpoint}"
          ];
          # Offline at boot, the wait times out and Restart tries again
          TimeoutStartSec = "5min";
          ExecStart = lib.concatStringsSep " " [
            "${pkgs.rclone}/bin/rclone mount ${name}: ${mountpoint}"
            "--vfs-cache-mode full --vfs-cache-max-age 720h --vfs-cache-max-size 20G"
            "--dir-cache-time 1h --poll-interval 1m"
          ];
          ExecStop = "/run/wrappers/bin/fusermount3 -u ${mountpoint}";
          # rclone calls fusermount3, which needs the setuid wrapper
          Environment = "PATH=/run/wrappers/bin";
          Restart = "on-failure";
          RestartSec = 15;
        };
        Install.WantedBy = [ "default.target" ];
      }
    ) cfg;
  };
}
