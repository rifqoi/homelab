{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./common.nix
  ];

  # Override/extend common configuration
  networking.firewall.allowedTCPPorts = [22 3900 3902 3901 3903];

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
        root_domain = ".s3.garage.rifqoi.com";
      };
      s3_web = {
        bind_addr = "[::]:3902";
        add_host_to_metrics = true;
        root_domain = ".web.garage.rifqoi.com";
      };
      admin = {
        api_bind_addr = "0.0.0.0:3903";
        metrics_token_file = "/run/credentials/garage.service/garage_metrics_token";
        metrics_require_token = true;
        admin_token_file = "/run/credentials/garage.service/garage_admin_token";
      };
    };
  };

  systemd.services.garage.serviceConfig.LoadCredential = [
    "garage_rpc_secret:${config.sops.secrets.garage_rpc_secret.path}"
    "garage_metrics_token:${config.sops.secrets.garage_metrics_token.path}"
    "garage_admin_token:${config.sops.secrets.garage_admin_token.path}"
  ];
}
