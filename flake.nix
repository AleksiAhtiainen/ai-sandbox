{
  description = "Koski NixOS sandbox VM image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      commonModules = [
        ./modules/base.nix
        ./modules/desktop.nix
        ./modules/spice.nix
        ./modules/share.nix
        ./modules/user.nix
        ./modules/firstboot.nix
        ./modules/vm.nix
      ];

      specialArgs = { flakeSelf = self; };
    in {
      packages = forAllSystems (system: {
        image = nixos-generators.nixosGenerate {
          inherit system specialArgs;
          format = "qcow-efi";
          modules = commonModules;
        };
      });

      nixosConfigurations = nixpkgs.lib.genAttrs (map (s: "sandbox-${s}") systems)
        (name:
          let system = nixpkgs.lib.removePrefix "sandbox-" name; in
          nixpkgs.lib.nixosSystem {
            inherit system specialArgs;
            modules = commonModules;
          });
    };
}
