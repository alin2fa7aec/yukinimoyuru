# The niri session: its programs, the config files they read, the user services that run them, and the input method
{
  lib,
  pkgs,
  inputs,
  dot,
  liveDot,
  ...
}:
let
  # User services that live with the niri session: they start with niri.service, stop with it,
  # and come back 2 seconds after a crash. after and wants add units to wait for
  niriService =
    {
      description,
      exec,
      after ? [ ],
      wants ? [ ],
    }:
    {
      Unit = {
        Description = description;
        PartOf = [ "niri.service" ];
        After = [ "niri.service" ] ++ after;
      }
      // lib.optionalAttrs (wants != [ ]) { Wants = wants; };
      Service = {
        ExecStart = exec;
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "niri.service" ];
    };
in
{
  home.packages =
    (with pkgs; [
      # For the niri session. niri uses xwayland-satellite for X11 apps if it is on PATH
      fuzzel
      waybar
      swaynotificationcenter
      xwayland-satellite
      swaybg
      # Screen lock (swaylock is used from niri's Super+Alt+L and swayidle), media keys
      swaylock
      swayidle
      playerctl
      # Clipboard history (niri's Mod+V)
      cliphist
      wl-clipboard
      # Volume settings (right-click the volume box in waybar), network settings (nm-applet and nm-connection-editor)
      pavucontrol
      networkmanagerapplet
      # PDF and image viewers. File operations are done in yazi
      zathura
      imv
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
      # Web browser
      inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

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

  # Long-running desktop programs are user services bound to niri.service (see niriService) rather than
  # niri's spawn-at-startup. waybar started that way sometimes crashed right after login and never came back
  systemd.user.services = {
    waybar = niriService {
      description = "waybar for niri";
      exec = "${pkgs.waybar}/bin/waybar";
    };

    # Wall clock at the top right of the QHD monitor. It shows the playing audio's spectrum around a circle, so it is drawn by its own program instead of waybar.
    # The vertical bar reserves no space, so leave a right margin of its width (52px) to sit just left of the bar
    clock-ring = niriService {
      description = "wall clock with an audio spectrum ring";
      exec = lib.concatStringsSep " " [
        "${pkgs.callPackage ../pkgs/clock-ring { }}/bin/clock-ring"
        "--output DP-3 --margin-right 52"
        "--theme ${dot + "/theme/nordfox.css"}"
        "--wires ${dot + "/waybar/circuit/wires.json"}"
      ];
      after = [ "pipewire.service" ];
    };

    # Leave notifications to swaync
    swaync = niriService {
      description = "swaync notification center for niri";
      exec = "${pkgs.swaynotificationcenter}/bin/swaync";
    };

    # Turn off the monitors after 36 minutes of inactivity and lock at 49 minutes. Also lock before sleep and on loginctl lock-session.
    # While waybar's idle_inhibitor is on, niri does not report idleness, so neither happens.
    # Start swaylock only if it is not already running, so it is not started again while locked
    swayidle =
      let
        lock = "${pkgs.procps}/bin/pgrep -x swaylock || ${pkgs.swaylock}/bin/swaylock -f";
      in
      niriService {
        description = "swayidle for niri";
        exec = lib.escapeShellArgs [
          "${pkgs.swayidle}/bin/swayidle"
          "-w"
          "timeout"
          "2160"
          "${pkgs.niri}/bin/niri msg action power-off-monitors"
          "timeout"
          "2940"
          lock
          "before-sleep"
          lock
          "lock"
          lock
        ];
      };

    # Authentication dialog for operations that need admin privileges
    polkit-gnome-agent = niriService {
      description = "GNOME polkit authentication agent for niri";
      exec = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
    };

    # Record copied content in the cliphist history. Pick it again from fuzzel with niri's Mod+V
    cliphist = niriService {
      description = "cliphist clipboard history for niri";
      exec = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
    };

    # Show the network and Bluetooth applets in the waybar tray.
    # waybar provides the tray (StatusNotifierWatcher), so start after waybar
    nm-applet = niriService {
      description = "NetworkManager applet for niri";
      exec = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
      after = [ "waybar.service" ];
      wants = [ "waybar.service" ];
    };
    blueman-applet = niriService {
      description = "blueman applet for niri";
      exec = "${pkgs.blueman}/bin/blueman-applet";
      after = [ "waybar.service" ];
      wants = [ "waybar.service" ];
    };

    # Each monitor shows ~/.local/share/wallpaper/<output name> as its wallpaper.
    # Images are not kept in the repository, so put the image you want at this path or symlink it,
    # then apply with systemctl --user restart swaybg
    swaybg = niriService {
      description = "swaybg wallpaper for niri";
      exec = lib.concatStringsSep " " [
        "${pkgs.swaybg}/bin/swaybg"
        "-o DP-3 -i %h/.local/share/wallpaper/DP-3 -m fill"
        "-o HDMI-A-1 -i %h/.local/share/wallpaper/HDMI-A-1 -m fill"
      ];
    };
  };
  # niri.service also pulls in xdg-desktop-autostart.target, which starts the applets' own autostart entries.
  # Whichever copy came up first won, and nm-applet from the entry runs without --indicator.
  # Hide the entries so only the services above start them
  xdg.configFile."autostart/nm-applet.desktop".text = ''
    [Desktop Entry]
    Hidden=true
  '';
  xdg.configFile."autostart/blueman.desktop".text = ''
    [Desktop Entry]
    Hidden=true
  '';

  # ---- input method ----
  # karukan's system dictionary. It is not bundled with the IME, so put the prebuilt release dictionary at the default path
  home.file.".local/share/karukan-im/dict.bin".source = "${
    pkgs.fetchzip {
      url = "https://github.com/togatoga/karukan/releases/download/v0.1.0/dict.tgz";
      hash = "sha256-gWUZH3FQfuksslb/AqUvBU0OVFe9DMg0+8SpGHlASqA=";
      stripRoot = false;
    }
  }/dict.bin";
  # karukan only reads its config file and never writes it, so a link is fine
  xdg.configFile."karukan-im/config.toml".source = liveDot "karukan/config.toml";
}
