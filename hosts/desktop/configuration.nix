{ config, pkgs, pkgs-unstable, inputs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  # boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.kernelPackages = pkgs.linuxPackages;

  # file system
  fileSystems."/".options = [ "compress=zstd" "noatime" ];
  fileSystems."/home".options = [ "compress=zstd" "noatime" ];
  fileSystems."/nix".options = [ "compress=zstd" "noatime" ];
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
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.desktopManager.plasma6.enable = true;
  services.xserver.xkb.layout = "jp";

  # japanese input
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [ fcitx5-mozc ];
  };

  fonts.packages = with pkgs; [
    moralerspace-hw
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
  ];
  fonts.fontconfig.defaultFonts.monospace = [ "Moralerspace Argon HW" "Noto Sans Mono CJK JP" ];

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
    enable32Bit = true;   # For 32-bit games on Steam/Proton
  };
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true;                    # Must be set explicitly
    modesetting.enable = true;
    powerManagement.enable = true;  # Avoids display corruption after resuming from sleep
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;   # Power on the adapter at boot
  };

  # Game
  programs.steam.enable = true;
  programs.gamemode.enable = true;

  # kanata
  # kanata-linux.kbd contains defcfg, so pass it via configFile instead of config
  services.kanata = {
    enable = true;
    keyboards.main = {
      devices = [ ];
      configFile = ../../kanata/kanata-linux.kbd;
    };
  };

  # Claude Code managed settings (apply to all users and take precedence over user settings)
  environment.etc."claude-code/managed-settings.json".source = ../../dotfiles/claude/managed-settings.json;

  # devenv
  programs.nix-ld.enable = true;
  virtualisation.docker.enable = true;

  # browser
  programs.firefox.enable = true;

  # user
  users.users.alin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
  };

  # Nix core
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  environment.systemPackages = with pkgs; [ git vim curl wget ];

  system.stateVersion = "26.05";
}
