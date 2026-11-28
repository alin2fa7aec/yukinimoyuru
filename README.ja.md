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
| `flake.nix` | エントリーポイント。`nixosConfigurations.yukiwari` を定義し、以下の層を組み合わせる |
| `modules/` | option を宣言するだけで値を持たないモジュール (`nixos/`: LAN のファイル共有と lumier の写真ミュージアム、`home/`: rclone のマウント) |
| `hosts/desktop/` | システム設定 (`configuration.nix`) とハードウェア設定 |
| `home/` | home-manager によるユーザー環境。`alin.nix` が領域ごとのモジュールを読み込む: `desktop.nix` (niri のセッション), `theme.nix`, `shell.nix`, `tools.nix`, `claude.nix` |
| `pkgs/` | nixpkgs に無いパッケージ |
| `ci/private/` | CI で非公開の input の代わりに使う仮の値 |

どのディレクトリを共有や配信に使うか、ローカルネットワークの構成など、マシンではなく持ち主に関わる値はこのリポジトリに置いていない。flake の input `private` から取る。これは公開していないローカルのリポジトリで、その `nixos.nix` と `home.nix` が `modules/` で宣言した option に値を設定する。

## 使い方

[dotfiles](https://github.com/alin2fa7aec/dotfiles) を `~/src/dotfiles` にチェックアウトしてあることを前提にしている。niri や waybar の設定のようにそのまま配置するファイルは、Nix store ではなくこのチェックアウトへリンクするので、チェックアウトが無いとその多くがリンク切れになる。nix が読んだり変換したりするファイルは `flake.lock` で固定したコピーから取るので、チェックアウトが無くても動く。

また、非公開のリポジトリが `~/src/yukinihimuru` にあることも前提にしている。それが無い環境でビルドするには、`--override-input private path:./ci/private` で input を仮の値に差し替える。

```sh
sudo nixos-rebuild switch --flake .#yukiwari
```

もっと軽く反映する方法もある。

- niri や waybar の設定のようにそのまま配置するファイルは、dotfiles のチェックアウトへ直接リンクしているので、編集しても rebuild は要らない。
- `nu scripts/home-switch.nu` は、home-manager の部分だけを sudo なしで反映する。`home.packages` の変更には、これまでどおり `nixos-rebuild` が要る。
- `sudo -A` はパスワードを fuzzel の入力欄で尋ねるので、パスワードを打つ端末が無い場所からでも rebuild できる。

`hosts/desktop/hardware-configuration.nix` はこのマシン固有のものなので、別のマシンで使う場合は `nixos-generate-config` で生成し直す。

壁紙はリポジトリに含めていない。`~/.local/share/wallpaper/<output>` (例: `DP-1`) に画像を置くと、そのモニターに表示される。

## ライセンス

[MIT](LICENSE)
