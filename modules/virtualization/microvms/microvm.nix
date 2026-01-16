{
  lib,
  inputs,
  config,
  pkgs,
  ...
}: let
  baseDir = "/var/lib/microvms/${hostName}";
  hostName = config.networking.hostName;
in {
  imports = [
    inputs.microvm.nixosModules.microvm
  ];

  config = {
    system.stateVersion = config.system.nixos.release;

    microvm = {
      hypervisor = lib.mkDefault "cloud-hypervisor";
      vcpu = lib.mkDefault 1;
      hotplugMem = lib.mkDefault 1536;

      shares = [
        {
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          tag = "store";
          proto = "virtiofs";
          socket = "${baseDir}/store.socket";
        }
        {
          source = "/run/secrets";
          mountPoint = "/run/secrets";
          tag = "secrets";
          proto = "virtiofs";
          readOnly = true;
          socket = "${baseDir}/secrets.socket";
        }
        {
          source = "/persist/microvm/${hostName}";
          mountPoint = "/persist";
          tag = "persist";
          proto = "virtiofs";
          socket = "${baseDir}/persist.socket";
        }
      ];

      writableStoreOverlay = "/nix/.rw-store";
      volumes = [
        {
          image = "nix-store-overlay.img";
          mountPoint = "/nix/.rw-store";
          size = 2048;
        }
      ];

      interfaces = [
        {
          type = "tap";
          id = "vm-${
            if builtins.stringLength hostName <= 8
            then hostName
            else builtins.substring (builtins.stringLength hostName - 8) 8 hostName
          }";
          mac = let
            hash = builtins.hashString "sha256" hostName;
            octets = lib.genList (i: builtins.substring (i * 2) 2 hash) 5;
          in "02:${lib.concatStringsSep ":" octets}";
        }
      ];
    };

    fileSystems = lib.genAttrs (map (share: share.mountPoint) config.microvm.shares) (_: {
      neededForBoot = true;
    });

    environment.persistence."/persist" = {
      directories = [
        "/var/lib/nixos"
      ];
    };

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    nixpkgs = {
      config = {
        allowUnfree = true;
        allowUnfreePredicate = _: true;
      };
    };

    systemd.network.enable = true;
    networking.useNetworkd = true;
    networking.useDHCP = true;
    networking.useHostResolvConf = lib.mkForce false;
    services.resolved.enable = true;

    microvm.host.enable = false;
  };
}
