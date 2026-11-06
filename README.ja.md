# yukinimoyuru

[English](README.md)

デスクトップ PC (ホスト名 `yukiwari`) の NixOS 設定。flakes と home-manager で、システムとユーザー環境をまとめて管理している。アプリケーションの設定ファイルそのものは [dotfiles](https://github.com/alin2fa7aec/dotfiles) にあり、この flake が input として読んで配置する。

## 概要

- デスクトップ: niri (スクロール型タイリングの Wayland コンポジター), waybar, fuzzel, swaync, swaylock
- ターミナルとシェル: WezTerm, Nushell (bash も残している), starship
- 日本語入力: fcitx5 + karukan (nixpkgs に無いため `pkgs/` でビルドしている)
- キーリマップ: kanata (JIS 配列向け)
- 配色: GTK, Qt, fcitx5, waybar などで nordfox のパレットを共有している
- エディターとツール: vim, Zed, yazi, jj, Claude Code

## 構成

| パス | 内容 |
| --- | --- |
| `flake.nix` | エントリーポイント。`nixosConfigurations.yukiwari` を定義する |
| `hosts/desktop/` | システム設定 (`configuration.nix`) とハードウェア設定 |
| `home/alin.nix` | home-manager によるユーザー環境 |
| `pkgs/` | nixpkgs に無いパッケージ |

## 使い方

```sh
sudo nixos-rebuild switch --flake .#yukiwari
```

`hosts/desktop/hardware-configuration.nix` はこのマシン固有のものなので、別のマシンで使う場合は `nixos-generate-config` で生成し直す。

壁紙はリポジトリに含めていない。`~/.local/share/wallpaper/<output>` (例: `DP-3`) に画像を置くと、そのモニターに表示される。

## ライセンス

[MIT](LICENSE)
