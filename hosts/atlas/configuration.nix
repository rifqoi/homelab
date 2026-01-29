{
  config,
  lib,
  pkgs,
  modulesPath,
  sops-nix,
  ...
}: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules

    # Common configuration
    ../../modules/common

    # NixOs container configuration
    ../../modules/container
  ];

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
  };

  sops.secrets.garage_admin_token = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "root";
    mode = "0400";
  };

  sops.secrets.garage_metrics_token = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "prometheus";
    group = "prometheus";
    mode = "0400";
  };

  sops.secrets.garage_rpc_secret = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "root";
    mode = "0400";
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    timeoutStyle = "menu";
    gfxmodeEfi = "1024x768";
    gfxpayloadEfi = "keep";

    extraConfig = ''
      terminal_input console
      terminal_output console
    '';

    zfsSupport = true;
  };
  boot.loader.timeout = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.supportedFilesystems = ["zfs"];
  boot.initrd.supportedFilesystems = ["zfs"];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      vpl-gpu-rt
    ];
  };

  fileSystems."/" = {
    device = "rpool/root/ROOT/nixos";
    fsType = "zfs";
  };

  fileSystems."/nix" = {
    device = "rpool/nix";
    fsType = "zfs";
  };

  fileSystems."/home" = {
    device = "rpool/home";
    fsType = "zfs";
  };

  fileSystems."/var" = {
    device = "rpool/var";
    fsType = "zfs";
  };

  fileSystems."/var/lib/vms" = {
    device = "rpool/vm";
    fsType = "zfs";
  };

  fileSystems."/var/lib/postgresql" = {
    device = "rpool/postgresql";
    fsType = "zfs";
  };

  #  Bind this dataset to /var/lib/private/garage via a systemd mount unit.
  #  Because garage use DynamicUser=true and StateDirectory=garage
  #  the actual persistent data is stored in a private, highly
  #  restricted directory within /var/lib/private/
  fileSystems."/var/lib/private/garage" = {
    device = "rpool/garage";
    fsType = "zfs";
  };

  services.zfs = {
    autoScrub.enable = true;
    autoScrub.interval = "monthly";
    autoSnapshot.enable = true;
  };

  networking.hostName = "atlas";
  networking.hostId = "6b53000e";

  networking = {
    useDHCP = false;
    nameservers = ["192.168.31.11" "1.1.1.1" "8.8.8.8"];

    firewall = {
      enable = true;
      # trustedInterfaces = ["br31"]; # Trust the bridge
      checkReversePath = false; # Set to disabled for containers to work. Because packet comes from different interface in container.
    };

    vlans = {
      vlan30 = {
        id = 30;
        interface = "eno2";
      };
      vlan31 = {
        id = 31;
        interface = "eno2";
      };
    };

    # Add default gateway
    defaultGateway = {
      address = "192.168.30.1";
      interface = "br30";
    };

    bridges = {
      br30 = {interfaces = ["vlan30"];};
      br31 = {interfaces = ["vlan31"];};
    };

    interfaces.br30.useDHCP = false; # Only assigned to host
    interfaces.br30.ipv4.addresses = [
      {
        address = "192.168.30.101";
        prefixLength = 24;
      }
    ];
    interfaces.br31.useDHCP = false;
  };

  features = {
    monitoring = {
      prometheus = {
        enable = true;
        nodeExporterTargets = with config.features; [
          "${monitoring.nodeExporter.listenAddress}:${builtins.toString monitoring.nodeExporter.port}"
          "${monitoring.pingExporter.listenAddress}:${builtins.toString monitoring.pingExporter.port}"
          "nongkee.home.local:9100"
          "router.home.local:9000"
        ];
        scrapeConfigs = [
          {
            job_name = "garage";
            static_configs = [
              {
                targets = ["garage.home.local:3903"];
              }
            ];
            authorization = {
              type = "Bearer";
              credentials_file = config.sops.secrets.garage_metrics_token.path;
            };
          }
        ];
      };
      grafana = {
        enable = true;
      };

      pingExporter = {
        enable = true;
        settings = {
          targets = [
            "8.8.8.8"
            "1.1.1.1"
            "id.cloudflare.com"
            {
              "google.com" = {
                asn = 15169;
              };
            }
          ];
        };
      };
    };

    virtualization.incus = {
      enable = true;
      enableUI = true;
      preseed = {
        config = {
          "core.https_address" = ":8999";
        };
        networks = [
          {
            name = "incusbr0";
            type = "bridge";
            description = "NAT bridge";
            config = {
              "ipv4.address" = "auto";
              "ipv4.nat" = "true";
              # "ipv6.address" = "auto";
              # "ipv6.nat" = "true";
            };
          }
        ];
        profiles = [
          {
            name = "default";
            description = "Default Incus Profile";
            devices = {
              eth0 = {
                name = "eth0";
                network = "incusbr0";
                type = "nic";
              };
              root = {
                path = "/";
                pool = "default";
                type = "disk";
              };
            };
          }
        ];
        storage_pools = [
          {
            name = "default";
            driver = "zfs";
            config = {
              source = "rpool/vm";
            };
          }
        ];
      };
      networking = {
        allowedTCPPorts = [53 67];
        allowedUDPPorts = [53 67];
      };
    };
  };

  programs = {
    zsh = {
      enable = true;
      ohMyZsh = {
        enable = true;
        theme = "agnoster";
      };
    };

    starship = {
      enable = true;
    };
  };

  # microvm.vms = {
  #   my-microvm = {
  #     # The package set to use for the microvm. This also determines the microvm's architecture.
  #     # Defaults to the host system's package set if not given.
  #     inherit pkgs;
  #
  #     # (Optional) A set of special arguments to be passed to the MicroVM's NixOS modules.
  #     #specialArgs = {};
  #
  #     # The configuration for the MicroVM.
  #     # Multiple definitions will be merged as expected.
  #     config = {
  #       # It is highly recommended to share the host's nix-store
  #       # with the VMs to prevent building huge images.
  #       microvm.shares = [
  #         {
  #           source = "/nix/store";
  #           mountPoint = "/nix/.ro-store";
  #           tag = "ro-store";
  #           proto = "virtiofs";
  #         }
  #       ];
  #
  #       # Any other configuration for your MicroVM
  #       # [...]
  #     };
  #   };
  # };
}
