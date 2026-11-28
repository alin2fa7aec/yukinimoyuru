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
| `flake.nix` | Entry point. Defines `nixosConfigurations.yukiwari` and puts the layers below together |
| `modules/` | Modules with options and no values of their own (`nixos/`: the user, kanata, the LAN file share, the lumier photo museums; `home/`: the dotfiles checkout, the monitors, rclone mounts) |
| `hosts/desktop/` | System configuration (`configuration.nix`) |
| `home/` | User environment via home-manager. `default.nix` imports one module per area: `desktop.nix` (the niri session), `theme.nix`, `shell.nix`, `tools.nix`, `claude.nix` |
| `pkgs/` | Packages not available in nixpkgs |
| `ci/private/` | Placeholder values standing in for the private input in CI |

This repository holds the mechanisms and the desktop built from them, but nothing specific to its owner or hardware: the user, the disks, drivers and monitors (`hardware-configuration.nix` included), the local network, what is shared and served, and personal software. Those come from the flake input `private`, a local unpublished repository whose `nixos.nix` and `home.nix` set the options declared under `modules/` and any other option directly.

## Usage

The configuration expects a checkout of [dotfiles](https://github.com/alin2fa7aec/dotfiles) at the path given in `yuki.dotfiles.checkout`. Files placed as they are, such as the niri and waybar configs, link into that checkout instead of the Nix store, so without it most of them end up as dangling links. Files that nix reads or transforms come from the copy pinned in `flake.lock` and work either way.

It also expects the private repository at `/etc/nixos`. To build without it, point the input at the placeholders with `--override-input private path:./ci/private`.

```sh
sudo nixos-rebuild switch --flake .#yukiwari
```

Lighter ways to apply a change:

- Files placed as they are, such as the niri and waybar configs, are linked straight to the dotfiles checkout, so edits to them need no rebuild.
- `nu scripts/home-switch.nu` applies only the home-manager part, without sudo. Changes to `home.packages` still need `nixos-rebuild`.
- `sudo -A` asks for the password in a fuzzel prompt, so the rebuild can also run where there is no terminal to type into.

Wallpapers are not stored in the repository. Put an image at `~/.local/share/wallpaper/<output>`, named after the monitor's connector, to show it on that monitor.

## License

[MIT](LICENSE)
