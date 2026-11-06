# yukinimoyuru

[日本語](README.ja.md)

NixOS configuration and dotfiles for my desktop PC (hostname `yukiwari`). The system and the user environment are managed together with flakes and home-manager.

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
| `dotfiles/` | Application config files, placed by `home/alin.nix` |
| `kanata/` | kanata configuration |
| `pkgs/` | Packages not available in nixpkgs |

## Usage

```sh
sudo nixos-rebuild switch --flake .#yukiwari
```

`hosts/desktop/hardware-configuration.nix` is specific to this machine, so regenerate it with `nixos-generate-config` to use the configuration elsewhere.

Wallpapers are not stored in the repository. Put an image at `~/.local/share/wallpaper/<output>` (e.g. `DP-3`) to show it on that monitor.

## License

[MIT](LICENSE)
