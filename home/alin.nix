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
      fuzzel waybar mako xwayland-satellite
    ])
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
