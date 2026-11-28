{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  inputs,
  dotFile,
  ...
}:
{
  # The hardware (disks, boot loader, GPU, clock) is described by the private input, along with its hardware-configuration.nix

  boot.kernelPackages = pkgs.linuxPackages;
  zramSwap.enable = true;

  # network/time/locale
  networking.hostName = "yukiwari";
  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "ja_JP.UTF-8";
    LC_MEASUREMENT = "ja_JP.UTF-8";
    LC_PAPER = "ja_JP.UTF-8";
  };

  # desktop
  # niri is the only desktop.
  # The niri module provides the file chooser (xdg-desktop-portal-gnome and Nautilus) and password storage (gnome-keyring)
  programs.niri.enable = true;
  # Login screen. niri is the only session, so tuigreet starts niri-session
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings.default_session.command = lib.escapeShellArgs [
      "${pkgs.tuigreet}/bin/tuigreet"
      "--time"
      "--remember"
      "--asterisks"
      "--cmd"
      "niri-session"
    ];
  };
  # home-manager's dconf.settings (GTK dark mode) needs the dconf database and service.
  # Desktop environments such as GNOME and Plasma turn this on themselves, but the niri module does not
  programs.dconf.enable = true;
  # The app xdg-open uses for directories. Otherwise zathura-cb (a comic book plugin), which claims to handle directories, gets picked.
  # Zen Browser rewrites ~/.config/mimeapps.list, so write to /etc/xdg/mimeapps.list
  # mimeapps.list takes no wildcards such as video/*, so list the common video types for Glide (installed in home/desktop.nix).
  # Without this, xdg-open picks Firefox, the only app that claims them
  xdg.mime.defaultApplications = {
    "inode/directory" = "dev.zed.Zed.desktop";
  }
  // lib.genAttrs [
    "video/mp4"
    "video/x-matroska"
    "video/webm"
    "video/quicktime"
    "video/x-msvideo"
    "video/mpeg"
    "video/ogg"
    "video/x-flv"
    "video/3gpp"
    "video/mp2t"
  ] (_: "net.base_art.Glide.desktop");
  # blueman-applet for the waybar tray, and the Bluetooth settings
  services.blueman.enable = true;
  services.xserver.xkb.layout = "jp";

  # japanese input
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = [ (pkgs.callPackage ../../pkgs/fcitx5-karukan.nix { src = inputs.karukan; }) ];
    # Theme for the candidate window (home/theme.nix puts it in ~/.local/share/fcitx5/themes/nordfox).
    # Using the accent color changes the selected candidate's color to the desktop's, so turn it off.
    # This is written to /etc/xdg, so saving the Classic User Interface in fcitx5-configtool makes the ~/.config copy take precedence
    fcitx5.settings.addons.classicui.globalSection = {
      Theme = "nordfox";
      DarkTheme = "nordfox";
      UseAccentColor = "False";
    };
  };

  fonts.packages = with pkgs; [
    moralerspace-hw
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    # For waybar icons (a Nerd Font containing only icons)
    nerd-fonts.symbols-only
  ];
  fonts.fontconfig.defaultFonts.monospace = [
    "Moralerspace Argon HW"
    "Noto Sans Mono CJK JP"
  ];

  # audio
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # GPU (the driver is chosen by the private input)
  hardware.graphics.enable = true;

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true; # Power on the adapter at boot
  };

  # kanata
  # kanata-linux.kbd contains defcfg, so pass it via configFile instead of config.
  # When a rebuild restarts systemd-udevd, kanata can fail to find the keyboard and exit with "No keyboard devices were found".
  # sudo systemctl restart kanata-main.service brings it back.
  # Keyboards that kanata misses when they connect are listed in yuki.kanata.reconnectDevices (modules/nixos/kanata.nix)
  services.kanata = {
    enable = true;
    keyboards.main = {
      devices = [ ];
      configFile = dotFile "kanata/kanata-linux.kbd";
    };
  };

  # Claude Code managed settings (apply to all users and take precedence over user settings).
  # Values in env are paths, and a leading ~/ in them is expanded to the desktop user's home directory here
  environment.etc."claude-code/managed-settings.json".text =
    let
      settings = lib.importJSON (dotFile "claude/managed-settings.json");
      home = config.users.users.${config.yuki.user}.home;
      expandHome = v: if lib.hasPrefix "~/" v then "${home}/${lib.removePrefix "~/" v}" else v;
    in
    builtins.toJSON (settings // { env = lib.mapAttrs (_: expandHome) (settings.env or { }); });

  # devenv
  programs.nix-ld.enable = true;
  virtualisation.docker.enable = true;

  # browser
  programs.firefox.enable = true;

  # user
  users.users.${config.yuki.user} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
    ];
    # Start the user manager at boot, so user services in default.target (the rclone mounts) run before login
    linger = true;
  };

  # sudo -A asks for the password in a fuzzel prompt instead of the terminal.
  # Claude Code's ! has no terminal to type a password into, so this lets `! sudo -A nixos-rebuild ...` run from there.
  # The password is still asked every time
  environment.etc."sudo.conf".text = ''
    Path askpass ${pkgs.writeShellScript "sudo-askpass" ''
      exec ${pkgs.fuzzel}/bin/fuzzel --dmenu --password --prompt-only "sudo: " </dev/null
    ''}
  '';

  # Nix core
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  # Keep ~/.nix-profile and ~/.nix-defexpr out of ~ and put them under ~/.local/state/nix.
  # home-manager puts packages in /etc/profiles/per-user, so ~/.nix-profile was unused and kept being recreated as a dangling link
  nix.settings.use-xdg-base-directories = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
  ];

  # editor: standardize on vim and leave out NixOS's default nano
  programs.nano.enable = false;
  programs.vim = {
    enable = true;
    defaultEditor = true; # EDITOR=vim
  };
  environment.variables.VISUAL = "vim";

  system.stateVersion = "26.05";
}
