{
  description = "Rifqoi's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    disko,
    sops-nix,
    ...
  }: let
    lib = nixpkgs.lib;
    allSystems = [
      "x86_64-linux" # 64-bit Intel/AMD Linux
      "aarch64-linux" # 64-bit ARM Linux
      "x86_64-darwin" # 64-bit Intel macOS
      "aarch64-darwin" # 64-bit ARM macOS
    ];

    # Helper to provide system-specific attributes
    forAllSystems = f: nixpkgs.lib.genAttrs allSystems f;
  in {
    formatter = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in
      pkgs.alejandra);

    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.nixd
          pkgs.alejandra
        ];
      };
    });

    apps = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
      buildApps =
        lib.mapAttrs' (hostName: _: {
          name = "build-${hostName}";
          value = {
            type = "app";
            program = toString (pkgs.writeShellScript "build-${hostName}" ''
              exec nix run nixpkgs#nixos-rebuild -- switch \
                --flake .#${hostName} \
                --target-host rifqoi@${hostName} \
                --build-host rifqoi@${hostName} \
                --use-remote-sudo
            '');
          };
        })
        self.nixosConfigurations;
    in
      buildApps
      // {
        # Add custom apps here
        # example = {
        #   type = "app";
        #   program = toString (pkgs.writeShellScript "example" ''
        #     echo "Hello from custom app"
        #   '');
        # };
      });

    nixosConfigurations = {
      vm = lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          disko.nixosModules.disko
          ./hosts/vm/disko.nix
          ./hosts/vm/configuration.nix
        ];
      };

      atlas = lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/atlas/configuration.nix
          ./hosts/atlas/disko.nix
        ];
      };
    };
  };
}
