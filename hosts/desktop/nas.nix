# File sharing over the LAN (proof of concept).
# Shares ~/!partage/kamakura over SMB so Windows, macOS, Linux and phones can all reach it.
# Samba keeps its own password database, so add the user once with `sudo smbpasswd -a alin`
{ ... }:
let
  # Samba opens files as the logged-in user (alin), so the share can sit in the 0700 home directory
  sharePath = "/home/alin/!partage/kamakura";
in
{
  # Create the share as a btrfs subvolume (a plain directory on other file systems),
  # so it can be snapshotted on its own later
  systemd.tmpfiles.settings."10-nas" = {
    ${sharePath}.v = {
      user = "alin";
      group = "users";
      mode = "0755";
    };
    # Uploads from the phone land here with no folder to choose, and get sorted into the library later
    "${sharePath}/inbox".d = {
      user = "alin";
      group = "users";
      mode = "0755";
    };
  };

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "server string" = "yukiwari";
        # Only accept the LAN (this machine is 172.16.10.25 on enp4s0) and localhost.
        # The global IPv6 address is left out because its prefix comes from the ISP,
        # so wsdd and avahi below announce only the IPv4 address
        "hosts allow" = "172.16. 127.0.0.1 ::1";
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
      nas = {
        path = sharePath;
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "alin";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
    };
  };

  # Show the server under "Network" in Windows Explorer
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
    interface = "enp4s0";
    extraOptions = [
      "--shortlog"
      "--ipv4only"
    ];
  };

  # Announce it over mDNS, so macOS and Linux file managers list it and yukiwari.local resolves
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    # Leave out IPv6 and the Docker bridges, so clients only get the address Samba accepts
    ipv6 = false;
    allowInterfaces = [ "enp4s0" ];
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
}
