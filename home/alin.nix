{ config, pkgs, pkgs-unstable, inputs, lib, ... }:
let
  # The dotfiles are used in two ways:
  # - dot: the copy pinned by flake.lock, for files nix reads or transforms (readFile, generated colors, service arguments)
  # - liveDot: a link straight into the checkout, for files placed as they are. Edits take effect without a rebuild
  # Assumes the checkout lives at ~/!metier/dotfiles
  dot = inputs.dotfiles;
  liveDot = path: config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/!metier/dotfiles/${path}";
  nushellDir = "${dot}/nushell";
  # Turn "@define-color name #rrggbb;" lines in nordfox.css into { name = "#rrggbb"; }. Used for the fcitx5 theme, which cannot read CSS
  nordfox = lib.listToAttrs (
    map (m: lib.nameValuePair (lib.elemAt m 0) (lib.elemAt m 1)) (
      lib.filter (m: m != null) (
        map (builtins.match "@define-color ([a-z0-9]+) (#[0-9a-f]{6});") (
          lib.splitString "\n" (builtins.readFile (dot + "/theme/nordfox.css"))
        )
      )
    )
  );
  # Color scheme files for qt5ct and qt6ct. Colors are listed in QPalette ColorRole order (WindowText, Button, ..., Accent).
  # Qt 5 has no Accent, so qt5ct gets only the first 21 colors (n picks the count).
  # Only disabled text is dimmed to fg3; everything else uses the same colors for active and inactive
  qtColors =
    n:
    let
      palette =
        disabled:
        let
          text = if disabled then nordfox.fg3 else nordfox.fg1;
        in
        lib.concatStringsSep ", " (
          lib.take n (
            with nordfox;
            [
              text # WindowText
              bg2 # Button
              bg4 # Light
              bg3 # Midlight
              bg0 # Dark
              bg2 # Mid
              text # Text
              white # BrightText
              text # ButtonText
              bg0 # Base
              bg1 # Window
              "#000000" # Shadow
              sel0 # Highlight
              fg1 # HighlightedText
              blue # Link
              magenta # LinkVisited
              bg1 # AlternateBase
              "#000000" # NoRole
              bg2 # ToolTipBase
              fg1 # ToolTipText
              fg3 # PlaceholderText
              blue # Accent
            ]
          )
        );
    in
    lib.generators.toINI { } {
      ColorScheme = {
        active_colors = palette false;
        inactive_colors = palette false;
        disabled_colors = palette true;
      };
    };
  # User services for applets shown in the waybar tray
  applet = description: exec: {
    Unit = {
      Description = description;
      PartOf = [ "niri.service" ];
      After = [ "waybar.service" ];
      Wants = [ "waybar.service" ];
    };
    Service = {
      ExecStart = exec;
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "niri.service" ];
  };
  qtctSettings = name: {
    Appearance = {
      style = "Fusion";
      custom_palette = true;
      color_scheme_path = "${config.xdg.configHome}/${name}/colors/nordfox.conf";
      icon_theme = "Papirus-Dark";
      # Leave file chooser and similar dialogs to the portal (Nautilus), consistent with GTK apps
      standard_dialogs = "xdgdesktopportal";
    };
  };
