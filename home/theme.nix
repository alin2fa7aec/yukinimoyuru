# Look and feel: fonts, the GTK and Qt themes, the cursor and the fcitx5 candidate window, all in the nordfox palette
{
  config,
  lib,
  pkgs,
  dotFile,
  liveDot,
  ...
}:
let
  # Turn "@define-color name #rrggbb;" lines in nordfox.css into { name = "#rrggbb"; }. Used for the fcitx5 theme, which cannot read CSS
  nordfox = lib.listToAttrs (
    map (m: lib.nameValuePair (lib.elemAt m 0) (lib.elemAt m 1)) (
      lib.filter (m: m != null) (
        map (builtins.match "@define-color ([a-z0-9]+) (#[0-9a-f]{6});") (
          lib.splitString "\n" (builtins.readFile (dotFile "theme/nordfox.css"))
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
  # ---- fonts ----
  # Font rendering for this machine's monitors. subpixelRendering must match the panel's subpixel layout, so revisit it on other hardware
  fonts.fontconfig = {
    antialiasing = true;
    hinting = "slight";
    subpixelRendering = "vertical-bgr";
  };

  # ---- GTK and Qt ----
  # Theme GTK and Qt apps with nordfox. Colors come from theme/nordfox.css in the dotfiles repository.
  # GTK overrides libadwaita's named colors on top of adw-gtk3 dark; Qt passes the nordfox palette to qt6ct's Fusion
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    gtk3.extraCss = builtins.readFile (dotFile "theme/gtk.css");
    gtk4.extraCss = builtins.readFile (dotFile "theme/gtk.css");
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

  # ---- fcitx5 candidate window ----
  # nordfox theme for the candidate window. fcitx5's classicui draws it, so it applies to input methods other than karukan too.
  # Colors match fuzzel: a bg1 background with a thin blue border, and sel0 for the selected candidate.
  # Images such as the paging arrows are borrowed from the bundled default-dark. The theme in use is selected in hosts/desktop/configuration.nix
  xdg.dataFile =
    let
      themeDir = "fcitx5/themes/nordfox";
      defaultDark = "${pkgs.fcitx5}/share/fcitx5/themes/default-dark";
      margin = n: {
        Left = n;
        Right = n;
        Top = n;
        Bottom = n;
      };
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
    // lib.listToAttrs (
      map (f: lib.nameValuePair "${themeDir}/${f}" { source = "${defaultDark}/${f}"; }) [
        "prev.png"
        "next.png"
        "radio.png"
        "arrow.png"
      ]
    );
}
