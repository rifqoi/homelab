{...}: {
  imports = [
    ./common.nix
    ../monitoring/grafana.nix
  ];

  # Override/extend common configuration
  networking.defaultGateway = "192.168.31.1";

  features.monitoring.grafana = {
    enable = true;
    prometheusUrl = "http://192.168.30.101:9090";
    domain = "grafana.rifqoi.com";
    rootUrl = "https://grafana.rifqoi.com";
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
        sha256 = "0fvakggsnj2rwylqlg9s6bsdfxwaacmbj7i6rg3arn9hyc4ldjdy";
      }
    ];
  };
}
