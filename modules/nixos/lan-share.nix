# File sharing over the LAN, so Windows, macOS, Linux and phones can all reach one directory over SMB.
# Samba keeps its own password database, so add the user once with `sudo smbpasswd -a <user>`
{ config, lib, ... }:
let
  cfg = config.yuki.lanShare;
  inherit (config.yuki.lan) interface;
  dir = {
    inherit (cfg) user;
    group = "users";
    mode = "0755";
  };
in
{
  options.yuki.lanShare = with lib; {
    enable = mkEnableOption "a Samba share on the LAN";
    name = mkOption {
      type = types.str;
      default = "nas";
      description = "Share name that clients see.";
    };
    path = mkOption {
      type = types.str;
      description = "Directory to share. Samba opens files as the logged-in user, so it can sit in a 0700 home directory.";
    };
    user = mkOption {
      type = types.str;
      description = "Owner of the share and the only user allowed in.";
    };
    subdirs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "inbox" ];
      description = "Directories created inside the share, such as a drop folder for uploads from a phone.";
    };
    hostsAllow = mkOption {
      type = types.listOf types.str;
      example = [ "192.168.1." ];
      description = "LAN clients to accept, in the syntax of Samba's `hosts allow`. Localhost is always accepted.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create the share as a btrfs subvolume (a plain directory on other file systems),
    # so it can be snapshotted on its own later
    systemd.tmpfiles.settings."10-lan-share" = {
      ${cfg.path}.v = dir;
    }
    // lib.genAttrs (map (d: "${cfg.path}/${d}") cfg.subdirs) (_: {
      d = dir;
    });

    services.samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          "server string" = config.networking.hostName;
          # Only accept the LAN and localhost. The global IPv6 address is left out because its prefix comes from the ISP,
          # so wsdd and avahi below announce only the IPv4 address
          "hosts allow" = lib.concatStringsSep " " (
            cfg.hostsAllow
            ++ [
              "127.0.0.1"
              "::1"
            ]
          );
          "hosts deny" = "0.0.0.0/0";
          "server min protocol" = "SMB3";
          "map to guest" = "never";
          # Apple clients (the iOS Files app, Finder) write metadata as named streams when creating files and folders,
          # and fail with OSStatus -61 when the server cannot store them. fruit and streams_xattr keep them in xattrs.
          # These must be the same on every share, so set them here
          "vfs objects" = "catia fruit streams_xattr";
          "fruit:metadata" = "stream";
          # Without this, fruit changes file modes to match the NFS ACEs that macOS sends
          "fruit:nfs_aces" = "no";
          "fruit:wipe_intentionally_left_blank_rfork" = "yes";
          "fruit:delete_empty_adfiles" = "yes";
        };
        ${cfg.name} = {
          inherit (cfg) path;
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = cfg.user;
          "create mask" = "0644";
          "directory mask" = "0755";
        };
      };
    };

    # Show the server under "Network" in Windows Explorer
    services.samba-wsdd = {
      enable = true;
      openFirewall = true;
      inherit interface;
      extraOptions = [
        "--shortlog"
        "--ipv4only"
      ];
    };

    # Announce it over mDNS, so macOS and Linux file managers list it and <hostname>.local resolves
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
      # Leave out IPv6 and other interfaces such as Docker bridges, so clients only get the address Samba accepts
      ipv6 = false;
      allowInterfaces = [ interface ];
      publish = {
        enable = true;
        userServices = true;
      };
      # ipv6 = false only stops mDNS traffic over IPv6; the IPv6 addresses are still announced over IPv4 without this.
      # extraConfig goes after the [reflector] section, so open [publish] again
      extraConfig = ''
        [publish]
        publish-aaaa-on-ipv4=no
      '';
    };
  };
}
