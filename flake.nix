{
  description = "Koski NixOS sandbox VM image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, unstable, nixos-generators }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      seedModules = [
        ./modules/base.nix
        ./modules/share.nix
        ./modules/user.nix
        ./modules/firstboot.nix
        ./modules/vm.nix
        ./modules/git.nix
        ./modules/fish.nix
      ];

      # Added only on the user's first nixos-rebuild — kept out of the seed
      # qcow2 for two reasons: (1) idea.nix and claude.nix carry binaries
      # whose licenses don't allow redistribution through the public seed,
      # and (2) the GUI stack and dev-tools.nix are heavy and the seed
      # itself doesn't need them, so excluding them keeps the published
      # qcow2 small. The user's own machine fetches everything from the
      # nixpkgs binary cache on first boot.
      postSeedModules = [
        ./modules/desktop.nix
        ./modules/spice.nix
        ./modules/claude.nix
        ./modules/idea.nix
        ./modules/dev-tools.nix
      ];

      mkSpecialArgs = system: {
        flakeSelf = self;
        unstablePkgs = import unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          image = nixos-generators.nixosGenerate {
            inherit system;
            specialArgs = mkSpecialArgs system;
            format = "qcow-efi";
            modules = seedModules;
          };
        in {
          inherit image;
          compressedImage = pkgs.runCommand "nixos-compressed.qcow2"
            { nativeBuildInputs = [ pkgs.qemu-utils ]; }
            ''qemu-img convert -c -O qcow2 ${image}/nixos.qcow2 $out'';
        });

      nixosConfigurations = nixpkgs.lib.genAttrs (map (s: "sandbox-${s}") systems)
        (name:
          let system = nixpkgs.lib.removePrefix "sandbox-" name; in
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = mkSpecialArgs system;
            modules = seedModules ++ postSeedModules;
          });
    };
}