in
{
  home.username = "alin";
  home.homeDirectory = "/home/alin";

  home.packages =
    (with pkgs; [
      # CLI tools
      ripgrep fd fzf eza bat unar zip delta jp jq
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
      # Volume settings (right-click the volume box in waybar), network settings (nm-applet and nm-connection-editor)
      pavucontrol networkmanagerapplet
      # PDF and image viewers. File operations are done in yazi
      zathura imv
      # Cropping and annotating images (satty --filename <image>)
      satty
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
  xdg.configFile."starship.toml".source = liveDot "starship.toml";

  programs.zoxide = {
    enable = true;
    enableBashIntegration = false;
  };

  # ---- xdg user dirs ----
  # Create only ~/downloads in the home directory.
  # xdg-user-dirs-update fills in directories missing from user-dirs.dirs with defaults like ~/Pictures,
  # so disable unused ones by setting them to $HOME (user-dirs.dirs(5)).
  # home-manager also writes enabled=False to user-dirs.conf, so they are not recreated at login
  xdg.userDirs =
    let
      home = config.home.homeDirectory;
    in
    {
      enable = true;
      createDirectories = true;
      download = "${home}/downloads";
      desktop = home;
      documents = home;
      music = home;
      pictures = home;
      projects = home;
      publicShare = home;
      templates = home;
      videos = home;
    };

  # ---- fonts ----
  # Carry over the values chosen in Plasma's font settings
  fonts.fontconfig = {
    antialiasing = true;
    hinting = "slight";
    subpixelRendering = "vertical-bgr";
  };

  # ---- look ----
  # Theme GTK and Qt apps with nordfox. Colors come from theme/nordfox.css in the dotfiles repository.
  # GTK overrides libadwaita's named colors on top of adw-gtk3 dark; Qt passes the nordfox palette to qt6ct's Fusion
  gtk = {
    enable = true;
    theme = { name = "adw-gtk3-dark"; package = pkgs.adw-gtk3; };
    iconTheme = { name = "Papirus-Dark"; package = pkgs.papirus-icon-theme; };
    gtk3.extraCss = builtins.readFile (dot + "/theme/gtk.css");
    gtk4.extraCss = builtins.readFile (dot + "/theme/gtk.css");
  };
  # @import in gtk.css resolves relative to gtk-3.0 and gtk-4.0
  xdg.configFile."gtk-3.0/nordfox.css".source = liveDot "theme/nordfox.css";
  xdg.configFile."gtk-4.0/nordfox.css".source = liveDot "theme/nordfox.css";
  # libadwaita apps and the portal decide dark mode from this setting, not the theme name
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    gtk.enable = true;
  };

  qt = {
    enable = true;
    platformTheme.name = "qtct";
    qt6ctSettings = qtctSettings "qt6ct";
    qt5ctSettings = qtctSettings "qt5ct";
  };
  xdg.configFile."qt6ct/colors/nordfox.conf".text = qtColors 22;
  xdg.configFile."qt5ct/colors/nordfox.conf".text = qtColors 21;

  # ---- input method ----
  # karukan's system dictionary. It is not bundled with the IME, so put the prebuilt release dictionary at the default path
  home.file.".local/share/karukan-im/dict.bin".source = "${pkgs.fetchzip {
    url = "https://github.com/togatoga/karukan/releases/download/v0.1.0/dict.tgz";
    hash = "sha256-gWUZH3FQfuksslb/AqUvBU0OVFe9DMg0+8SpGHlASqA=";
    stripRoot = false;
  }}/dict.bin";
  # karukan only reads its config file and never writes it, so a link is fine
  xdg.configFile."karukan-im/config.toml".source = liveDot "karukan/config.toml";

  # nordfox theme for the candidate window. fcitx5's classicui draws it, so it applies to input methods other than karukan too.
  # Colors match fuzzel: a bg1 background with a thin blue border, and sel0 for the selected candidate.
  # Images such as the paging arrows are borrowed from the bundled default-dark. The theme in use is selected in hosts/desktop/configuration.nix
  xdg.dataFile =
    let
      themeDir = "fcitx5/themes/nordfox";
      defaultDark = "${pkgs.fcitx5}/share/fcitx5/themes/default-dark";
      margin = n: { Left = n; Right = n; Top = n; Bottom = n; };
    in
    {
      "${themeDir}/theme.conf".text = lib.generators.toINI { } {
        Metadata = {
          Name = "Nordfox";
          Version = 1;
          Author = "alin";
          Description = "nordfox (nightfox.nvim)";
          ScaleWithDPI = "True";
        };
        InputPanel = {
          NormalColor = nordfox.fg1;
          HighlightCandidateColor = nordfox.fg1;
          # The part of the preedit string currently being converted
          HighlightColor = nordfox.cyan;
          HighlightBackgroundColor = nordfox.sel0;
          PageButtonAlignment = "Last Candidate";
        };
        "InputPanel/TextMargin" = margin 5;
        "InputPanel/ContentMargin" = margin 2;
        "InputPanel/Background" = {
          Color = nordfox.bg1;
          BorderColor = nordfox.blue;
          BorderWidth = 1;
        };
        "InputPanel/Background/Margin" = margin 1;
        "InputPanel/Highlight".Color = nordfox.sel0;
        "InputPanel/Highlight/Margin" = margin 5;
        "InputPanel/PrevPage".Image = "prev.png";
        "InputPanel/PrevPage/ClickMargin" = margin 5;
        "InputPanel/NextPage".Image = "next.png";
        "InputPanel/NextPage/ClickMargin" = margin 5;
        Menu = {
          NormalColor = nordfox.fg1;
          HighlightCandidateColor = nordfox.fg1;
        };
        "Menu/Background" = {
          Color = nordfox.bg1;
          BorderColor = nordfox.blue;
          BorderWidth = 1;
        };
        "Menu/Background/Margin" = margin 1;
        "Menu/ContentMargin" = margin 2;
        "Menu/Highlight".Color = nordfox.sel0;
        "Menu/Highlight/Margin" = margin 5;
        "Menu/Separator".Color = nordfox.bg3;
        "Menu/CheckBox".Image = "radio.png";
        "Menu/SubMenu".Image = "arrow.png";
        "Menu/TextMargin" = margin 5;
      };
    }
    // lib.listToAttrs (map
      (f: lib.nameValuePair "${themeDir}/${f}" { source = "${defaultDark}/${f}"; })
      [ "prev.png" "next.png" "radio.png" "arrow.png" ]
    );

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

  home.file.".vimrc".source = liveDot "vim/vimrc";

  # Link each file rather than the directory: ~/.config/wezterm is already a real directory from earlier generations
  xdg.configFile."wezterm/wezterm.lua".source = liveDot "wezterm/wezterm.lua";
  xdg.configFile."wezterm/wezterm_common.lua".source = liveDot "wezterm/wezterm_common.lua";
  xdg.configFile."wezterm/keybinds.lua".source = liveDot "wezterm/keybinds.lua";
  xdg.configFile."wezterm/keybinds_common.lua".source = liveDot "wezterm/keybinds_common.lua";

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
    # session shares yank and cut state with other instances via DDS
    # linemode = "size_and_mtime" in yazi.toml is not built in, so define it here
    initLua = ''
      require("session"):setup({ sync_yanked = true })

      function Linemode:size_and_mtime()
        local time = math.floor(self._file.cha.mtime or 0)
        if time == 0 then
          time = ""
        elseif os.date("%Y", time) == os.date("%Y") then
          time = os.date("%b %d %H:%M", time)
        else
          time = os.date("%b %d  %Y", time)
        end

        local size = self._file:size()
        return string.format("%s %s", size and ya.readable_size(size) or "-", time)
      end
    '';
  };
  xdg.configFile."yazi/yazi.toml".source = liveDot "yazi/yazi.toml";
  xdg.configFile."yazi/keymap.toml".source = liveDot "yazi/keymap.toml";

  xdg.configFile."niri/config.kdl".source = liveDot "niri/config.kdl";
  xdg.configFile."waybar/config.jsonc".source = liveDot "waybar/config.jsonc";
  xdg.configFile."waybar/modules.jsonc".source = liveDot "waybar/modules.jsonc";
  xdg.configFile."waybar/style.css".source = liveDot "waybar/style.css";
  # @import in style.css resolves relative to ~/.config/waybar, so put it in the same directory
  xdg.configFile."waybar/nordfox.css".source = liveDot "theme/nordfox.css";
  xdg.configFile."fuzzel/fuzzel.ini".source = liveDot "fuzzel/fuzzel.ini";
  xdg.configFile."swaync/config.json".source = liveDot "swaync/config.json";
  xdg.configFile."swaync/style.css".source = liveDot "swaync/style.css";
  xdg.configFile."swaync/nordfox.css".source = liveDot "theme/nordfox.css";
  xdg.configFile."swaylock/config".source = liveDot "swaylock/config";

  # When started from niri's spawn-at-startup, it sometimes crashed right after login and never came back.
  # Make it a user service bound to niri.service so it starts once niri is ready and restarts if it crashes
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

  # Wall clock at the top right of the QHD monitor. It shows the playing audio's spectrum around a circle, so it is drawn by its own program instead of waybar.
  # The vertical bar reserves no space, so leave a right margin of its width (52px) to sit just left of the bar
  systemd.user.services.clock-ring = {
    Unit = {
      Description = "wall clock with an audio spectrum ring";
      PartOf = [ "niri.service" ];
      After = [ "niri.service" "pipewire.service" ];
    };
    Service = {
      ExecStart = "${pkgs.callPackage ../pkgs/clock-ring { }}/bin/clock-ring --output DP-3 --margin-right 52 --theme ${dot + "/theme/nordfox.css"} --wires ${../pkgs/clock-ring/wires.json}";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "niri.service" ];
  };

  # Leave notifications to swaync. Bound to niri.service like waybar
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

  # Turn off the monitors after 36 minutes of inactivity and lock at 49 minutes. Also lock before sleep and on loginctl lock-session.
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
          "timeout" "2160" "${pkgs.niri}/bin/niri msg action power-off-monitors"
          "timeout" "2940" lock
          "before-sleep" lock
          "lock" lock
        ];
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "niri.service" ];
    };

  # Authentication dialog for operations that need admin privileges
  systemd.user.services.polkit-gnome-agent = {
    Unit = {
      Description = "GNOME polkit authentication agent for niri";
      PartOf = [ "niri.service" ];
      After = [ "niri.service" ];
    };
    Service = {
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "niri.service" ];
  };

  # Record copied content in the cliphist history. Pick it again from fuzzel with niri's Mod+V
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

  # Show the network and Bluetooth applets in the waybar tray.
  # waybar provides the tray (StatusNotifierWatcher), so start after waybar
  systemd.user.services.nm-applet = applet "NetworkManager applet for niri" "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
  systemd.user.services.blueman-applet = applet "blueman applet for niri" "${pkgs.blueman}/bin/blueman-applet";

  # Each monitor shows ~/.local/share/wallpaper/<output name> as its wallpaper.
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
        "-o DP-3 -i %h/.local/share/wallpaper/DP-3 -m fill"
        "-o HDMI-A-1 -i %h/.local/share/wallpaper/HDMI-A-1 -m fill"
      ];
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "niri.service" ];
  };

  # ---- Claude Code ----
  # managed-settings.json is placed in /etc/claude-code on the system side (hosts/desktop/configuration.nix)
  # The writing-style skill comes from claude.ai (its source is in dotfiles); only its lint is deployed here.
  # The lint runs from the PostToolUse hook, so unlike other placed files it stays pinned in the store
  # and changes only on a rebuild
  home.file.".claude/writing-lint.nu".source = dot + "/claude/writing-lint.nu";
  home.file.".claude/CLAUDE.md".source = liveDot "claude/CLAUDE.md";
  home.file.".claude/skills/commit-message".source = liveDot "claude/skills/commit-message";
  home.file.".claude/keybindings.json".source = liveDot "claude/keybindings.json";

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
