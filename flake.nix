{
  description = "Rifqoi's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";

    talos-pilot.url = "github:Handfish/talos-pilot";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    dewclaw.url = "github:MakiseKurisu/dewclaw";
    dewclaw.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    disko,
    sops-nix,
    deploy-rs,
    microvm,
    talos-pilot,
    dewclaw,
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

    packages = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      openwrt = pkgs.callPackage dewclaw {
        configuration = ./hosts/openwrt/configuration.nix;
      };

      fix-iscsi-target = pkgs.writeShellScriptBin "fix-iscsi-target" ''
        exec bash "./k8s/clusters/production/infrastructure/democratic-csi/fix-iscsi-target.sh" "$@"
      '';
      find-orphaned-pvcs = pkgs.writeShellScriptBin "find-orphaned-pvcs" ''
        exec bash "./k8s/clusters/production/infrastructure/democratic-csi/find-orphaned-pvcs.sh" "$@"
      '';
      restore-orphaned-pvcs = pkgs.writeShellScriptBin "restore-orphaned-pvcs" ''
        exec bash "./k8s/clusters/production/infrastructure/democratic-csi/restore-orphaned-pvcs.sh" "$@"
      '';
    });

    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [talos-pilot.overlays.default];
        config.allowUnfree = true;
      };
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.nixd
          pkgs.alejandra
          pkgs.deploy-rs
          pkgs.omnictl
          pkgs.qemu-utils
          pkgs.talosctl
          pkgs.talos-pilot
          pkgs.kubectl
          pkgs.cilium-cli
          pkgs.hubble
          pkgs.helmfile
          pkgs.kubernetes-helm
          pkgs.fluxcd
          pkgs.sops
          pkgs.age
          pkgs.flux9s
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
              ${pkgs.deploy-rs}/bin/deploy .#${hostName} --debug-logs
                    # exec nix run nixpkgs#nixos-rebuild -- switch \
                    #   --flake .#${hostName} \
                    #   --target-host rifqoi@${hostName} \
                    #   --build-host rifqoi@${hostName} \
                    #   --sudo
            '');
          };
        })
        self.nixosConfigurations;
    in
      buildApps
      // {
        fix-iscsi-target = {
          type = "app";
          program = "${self.packages.${system}.fix-iscsi-target}/bin/fix-iscsi-target";
        };
        find-orphaned-pvcs = {
          type = "app";
          program = "${self.packages.${system}.find-orphaned-pvcs}/bin/find-orphaned-pvcs";
        };
        restore-orphaned-pvcs = {
          type = "app";
          program = "${self.packages.${system}.restore-orphaned-pvcs}/bin/restore-orphaned-pvcs";
        };
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
        specialArgs = {inherit sops-nix;};
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          # microvm.nixosModules.host
          ./hosts/atlas/configuration.nix
          ./hosts/atlas/disko.nix
        ];
      };
    };
    deploy = {
      # If the previous profile should be re-activated if activation fails.
      # This defaults to `true`
      autoRollback = true;

      # See the earlier section about Magic Rollback for more information.
      # This defaults to `true`
      magicRollback = true;

      remoteBuild = true;

      nodes = {
        atlas = {
          hostname = "atlas";
          sshUser = "rifqoi";
          user = "rifqoi";

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.atlas;
          };
        };
      };
    };
  };
}
