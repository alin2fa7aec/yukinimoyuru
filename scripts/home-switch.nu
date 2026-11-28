#!/usr/bin/env nu

# Build and activate only the home-manager part of yukiwari, as the current user and without sudo.
#
# What this applies: files placed by the modules in home/, user services, dconf and other activation steps.
# What it does not: home.packages. With useUserPackages they are installed into the system's
# /etc/profiles/per-user, so adding or removing a package still needs nixos-rebuild.
# The system generation is not updated either; the next nixos-rebuild switch applies the same result.
#
# Extra arguments go to nix build, e.g. to try uncommitted dotfiles that are not linked live:
#   nu scripts/home-switch.nu --override-input dotfiles path:<checkout>
def main [...args: string] {
  let flake = $env.FILE_PWD | path dirname
  let config = $"($flake)#nixosConfigurations.yukiwari.config"
  let user = ^nix eval --raw $"($config).yuki.user" ...$args
  let attr = $"nixosConfigurations.yukiwari.config.home-manager.users.($user).home.activationPackage"
  let out = ^nix build --no-link --print-out-paths $"($flake)#($attr)" ...$args | str trim
  ^$"($out)/activate"
}
