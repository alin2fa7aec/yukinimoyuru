# Claude Code: the package and the files placed in ~/.claude
{
  lib,
  pkgs,
  pkgs-unstable,
  dotFile,
  liveDot,
  ...
}:
{
  home.packages = [
    pkgs-unstable.claude-code
    # Claude Code's clangd-lsp plugin
    pkgs.clang-tools
  ];

  # managed-settings.json is placed in /etc/claude-code on the system side (hosts/desktop/configuration.nix)
  # The writing-style skill comes from claude.ai (its source is in dotfiles); only its lint is deployed here.
  # The lint runs from the PostToolUse hook, so unlike other placed files it stays pinned in the store
  # and changes only on a rebuild
  home.file.".claude/writing-lint.nu".source = dotFile "claude/writing-lint.nu";
  home.file.".claude/CLAUDE.md".source = liveDot "claude/CLAUDE.md";
  home.file.".claude/skills/commit-message".source = liveDot "claude/skills/commit-message";
  home.file.".claude/keybindings.json".source = liveDot "claude/keybindings.json";
  home.file.".claude/statusline.sh".source = liveDot "claude/statusline.sh";

  # Claude Code itself rewrites settings.json (/model, /config, etc.),
  # so instead of a link to the store, put a writable copy only when it is missing
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "$HOME/.claude/settings.json" ]; then
      run mkdir -p "$HOME/.claude"
      run install -m 644 ${dotFile "claude/settings.json"} "$HOME/.claude/settings.json"
    fi
  '';
}
