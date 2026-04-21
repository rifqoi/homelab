{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.features.monitoring.grafana;
  dashboardsPath = "grafana/dashboards";
  mergeDashboards = dashboards:
    lib.attrsets.mergeAttrsList (map (dashboard: let
        source =
          if dashboard ? url
          then
            assert dashboard.sha256 != null;
              pkgs.fetchurl {
                url = "${dashboard.url}";
                sha256 = "${dashboard.sha256}";
              }
          else if dashboard ? file
          then dashboard.file
          else throw "Dashboard must have either file or url.";
      in {
        "${dashboardsPath}/${dashboard.name}.json".source = source;
      })
      dashboards);
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.features.monitoring.grafana = {
    enable = lib.mkEnableOption "Grafana monitoring dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port for Grafana web interface";
    };

    prometheusUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:9090";
      description = "URL of Prometheus server";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "Domain name for Grafana";
    };

    dashboards = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = "List of dashboards to be added to Grafana";
    };

    rootUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Root URL for Grafana (overrides default if set)";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = lib.mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # GRAFANA SERVICE
    # --------------------------------------------------------------------------

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port = cfg.port;
          http_addr = "0.0.0.0";
          domain = cfg.domain;
          root_url = cfg.rootUrl;
          enforce_domain = true;
        };

        security = {
          admin_user = "admin";
          admin_password = "admin";
          secret_key = "SW2YcwTIb9zpOOhoPsMm";
        };

        auth = {
          oauth_allow_insecure_email_lookup = true;
        };

        "auth.anonymous" = {
          enabled = true;
          org_role = "Viewer";
        };
      };

      provision = {
        enable = true;

        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = cfg.prometheusUrl;
            isDefault = true;
          }
        ];

        dashboards.settings.providers = [
          {
            name = "default";
            options.path = "/etc/grafana/dashboards";
          }
        ];
      };
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [cfg.port];

    # --------------------------------------------------------------------------
    # DASHBOARD SETUP
    # --------------------------------------------------------------------------

    environment.etc = mergeDashboards cfg.dashboards;
    # Fetch the popular Node Exporter Full dashboard
    # environment.etc."grafana/dashboards/node-exporter.json".source = pkgs.fetchurl {
    #   url = "https://raw.githubusercontent.com/rfmoz/grafana-dashboards/master/prometheus/node-exporter-full.json";
    #   sha256 = "sha256-lOpPVIW4Rih8/5zWnjC3K0kKgK5Jc1vQgCgj4CVkYP4=";
    # };
  };
}
