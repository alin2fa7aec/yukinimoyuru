{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  dotFile,
  ...
}:
{
  imports = [ ./hardware-configuration.nix ];

  # boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.kernelPackages = pkgs.linuxPackages;

  # file system
  fileSystems."/".options = [
    "compress=zstd"
    "noatime"
  ];
  fileSystems."/home".options = [
    "compress=zstd"
    "noatime"
  ];
  fileSystems."/nix".options = [
    "compress=zstd"
    "noatime"
  ];
  zramSwap.enable = true;

  # network/time/locale
  networking.hostName = "yukiwari";
  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Tokyo";
  time.hardwareClockInLocalTime = true;
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
  xdg.mime.defaultApplications."inode/directory" = "dev.zed.Zed.desktop";
  # blueman-applet for the waybar tray, and the Bluetooth settings
  services.blueman.enable = true;
  services.xserver.xkb.layout = "jp";

  # japanese input
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = [ (pkgs.callPackage ../../pkgs/fcitx5-karukan.nix { }) ];
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

  # GPU
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # For 32-bit games on Steam/Proton
  };
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true; # Must be set explicitly
    modesetting.enable = true;
    powerManagement.enable = true; # Avoids display corruption after resuming from sleep
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true; # Power on the adapter at boot
  };

  # Game
  programs.steam.enable = true;
  programs.gamemode.enable = true;

  # kanata
  # kanata-linux.kbd contains defcfg, so pass it via configFile instead of config.
  # When a rebuild restarts systemd-udevd, kanata can fail to find the keyboard and exit with "No keyboard devices were found".
  # sudo systemctl restart kanata-main.service brings it back
  services.kanata = {
    enable = true;
    keyboards.main = {
      devices = [ ];
      configFile = dotFile "kanata/kanata-linux.kbd";
    };
  };
  # kanata sometimes misses the Bluetooth MX Keys Mini because it cannot grab it yet when rescanning right after it connects.
  # Restart kanata when it connects so it rescans for devices.
  # Matching devices that create several event nodes would restart it repeatedly and hit StartLimitBurst, so narrow it to one by name.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", ATTRS{name}=="MX Keys Mini", RUN+="${pkgs.systemd}/bin/systemctl --no-block try-restart kanata-main.service"
  '';

  # Claude Code managed settings (apply to all users and take precedence over user settings)
  environment.etc."claude-code/managed-settings.json".source = dotFile "claude/managed-settings.json";

  # devenv
  programs.nix-ld.enable = true;
  virtualisation.docker.enable = true;

  # browser
  programs.firefox.enable = true;

  # user
  users.users.alin = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
    ];
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
