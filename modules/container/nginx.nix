{
  pkgs,
  config,
  ...
}: {
  imports = [./common.nix];

  sops.secrets.cloudflare = {
    sopsFile = ../../secrets/cloudflare.env;
    key = "";
    format = "dotenv";
  };

  networking.firewall.allowedTCPPorts = [80 443];
  security.acme = {
    acceptTerms = true;
    certs = {
      "home.rifqoi.com" = {
        email = "rifqoi@rifqoi.com";
        dnsProvider = "cloudflare";
        dnsResolver = "1.1.1.1:53";
        credentialsFile = config.sops.secrets.cloudflare.path;
        webroot = null;
      };
      "garage.rifqoi.com" = {
        email = "rifqoi@rifqoi.com";
        dnsProvider = "cloudflare";
        dnsResolver = "1.1.1.1:53";
        credentialsFile = config.sops.secrets.cloudflare.path;
        webroot = null;
      };
      "grafana.rifqoi.com" = {
        email = "rifqoi@rifqoi.com";
        dnsProvider = "cloudflare";
        dnsResolver = "1.1.1.1:53";
        credentialsFile = config.sops.secrets.cloudflare.path;
        webroot = null;
      };
      "pocket.rifqoi.com" = {
        email = "rifqoi@rifqoi.com";
        dnsProvider = "cloudflare";
        dnsResolver = "1.1.1.1:53";
        credentialsFile = config.sops.secrets.cloudflare.path;
        webroot = null;
      };
    };
  };

  services.nginx.enable = true;
  services.nginx.virtualHosts = {
    "home.rifqoi.com" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        return = "301 https://rifqoi.com";
        # root = "/usr/share/nginx/html";
      };
    };
    "garage.rifqoi.com" = {
      forceSSL = true;
      enableACME = true;
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.10:3909";
        };
      };
    };
    "grafana.rifqoi.com" = {
      forceSSL = true;
      enableACME = true;
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.12:3000";
        };
      };
    };
    "pocket.rifqoi.com" = {
      forceSSL = true;
      enableACME = true;
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.13:1411";
        };
      };
    };
  };
}
