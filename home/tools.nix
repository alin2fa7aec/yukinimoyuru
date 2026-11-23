# Command-line tools, development toolchains, version control, vim, yazi and Zed
{
  lib,
  pkgs,
  pkgs-unstable,
  liveDot,
  ...
}:
let
  # Identity shared by git and jj. The address is GitHub's noreply one, so it is safe to publish
  user = {
    name = "alin";
    email = "72394482+alin2fa7aec@users.noreply.github.com";
  };
in
{
  home.packages =
    (with pkgs; [
      # CLI tools
      ripgrep
      fd
      fzf
      eza
      bat
      unar
      zip
      delta
      jp
      jq
      # clipboard=unnamed,unnamedplus in vimrc needs a +clipboard build (the system vim is -clipboard)
      vim-full
      # yazi openers (Show media info / Show EXIF)
      mediainfo
      exiftool
      # develop
      gcc
      pkg-config
      gnumake
      cargo-binstall
      nodejs
      bun
      # Not for my own use: other people's repositories call python3 in scripts and build steps
      python3
      # Google Drive mount (see rclone-cloud below). Create the remote with `rclone config`
      rclone
    ])
    # Rust comes from nixpkgs rather than rustup: Claude's sandbox cannot write ~/.rustup, so every toolchain install
    # or update through rustup needed a manual step. Taken from unstable to track the latest stable compiler, and all
    # from the same set so the versions match. rust-toolchain.toml is ignored; a project that needs another version gets a devShell
    ++ (with pkgs-unstable; [
      rustc
      cargo
      clippy
      rustfmt
      rust-analyzer
    ])
    ++ [
      pkgs-unstable.zed-editor
      # zed-editor from nixpkgs installs as zeditor, so make it launchable as zed too
      (pkgs.writeShellScriptBin "zed" ''exec ${pkgs-unstable.zed-editor}/bin/zeditor "$@"'')
    ];

  programs.git = {
    enable = true;
    settings = {
      inherit user;
      init.defaultBranch = "main";
      core.editor = "vim";
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
    };
  };

  programs.jujutsu = {
    enable = true;
    settings = {
      inherit user;
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

  # Mount the Google Drive remote "cloud" at ~/cloud. The remote and its OAuth token live in
  # ~/.config/rclone/rclone.conf, written by `rclone config`, so they stay out of the store; until it exists the unit is skipped.
  # The full VFS cache keeps opened files locally and uploads changes in the background, and --poll-interval picks up remote changes.
  # It is in default.target, and linger (hosts/desktop) starts the user manager at boot, so it mounts before login.
  # The mount waits until systemd-timesyncd has synchronized the clock. At boot rtc_cmos reads the RTC, kept in local time, as UTC and sets the clock 9 hours ahead until NTP corrects it; an OAuth token refreshed in that window is saved with
  # an expiry 9 hours late, so rclone keeps sending the expired token and gets 401 until that time. Waiting for the sync also
  # covers the network, which the user manager cannot wait for because it has no network-online.target.
  systemd.user.services.rclone-cloud =
    let
      mountpoint = "%h/cloud";
      waitForTimeSync = pkgs.writeShellScript "wait-for-time-sync" ''
        until [ -e /run/systemd/timesync/synchronized ]; do ${pkgs.coreutils}/bin/sleep 1; done
      '';
    in
    {
      Unit = {
        Description = "Google Drive mounted at ~/cloud";
        ConditionPathExists = "%h/.config/rclone/rclone.conf";
      };
      Service = {
        Type = "notify";
        ExecStartPre = [
          "${waitForTimeSync}"
          "${pkgs.coreutils}/bin/mkdir -p ${mountpoint}"
        ];
        # Offline at boot, the wait times out and Restart tries again
        TimeoutStartSec = "5min";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.rclone}/bin/rclone mount cloud: ${mountpoint}"
          "--vfs-cache-mode full --vfs-cache-max-age 720h --vfs-cache-max-size 20G"
          "--dir-cache-time 1h --poll-interval 1m"
        ];
        ExecStop = "/run/wrappers/bin/fusermount3 -u ${mountpoint}";
        # rclone calls fusermount3, which needs the setuid wrapper
        Environment = "PATH=/run/wrappers/bin";
        Restart = "on-failure";
        RestartSec = 15;
      };
      Install.WantedBy = [ "default.target" ];
    };
}
