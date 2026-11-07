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
      rustup
      gcc
      pkg-config
      gnumake
      cargo-binstall
      nodejs
      bun
      # Google Drive mount (see rclone-gdrive below). Create the remote with `rclone config`
      rclone
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

  # Mount the Google Drive remote "gdrive" at ~/!partage/gdrive. The remote and its OAuth token live in
  # ~/.config/rclone/rclone.conf, written by `rclone config`, so they stay out of the store; until it exists the unit is skipped.
  # The full VFS cache keeps opened files locally and uploads changes in the background, and --poll-interval picks up remote changes.
  # It is in default.target, and linger (hosts/desktop) starts the user manager at boot, so it mounts before login.
  # The user manager has no network-online.target, so a mount attempted before the network is up fails and is retried
  systemd.user.services.rclone-gdrive =
    let
      mountpoint = "%h/!partage/gdrive";
    in
    {
      Unit = {
        Description = "Google Drive mounted at ~/!partage/gdrive";
        ConditionPathExists = "%h/.config/rclone/rclone.conf";
      };
      Service = {
        Type = "notify";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${mountpoint}";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.rclone}/bin/rclone mount gdrive: ${mountpoint}"
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
