# lumier: a museum-shaped viewer for photo collections, browsed from the LAN over HTTP.
# The module comes from the lumier repository (inputs.lumier); see its nix/module.nix for the options.
# Each collection is a museum of its own on its own port, so sharing one port never exposes the others
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.yuki.photoMuseums;
  rootOf = museum: "${cfg.dataDir}/library/${museum.collection}";
  # Runs f on each museum and builds an attrset from the { name, value } pairs it returns
  forEach = f: lib.listToAttrs (lib.mapAttrsToList f cfg.museums);
in
{
  imports = [ inputs.lumier.nixosModules.default ];

  options.yuki.photoMuseums = with lib; {
    # The collections and the manifests are data, not configuration, so neither is kept in a repository.
    # The manifests live here as <name>.yaml and the collections are mounted under library/
    dataDir = mkOption {
      type = types.str;
      default = "/srv/lumier";
      description = "Directory holding the manifests and the mount points of the collections.";
    };
    owner = mkOption {
      type = types.str;
      description = "User who owns dataDir, so the manifests can be edited without sudo.";
    };
    museums = mkOption {
      default = { };
      description = "One lumier instance per museum, served as lumier-<name>.service.";
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              port = mkOption { type = types.port; };
              source = mkOption {
                type = types.str;
                description = ''
                  Directory holding the originals. It stays where it is kept and is bind-mounted read-only:
                  lumier refuses symlinks that leave the root, and a 0700 home directory would keep the lumier user out anyway.
                '';
              };
              collection = mkOption {
                type = types.str;
                default = name;
                description = "Name of the mount point under dataDir/library.";
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf (cfg.museums != { }) {
    # The services run as the module's own lumier user, which only needs to read the manifests
    systemd.tmpfiles.settings."10-lumier".${cfg.dataDir}.d = {
      user = cfg.owner;
      group = "users";
      mode = "0755";
    };

    services.lumier.instances = lib.mapAttrs (name: museum: {
      inherit (museum) port;
      # Strings, not paths: a path would copy the collection into the store.
      # The manifest is read from disk, so edits apply with `systemctl reload lumier-<name>` without a rebuild
      root = rootOf museum;
      manifest = "${cfg.dataDir}/${name}.yaml";
    }) cfg.museums;

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

    # openFirewall would open the ports on every interface. Open them only on the LAN side, like the Samba share
    networking.firewall.interfaces.${config.yuki.lan.interface}.allowedTCPPorts = lib.mapAttrsToList (
      _: museum: museum.port
    ) cfg.museums;
  };
}
