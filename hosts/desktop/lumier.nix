# lumier: a museum-shaped viewer for a photo library, browsed from the LAN over HTTP.
# The module comes from the lumier repository (inputs.lumier); see its nix/module.nix for the options
{ inputs, ... }:
let
  port = 8080;
  # The library and the manifest are data, not configuration, so neither is kept in this repository.
  # The manifest lives here and the library is assembled here from the collections below
  dataDir = "/srv/lumier";
  root = "${dataDir}/library";
  # The originals stay where they are kept and are bind-mounted read-only under the root.
  # lumier refuses symlinks that leave the root, and /home/alin is 0700 so the lumier user could not reach them anyway
  collections = {
    album = "/srv/photos";
    notes = "/srv/photos";
  };
  mountPoints = map (name: "${root}/${name}") (builtins.attrNames collections);
in
{
  imports = [ inputs.lumier.nixosModules.default ];

  # Owned by alin, so the manifest can be edited without sudo.
  # The service runs as the module's own lumier user, which only needs to read it
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
    inherit root;
    manifest = "${dataDir}/museum.yaml";
  };

  fileSystems = builtins.listToAttrs (
    map (name: {
      name = "${root}/${name}";
      value = {
        device = collections.${name};
        fsType = "none";
        options = [
          "bind"
          "ro"
        ];
      };
    }) (builtins.attrNames collections)
  );

  # Start after the mounts, so the server never scans a root whose collections are missing
  systemd.services.lumier.unitConfig.RequiresMountsFor = mountPoints;

  # openFirewall would open the port on every interface. Open it only on the LAN side, like Samba in nas.nix
  networking.firewall.interfaces.eth0.allowedTCPPorts = [ port ];
}
