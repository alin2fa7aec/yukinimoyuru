{
  description = "NixOS desktop configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # App config files live in their own repository; this flake only places them
    dotfiles = {
      url = "github:alin2fa7aec/dotfiles";
      flake = false;
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      # Path of a file in the copy of dotfiles pinned by flake.lock. A missing file stops evaluation,
      # so a renamed or removed file is caught before anything is built or started with a dangling path
      dotFile =
        rel:
        let
          path = "${inputs.dotfiles}/${rel}";
        in
        if builtins.pathExists path then path else throw "dotfiles has no ${rel}";
    in
    {
      # `nix fmt` formats every tracked .nix file with nixfmt.
      # hardware-configuration.nix is left as nixos-generate-config wrote it
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree.override {
        settings.global.excludes = [ "hosts/desktop/hardware-configuration.nix" ];
      };

      nixosConfigurations.yukiwari = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs pkgs-unstable dotFile; };
        modules = [
          ./hosts/desktop/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = { inherit inputs pkgs-unstable dotFile; };
            home-manager.users.alin = import ./home/alin.nix;
          }
        ];
      };
    };
}
