{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./common.nix
  ];

  # Override/extend common configuration
  networking.firewall.allowedTCPPorts = [22 3909 3900 3902 3901 3903];

  # Garage-specific SOPS secrets
  sops.secrets = {
    garage_admin_token = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "root";
      mode = "0400";
    };

    garage_metrics_token = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "root";
      mode = "0400";
    };

    garage_rpc_secret = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "root";
      mode = "0400";
    };
  };

  services.garage = {
    enable = true;
    package = pkgs.garage_2;
    logLevel = "debug";

    settings = {
      replication_factor = 1;
      data_dir = "/var/lib/garage/data";
      metadata_dir = "/var/lib/garage/metadata";

      allow_world_readable_secrets = true;
      consistency_mode = "consistent";
      db_engine = "sqlite";
      rpc_bind_addr = "[::]:3901";
      rpc_public_addr = "192.168.31.10:3901";
      rpc_secret_file = "/run/credentials/garage.service/garage_rpc_secret";

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
        api_bind_addr = "0.0.0.0:3903";
        metrics_token_file = "/run/credentials/garage.service/garage_metrics_token";
        metrics_require_token = true;
        admin_token_file = "/run/credentials/garage.service/garage_admin_token";
      };
    };
  };

  # Garage-specific packages
  environment.systemPackages = [pkgs.garage-webui];
  users.users.root.password = "changeme";

  systemd.services.garage.serviceConfig.LoadCredential = [
    "garage_rpc_secret:${config.sops.secrets.garage_rpc_secret.path}"
    "garage_metrics_token:${config.sops.secrets.garage_metrics_token.path}"
    "garage_admin_token:${config.sops.secrets.garage_admin_token.path}"
  ];

  systemd.services.garage-ui = {
    description = "Garage Web UI Service";
    after = ["network.target" "garage.service"];
    wants = ["garage.service"];
    serviceConfig = {
      ExecStart = let
        startScript = pkgs.writeShellScript "garage-ui-start" ''
          set -euo pipefail

          # Read admin token from credentials and export it
          if [ -f "$CREDENTIALS_DIRECTORY/garage_admin_token" ]; then
            export API_ADMIN_KEY=$(cat "$CREDENTIALS_DIRECTORY/garage_admin_token")
          else
            echo "ERROR: garage_admin_token credential not found in $CREDENTIALS_DIRECTORY" >&2
            exit 1
          fi

          # Start garage-webui
          exec ${pkgs.garage-webui}/bin/garage-webui
        '';
      in "${startScript}";

      Environment = ["PORT=3909" "CONFIG_PATH=/etc/garage.toml" "API_BASE_URL=http://127.0.0.1:3903"];
      LoadCredential = [
        "garage_rpc_secret:${config.sops.secrets.garage_rpc_secret.path}"
        "garage_metrics_token:${config.sops.secrets.garage_metrics_token.path}"
        "garage_admin_token:${config.sops.secrets.garage_admin_token.path}"
      ];

      Restart = "on-failure";
    };
    wantedBy = ["multi-user.target"];
  };
}
