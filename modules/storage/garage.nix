{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.features.storage.garage;
in {
  options.features.storage.garage = {
    enable = lib.mkEnableOption "Garage storage for media files";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.garage_2;
      description = "Package for Garage service";
    };

    data_dir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/garage/data";
      description = "Directory for storing Garage media files";
    };

    metadata_dir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/garage/metadata";
      description = "Directory for storing Garage metadata files";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Additional Garage configuration settings";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum ["debug" "info" "warn" "error"];
      default = "info";
      description = "Logging level for Garage service";
    };
  };

  config = lib.mkIf cfg.enable {
    services.garage = {
      enable = true;
      package = cfg.package;
      logLevel = cfg.logLevel;
      settings = lib.recursiveUpdate cfg.settings {
        data_dir = cfg.data_dir;
        metadata_dir = cfg.metadata_dir;

        allow_world_readable_secrets = lib.mkIf ((cfg.settings ? rpc_secret_file)
          || (cfg.settings.admin ? metrics_token_file)
          || (cfg.settings.admin ? admin_token_file))
        true;

        rpc_secret_file =
          lib.mkIf (cfg.settings ? rpc_secret_file)
          "/run/credentials/garage.service/garage_rpc_secret";

        admin.metrics_token_file =
          lib.mkIf (cfg.settings.admin ? metrics_token_file)
          "/run/credentials/garage.service/garage_metrics_token";

        admin.admin_token_file =
          lib.mkIf (cfg.settings.admin ? admin_token_file)
          "/run/credentials/garage.service/garage_admin_token";
      };
    };
    # Workaround to load secrets into the Garage service
    # Using LoadCredential to mount secrets from SOPS
    systemd.services.garage.serviceConfig.LoadCredential =
      (lib.optional (cfg.settings ? rpc_secret_file)
        "garage_rpc_secret:${cfg.settings.rpc_secret_file}")
      ++ (lib.optional (cfg.settings.admin ? metrics_token_file)
        "garage_metrics_token:${cfg.settings.admin.metrics_token_file}")
      ++ (lib.optional (cfg.settings.admin ? admin_token_file)
        "garage_admin_token:${cfg.settings.admin.admin_token_file}");

  };
}
