# Shells and the terminal: bash, Nushell, starship, zoxide and WezTerm
{
  pkgs,
  pkgs-unstable,
  dot,
  liveDot,
  ...
}:
let
  nushellDir = "${dot}/nushell";
in
{
  home.packages = [
    pkgs-unstable.wezterm
    # starship's custom.jj
    pkgs.jj-starship
  ];

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

  # Link each file rather than the directory: ~/.config/wezterm is already a real directory from earlier generations
  xdg.configFile."wezterm/wezterm.lua".source = liveDot "wezterm/wezterm.lua";
  xdg.configFile."wezterm/wezterm_common.lua".source = liveDot "wezterm/wezterm_common.lua";
  xdg.configFile."wezterm/keybinds.lua".source = liveDot "wezterm/keybinds.lua";
  xdg.configFile."wezterm/keybinds_common.lua".source = liveDot "wezterm/keybinds_common.lua";
}
