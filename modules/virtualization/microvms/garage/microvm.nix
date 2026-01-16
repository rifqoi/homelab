{
  lib,
  config,
  pkgs,
  ...
}: let
  vmName = "garage";
in {
  imports = [
    ../microvm.nix
    ../../storage
    ../../../common/users.nix
    ../../../monitoring/node-exporter.nix
  ];

  config = {
    networking.hostName = "${vmName}";

    # Enable node exporter for monitoring
    features.monitoring.nodeExporter = {
      enable = true;
      port = 9100;
      listenAddress = "0.0.0.0";
    };

    # Open firewall for node exporter

    microvm = {
      vcpu = 2;
      hotplugMem = 2048;

      shares = [
        {
          source = "/var/lib/private/garage";
          mountPoint = "/storage/garage";
          tag = "garage";
          proto = "virtiofs";
          socket = "/var/lib/microvms/${vmName}/garage.socket";
        }
      ];
    };

    # Enable Garage storage service
    features.storage.garage = {
      enable = true;
      package = pkgs.garage_2;
      logLevel = "info";

      ui.enable = true;
      ui.port = 3909;

      data_dir = "/storage/garage/data";
      metadata_dir = "/storage/garage/metadata";

      settings = {
        replication_mode = "none";

        rpc_bind_addr = "[::]:3901";
        rpc_public_addr = "127.0.0.1:3901";
        rpc_secret_file = config.sops.secrets.garage_rpc_secret.path;

        s3_api = {
          s3_region = "garage";
          api_bind_addr = "[::]:3900";
          root_domain = ".s3.garage.localhost";
        };

        s3_web = {
          bind_addr = "[::]:3902";
          root_domain = ".web.garage.localhost";
        };

        k2v_api = {
          api_bind_addr = "[::]:3904";
        };

        admin = {
          api_bind_addr = "127.0.0.1:3903";
          metrics_token_file = config.sops.secrets.garage_metrics_token.path;
          admin_token_file = config.sops.secrets.garage_admin_token.path;
        };
      };
    };

    # SOPS secrets configuration
    # Secrets are shared from host via VirtioFS at /run/secrets
    sops = {
      defaultSopsFile = ../../../../secrets/secrets.yaml;
      secrets = {
        garage_admin_token = {
          owner = "root";
          mode = "0400";
        };
        garage_metrics_token = {
          owner = "root";
          mode = "0400";
        };
        garage_rpc_secret = {
          owner = "root";
          mode = "0400";
        };
      };
    };

    # Networking configuration
    networking = {
      firewall = {
        enable = true;
        allowedTCPPorts = [
          3900 # S3 API
          3902 # S3 Web
          3903 # Admin API
          3904 # K2V API
          3909 # Web UI
          9100 # Node Exporter
        ];
        allowedUDPPorts = [
          3901 # RPC
        ];
      };
    };

    # Persistent directories
    environment.persistence."/persist" = {
      directories = [
        "/var/lib/nixos"
      ];
    };

    # System packages
    environment.systemPackages = with pkgs; [
      garage_2
    ];
  };
}
