{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./common.nix
  ];

  # Override/extend common configuration
  networking.defaultGateway = "192.168.31.1";
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
            "https://one.one.one.one/dns-query" # Cloudflare DNS over HTTPS
            "https://dns.google/dns-query" # Google DNS over HTTPS
          ];
        };
      };

      # Custom DNS mappings
      customDNS = {
        customTTL = "1h";
        mapping = {
          "router.home.lab" = "192.168.30.1";
          "garage.home.lab" = "192.168.31.10";
          "grafana.home.lab" = "192.168.30.101";
          "blocky.home.lab" = "192.168.31.11";
        };
      };

      # Conditional forwarding for home.lab domain
      conditional = {
        mapping = {
          "home.lab" = "192.168.31.11"; # Self-reference for home.lab queries
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
