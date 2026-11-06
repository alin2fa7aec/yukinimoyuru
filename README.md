# yukinimoyuru

[日本語](README.ja.md)

NixOS configuration for my desktop PC (hostname `yukiwari`). The system and the user environment are managed together with flakes and home-manager. The application config files themselves live in [dotfiles](https://github.com/alin2fa7aec/dotfiles), which this flake reads as an input and places.

## Overview

- Desktop: niri (a scrollable-tiling Wayland compositor), waybar, fuzzel, swaync, swaylock
- Terminal and shell: WezTerm, Nushell (bash is kept as well), starship
- Japanese input: fcitx5 + karukan (built in `pkgs/` since it is not in nixpkgs)
- Key remapping: kanata (for the JIS layout)
- Colors: GTK, Qt, fcitx5, waybar and others share the nordfox palette
- Editors and tools: vim, Zed, yazi, jj, Claude Code

## Layout

| Path | Contents |
| --- | --- |
| `flake.nix` | Entry point. Defines `nixosConfigurations.yukiwari` |
| `hosts/desktop/` | System configuration (`configuration.nix`) and hardware configuration |
| `home/alin.nix` | User environment via home-manager |
| `pkgs/` | Packages not available in nixpkgs |

## Usage

The configuration expects a checkout of [dotfiles](https://github.com/alin2fa7aec/dotfiles) at `~/!metier/dotfiles`. Files placed as they are, such as the niri and waybar configs, link into that checkout instead of the Nix store, so without it most of them end up as dangling links. Files that nix reads or transforms come from the copy pinned in `flake.lock` and work either way.

```sh
sudo nixos-rebuild switch --flake .#yukiwari
```

Lighter ways to apply a change:

- Files placed as they are, such as the niri and waybar configs, are linked straight to the dotfiles checkout, so edits to them need no rebuild.
- `nu scripts/home-switch.nu` applies only the home-manager part, without sudo. Changes to `home.packages` still need `nixos-rebuild`.
- `sudo -A` asks for the password in a fuzzel prompt, so the rebuild can also run where there is no terminal to type into.

`hosts/desktop/hardware-configuration.nix` is specific to this machine, so regenerate it with `nixos-generate-config` to use the configuration elsewhere.

Wallpapers are not stored in the repository. Put an image at `~/.local/share/wallpaper/<output>` (e.g. `DP-3`) to show it on that monitor.

## License

[MIT](LICENSE)
