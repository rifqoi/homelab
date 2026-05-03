{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./common.nix
  ];

  # Override/extend common configuration
  networking.firewall.allowedTCPPorts = [22 53 4000]; # DNS and metrics
  networking.firewall.allowedUDPPorts = [53]; # DNS

  services.blocky = {
    enable = true;
    settings = {
      # Port configuration
      ports = {
        dns = 53;
        http = 4000; # Metrics/API port
      };

      # Upstream DNS servers
      upstreams = {
        groups = {
          default = [
            "1.1.1.1" # Cloudflare DNS over HTTPS
            "8.8.8.8" # Google DNS over HTTPS
          ];
        };
      };

      # Custom DNS mappings
      customDNS = {
        customTTL = "1h";
        mapping = {
          "router.home.local" = "192.168.11.1";
          "garage.home.local" = "192.168.31.10";
          "blocky.home.local" = "192.168.31.11";
          "grafana.home.local" = "192.168.31.12";
          "rifqoi.com" = "192.168.31.30";
          "omni.rifqoi.com" = "192.168.31.20";
          "immich.rifqoi.com" = "192.168.31.130";
          "headlamp.rifqoi.com" = "192.168.31.131";
          # "pocket.rifqoi.com" = "192.168.31.30";
          # "grafana.rifqoi.com" = "192.168.31.30";
          # "garage.rifqoi.com" = "192.168.31.30";
          "authelia.home.local" = "192.168.31.13";
          "nongkee.home.local" = "100.71.151.87";
        };
      };

      # Conditional forwarding for home.local domain
      conditional = {
        mapping = {
          "home.local" = "192.168.31.11"; # Self-reference for home.lab queries
        };
      };

      # Blocking configuration (optional - you can customize this)
      blocking = {
        blackLists = {
          ads = [
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
          ];
        };
        clientGroupsBlock = {
          default = ["ads"];
        };
      };

      # Caching
      caching = {
        minTime = "5m";
        maxTime = "30m";
        prefetching = true;
      };

      # Prometheus metrics
      prometheus = {
        enable = true;
        path = "/metrics";
      };

      # Query logging (optional)
      queryLog = {
        type = "console";
      };
    };
  };

  # Additional packages
  environment.systemPackages = with pkgs; [
    dig
    dnsutils
  ];
}
