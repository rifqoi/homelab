{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules

    # Common configuration
    ../../modules/common
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
    timeout = 5;
    timeoutStyle = "menu";

    zfsSupport = true;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  boot.supportedFilesystems = ["zfs"];
  boot.initrd.supportedFilesystems = ["zfs"];

  boot.kernelModules = [
    "nf_nat"
    "nf_nat_ipv4"
    "nf_nat_ipv6"
    "iptable_nat"
    "iptable_mangle"
    "xt_MASQUERADE"
  ];

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
    networkmanager = {
      enable = true;
      wifi.powersave = false;
    };
  };

  features = {
    monitoring = {
      prometheus = {
        enable = true;
        nodeExporterTargets = with config.features; [
          "${monitoring.nodeExporter.listenAddress}:${builtins.toString monitoring.nodeExporter.port}"
          "${monitoring.pingExporter.listenAddress}:${builtins.toString monitoring.pingExporter.port}"
          "100.71.151.87:9100"
          "192.168.11.1:9000"
        ];
        scrapeConfigs = [
          {
            job_name = "garage";
            static_configs = [
              {
                targets = [config.features.storage.garage.settings.admin.api_bind_addr];
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
        domain = "localhost";
        prometheusUrl = "http://localhost:9090";
        dashboards = [
          {
            name = "node-exporter";
            url = "https://raw.githubusercontent.com/rfmoz/grafana-dashboards/master/prometheus/node-exporter-full.json";
            sha256 = "sha256-lOpPVIW4Rih8/5zWnjC3K0kKgK5Jc1vQgCgj4CVkYP4=";
          }
          {
            name = "ping-exporter";
            url = "https://raw.githubusercontent.com/rifqoi/nixos-config/refs/heads/main/grafana/dashboards/ping-exporter.json";
            sha256 = "sha256-ZmzCak5jAaUA4jKjKcN4mC2SjBsHZXcQf4I7bhoetoY=";
          }
          {
            name = "garage-exporter";
            url = "https://raw.githubusercontent.com/rifqoi/nixos-config/refs/heads/main/grafana/dashboards/garage-exporter.json";
            sha256 = "sha256-k+lWwFHYwcpMhraDnZwmbMKDZHAGjfcBqJ32n9nXpDQ=";
          }
          {
            name = "openwrt-exporter";
            url = "https://raw.githubusercontent.com/rifqoi/nixos-config/refs/heads/main/grafana/dashboards/openwrt-dashboard.json";
            sha256 = "sha256-pXMvsz0nemZHzM1oPUe/ItVgu3TR7MStT3Y47burju4=";
          }
        ];
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

    storage = {
      garage = {
        enable = true;
        ui.enable = true;
        package = pkgs.garage_2;
        data_dir = "/var/lib/garage/data";
        metadata_dir = "/var/lib/garage/metadata";
        settings = {
          replication_factor = 1;
          consistency_mode = "consistent";
          db_engine = "sqlite";
          rpc_bind_addr = "[::]:3901";
          rpc_public_addr = "127.0.0.1:3901";
          rpc_secret_file = config.sops.secrets.garage_rpc_secret.path;
          s3_api = {
            api_bind_addr = "[::]:3900";
            s3_region = "garage";
            root_domain = ".s3.garage";
          };
          s3_web = {
            bind_addr = "[::]:3902";
            add_host_to_metrics = true;
            root_domain = ".web.garage";
          };
          admin = {
            api_bind_addr = "127.0.0.1:3903";
            metrics_token_file = config.sops.secrets.garage_metrics_token.path;
            metrics_require_token = true;
            admin_token_file = config.sops.secrets.garage_admin_token.path;
          };
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

  networking.networkmanager.insertNameservers = ["1.1.1.1" "8.8.8.8"];
  networking.vlans = {
    vlan30 = {
      id = 30;
      interface = "eno2";
    };
  };
  networking.interfaces.vlan30.useDHCP = true;

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
}
