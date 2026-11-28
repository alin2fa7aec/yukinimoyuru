# The dotfiles are used in two ways:
# - dotFile (from flake.nix): the copy pinned by flake.lock, for files nix reads or transforms (readFile, generated colors, service arguments)
# - liveDot: a link straight into the checkout, for files placed as they are. Edits take effect without a rebuild
# liveDot is passed to every module as an argument
{ config, lib, ... }:
{
  options.yuki.dotfiles.checkout = lib.mkOption {
    type = lib.types.str;
    example = "/home/user/src/dotfiles";
    description = "Absolute path of the dotfiles checkout that liveDot links into.";
  };

  config._module.args.liveDot =
    path: config.lib.file.mkOutOfStoreSymlink "${config.yuki.dotfiles.checkout}/${path}";
}
