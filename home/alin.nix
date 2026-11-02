{ pkgs, pkgs-unstable, inputs, lib, ... }:
let
  dot = ../dotfiles;
  nushellDir = builtins.path { path = dot + "/nushell"; name = "nushell-config"; };
in
{
  home.username = "alin";
  home.homeDirectory = "/home/alin";

  home.packages =
    (with pkgs; [
      # CLI tools
      ripgrep fd fzf eza bat unar delta jp jq
      # clipboard=unnamed,unnamedplus in vimrc needs a +clipboard build (the system vim is -clipboard)
      vim-full
      # starship's custom.jj
      jj-starship
      # yazi openers (Show media info / Show EXIF)
      mediainfo exiftool
      # develop
      rustup gcc pkg-config gnumake cargo-binstall nodejs bun
      # Claude Code's clangd-lsp plugin
      clang-tools
      # For the niri session. niri uses xwayland-satellite for X11 apps if it is on PATH
      fuzzel waybar swaynotificationcenter xwayland-satellite swaybg
      # Screen lock (swaylock is used from niri's Super+Alt+L and swayidle), media keys
      swaylock swayidle playerctl
      # Clipboard history (niri's Mod+V)
      cliphist wl-clipboard
    ])
    ++ [
      # Power menu (niri's Ctrl+Alt+Delete and the power box in waybar)
      (pkgs.writeShellApplication {
        name = "power-menu";
        runtimeInputs = [ pkgs.fuzzel ];
        text = builtins.readFile (dot + "/fuzzel/power-menu.sh");
      })
      # zed-editor from nixpkgs installs as zeditor, so make it launchable as zed too
      (pkgs.writeShellScriptBin "zed" ''exec ${pkgs-unstable.zed-editor}/bin/zeditor "$@"'')
    ]
    ++ (with pkgs-unstable; [
      zed-editor
      wezterm
      claude-code
    ])
    ++ [
      inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

  # ---- shell ----
  # bashrc has its own prompt and loads zoxide / fzf / ble.sh itself, so turn off Home Manager's bash integrations
  programs.bash = {
    enable = true;
    initExtra = builtins.readFile (dot + "/bash/bashrc");
  };
  # bashrc looks for and loads ~/.local/share/blesh/ble.sh
  home.file.".local/share/blesh".source = "${pkgs.blesh}/share/blesh";

  # config.nu writes starship init to autoload itself and reads color_config.nu from the same directory as env.nu.
  # $nu.env-path resolves to the store path behind the link, so link env.nu and color_config.nu from the same store path.
  programs.nushell = {
    enable = true;
    configFile.source = dot + "/nushell/config.nu";
  };
  xdg.configFile."nushell/env.nu".source = "${nushellDir}/env.nu";
  xdg.configFile."nushell/color_config.nu".source = "${nushellDir}/color_config.nu";

  programs.starship = {
    enable = true;
    enableBashIntegration = false;
    enableNushellIntegration = false;
  };
  xdg.configFile."starship.toml".source = dot + "/starship.toml";

  programs.zoxide = {
    enable = true;
    enableBashIntegration = false;
  };

  # ---- input method ----
  # karukan's system dictionary. It is not bundled with the IME, so put the prebuilt release dictionary at the default path
  home.file.".local/share/karukan-im/dict.bin".source = "${pkgs.fetchzip {
    url = "https://github.com/togatoga/karukan/releases/download/v0.1.0/dict.tgz";
    hash = "sha256-gWUZH3FQfuksslb/AqUvBU0OVFe9DMg0+8SpGHlASqA=";
    stripRoot = false;
  }}/dict.bin";
  # karukan only reads its config file and never writes it, so a link is fine
  xdg.configFile."karukan-im/config.toml".source = dot + "/karukan/config.toml";

  # ---- tools ----
  programs.git = {
    enable = true;
    settings = {
      user.name = "alin";
      user.email = "72394482+alin2fa7aec@users.noreply.github.com";
      init.defaultBranch = "main";
      core.editor = "vim";
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
    };
  };

  programs.jujutsu = {
    enable = true;
    settings = {
      user.name = "alin";
      user.email = "72394482+alin2fa7aec@users.noreply.github.com";
      ui.default-command = "log";
      ui.editor = "vim";
    };
  };

  # ~/.config/git/config is read-only, so gh auth login cannot write a credential helper.
  # programs.gh registers gh auth git-credential on the programs.git side.
  programs.gh = {
    enable = true;
    settings.git_protocol = "https";
  };

  home.file.".vimrc".source = dot + "/vim/vimrc";

  xdg.configFile."wezterm" = {
    source = dot + "/wezterm";
    recursive = true;
  };

  # yz for bash / nushell is defined in each shell's config, so do not use Home Manager's wrapper
  programs.yazi = {
    enable = true;
    enableBashIntegration = false;
    enableNushellIntegration = false;
    plugins.git = {
      package = pkgs.yaziPlugins.git;
      setup = true;
    };
    plugins.jump-to-char = pkgs.yaziPlugins.jump-to-char;
  };
  xdg.configFile."yazi/yazi.toml".source = dot + "/yazi/yazi.toml";
  xdg.configFile."yazi/keymap.toml".source = dot + "/yazi/keymap.toml";

  xdg.configFile."niri/config.kdl".source = dot + "/niri/config.kdl";
  xdg.configFile."waybar/config.jsonc".source = dot + "/waybar/config.jsonc";
  xdg.configFile."waybar/modules.jsonc".source = dot + "/waybar/modules.jsonc";
  xdg.configFile."waybar/style.css".source = dot + "/waybar/style.css";
  xdg.configFile."fuzzel/fuzzel.ini".source = dot + "/fuzzel/fuzzel.ini";
  xdg.configFile."swaync/config.json".source = dot + "/swaync/config.json";
  xdg.configFile."swaync/style.css".source = dot + "/swaync/style.css";
  xdg.configFile."swaylock/config".source = dot + "/swaylock/config";

  # When started from niri's spawn-at-startup, it sometimes crashed right after login and never came back.
  # niri の準備が済んでから起動し、落ちても起動し直すよう、niri.service に結び付けたユーザーサービスにする。
  # Plasma のセッションでは niri.service が動かないので、waybar も起動しない
  systemd.user.services.waybar = {
    Unit = {
      Description = "waybar for niri";
      PartOf = [ "niri.service" ];
      After = [ "niri.service" ];
    };
    Service = {
      ExecStart = "${pkgs.waybar}/bin/waybar";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "niri.service" ];
  };

  # 通知は swaync に任せる。waybar と同じく niri.service に結び付け、Plasma のセッションでは起動しない。
  # Plasma では plasmashell が通知を受け持つので、両方が動くと通知の受け取り手を取り合う
  systemd.user.services.swaync = {
    Unit = {
      Description = "swaync notification center for niri";
      PartOf = [ "niri.service" ];
      After = [ "niri.service" ];
    };
    Service = {
      ExecStart = "${pkgs.swaynotificationcenter}/bin/swaync";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "niri.service" ];
  };

  # 5 分操作がなければモニタを消し、10 分でロックする。スリープの前と loginctl lock-session でもロックする。
  # While waybar's idle_inhibitor is on, niri does not report idleness, so neither happens.
  # Start swaylock only if it is not already running, so it is not started again while locked
  systemd.user.services.swayidle =
    let
      lock = "${pkgs.procps}/bin/pgrep -x swaylock || ${pkgs.swaylock}/bin/swaylock -f";
    in
    {
      Unit = {
        Description = "swayidle for niri";
        PartOf = [ "niri.service" ];
        After = [ "niri.service" ];
      };
      Service = {
        ExecStart = lib.escapeShellArgs [
          "${pkgs.swayidle}/bin/swayidle" "-w"
          "timeout" "300" "${pkgs.niri}/bin/niri msg action power-off-monitors"
          "timeout" "600" lock
          "before-sleep" lock
          "lock" lock
        ];
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "niri.service" ];
    };

  # 管理者権限が要る操作の認証ダイアログ。Plasma のセッションでは Plasma 自身が同じエージェントを起動する
  systemd.user.services.polkit-kde-agent = {
    Unit = {
      Description = "KDE polkit authentication agent for niri";
      PartOf = [ "niri.service" ];
      After = [ "niri.service" ];
    };
    Service = {
      ExecStart = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "niri.service" ];
  };

  # コピーしたものを cliphist の履歴に記録する。niri の Mod+V で fuzzel から選び直す。
  # Plasma のセッションでは Klipper が同じ役をするので、niri.service に結び付ける
  systemd.user.services.cliphist = {
    Unit = {
      Description = "cliphist clipboard history for niri";
      PartOf = [ "niri.service" ];
      After = [ "niri.service" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "niri.service" ];
  };

  # 壁紙はモニターごとに ~/Pictures/wallpaper/<出力名> を表示する。
  # Images are not kept in the repository, so put the image you want at this path or symlink it,
  # then apply with systemctl --user restart swaybg
  systemd.user.services.swaybg = {
    Unit = {
      Description = "swaybg wallpaper for niri";
      PartOf = [ "niri.service" ];
      After = [ "niri.service" ];
    };
    Service = {
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.swaybg}/bin/swaybg"
        "-o DP-3 -i %h/Pictures/wallpaper/DP-3 -m fill"
        "-o HDMI-A-1 -i %h/Pictures/wallpaper/HDMI-A-1 -m fill"
      ];
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "niri.service" ];
  };

  # ---- Claude Code ----
  # managed-settings.json is placed in /etc/claude-code on the system side (hosts/desktop/configuration.nix)
  # The writing-style skill is registered on claude.ai and synced from there; only its lint is deployed here
  home.file.".claude/skills/commit-message".source = dot + "/claude/skills/commit-message";
  home.file.".claude/writing-lint.nu".source = dot + "/claude/writing-lint.nu";
  home.file.".claude/keybindings.json".source = dot + "/claude/keybindings.json";
  home.file.".claude/CLAUDE.md".source = dot + "/claude/CLAUDE.md";

  # Claude Code itself rewrites settings.json (/model, /config, etc.),
  # so instead of a link to the store, put a writable copy only when it is missing
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "$HOME/.claude/settings.json" ]; then
      run mkdir -p "$HOME/.claude"
      run install -m 644 ${dot + "/claude/settings.json"} "$HOME/.claude/settings.json"
    fi
  '';

  home.stateVersion = "26.05";
}
