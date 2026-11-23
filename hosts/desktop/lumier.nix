# lumier: a museum-shaped viewer for a photo library, browsed from the LAN over HTTP.
# The module comes from the lumier repository (inputs.lumier); see its nix/module.nix for the options
{ inputs, ... }:
let
  port = 8080;
  # The library and the manifest are data, not configuration, so neither is kept in this repository.
  # Both live here instead, and nothing below depends on what they contain or where they came from
  dataDir = "/srv/lumier";
in
{
  imports = [ inputs.lumier.nixosModules.default ];

  # Owned by alin, so photos and the manifest can be put in place without sudo.
  # The service runs as the module's own lumier user, which only needs to read them
  systemd.tmpfiles.settings."10-lumier".${dataDir}.d = {
    user = "alin";
    group = "users";
    mode = "0755";
  };

  services.lumier = {
    enable = true;
    inherit port;
    # Strings, not paths: a path would copy the library into the store.
    # The manifest is read from disk, so edits apply with `systemctl reload lumier` without a rebuild
    root = "${dataDir}/library";
    manifest = "${dataDir}/museum.yaml";
  };

  # openFirewall would open the port on every interface. Open it only on the LAN side, like Samba in nas.nix
  networking.firewall.interfaces.eth0.allowedTCPPorts = [ port ];
}
