# lumier: a museum-shaped viewer for a photo library, browsed from the LAN over HTTP.
# The module comes from the lumier repository (inputs.lumier); see its nix/module.nix for the options.
# Each collection is a museum of its own on its own port, so sharing one port never exposes the other
{ inputs, ... }:
let
  # The libraries and the manifests are data, not configuration, so neither is kept in this repository.
  # The manifests live here as <name>.yaml and the collections are mounted under library/
  dataDir = "/srv/lumier";
  # The originals stay where they are kept and are bind-mounted read-only, one per instance root.
  # lumier refuses symlinks that leave the root, and /home/alin is 0700 so the lumier user could not reach them anyway
  museums = {
    photos = {
      port = 8080;
      collection = "album";
      source = "/srv/photos";
    };
    notes = {
      port = 8081;
      collection = "notes";
      source = "/srv/photos";
    };
  };
  rootOf = museum: "${dataDir}/library/${museum.collection}";
  # Runs f on each museum and builds an attrset from the { name, value } pairs it returns
  forEach = f: builtins.listToAttrs (builtins.attrValues (builtins.mapAttrs f museums));
in
{
  imports = [ inputs.lumier.nixosModules.default ];

  # Owned by alin, so the manifests can be edited without sudo.
  # The services run as the module's own lumier user, which only needs to read them
  systemd.tmpfiles.settings."10-lumier".${dataDir}.d = {
    user = "alin";
    group = "users";
    mode = "0755";
  };

  # Each instance runs as lumier-<name>.service
  services.lumier.instances = builtins.mapAttrs (name: museum: {
    inherit (museum) port;
    # Strings, not paths: a path would copy the library into the store.
    # The manifest is read from disk, so edits apply with `systemctl reload lumier-<name>` without a rebuild
    root = rootOf museum;
    manifest = "${dataDir}/${name}.yaml";
  }) museums;

  fileSystems = forEach (
    _: museum: {
      name = rootOf museum;
      value = {
        device = museum.source;
        fsType = "none";
        options = [
          "bind"
          "ro"
        ];
      };
    }
  );

  # Start after the mount, so the server never scans an empty root
  systemd.services = forEach (
    name: museum: {
      name = "lumier-${name}";
      value.unitConfig.RequiresMountsFor = [ (rootOf museum) ];
    }
  );

  # openFirewall would open the ports on every interface. Open them only on the LAN side, like Samba in nas.nix
  networking.firewall.interfaces.eth0.allowedTCPPorts = map (museum: museum.port) (
    builtins.attrValues museums
  );
}
