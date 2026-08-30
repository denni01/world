{
  description = "dennis' NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixpkgs only builds xremap with the `wlroots` feature, which cannot read
    # the focused window from post-wlroots Hyprland. This flake provides the
    # Hyprland-feature build plus a NixOS module that handles uinput permissions
    # and the user-service wiring.
    xremap = {
      url = "github:xremap/nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative partitioning for a fresh install. Deliberately not imported
    # into nixosConfigurations.proart — see hosts/proart/disko.nix.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    {
      nixosConfigurations.proart = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/proart
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-bak";
              extraSpecialArgs = { inherit inputs; };
              users.dennis = import ./home;
            };
          }
        ];
      };


      # Installer ISO. Carries no system closure — it clones main at install
      # time, so an old ISO still installs a current system.
      #   nix build .#installer
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [ ./hosts/installer ];
      };

      packages.x86_64-linux.installer =
        self.nixosConfigurations.installer.config.system.build.isoImage;

      # Consumed by `disko --mode destroy,format,mount --flake .#proart`. Kept out
      # of the NixOS config so switching this machine can never depend on it.
      diskoConfigurations.proart = import ./hosts/proart/disko.nix;
    };
}
