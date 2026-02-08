{
  pkgs,
  lib,
  config,
  ...
}: let
  mkCert = domains:
    lib.attrsets.genAttrs domains (domain: {
      email = "rifqoi@rifqoi.com";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      credentialsFile = config.sops.secrets.cloudflare.path;
      webroot = null;
    });
  certs = [
    "home.rifqoi.com"
    "garage.rifqoi.com"
    "garage-s3"
    "grafana.rifqoi.com"
    "pocket.rifqoi.com"
    "omni.rifqoi.com"
  ];
  nginxDefaultConfigs = ''
      proxy_set_header Host $host;
    client_max_body_size 0;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
  '';
in {
  imports = [./common.nix];

  sops.secrets.cloudflare = {
    sopsFile = ../../secrets/cloudflare.env;
    key = "";
    format = "dotenv";
  };

  users.users.nginx.extraGroups = ["acme"];

  networking.firewall.allowedTCPPorts = [80 443];
  security.acme = {
    acceptTerms = true;
    certs = mkCert certs;
    # certs = {
    #   "home.rifqoi.com" = {
    #     email = "rifqoi@rifqoi.com";
    #     dnsProvider = "cloudflare";
    #     dnsResolver = "1.1.1.1:53";
    #     credentialsFile = config.sops.secrets.cloudflare.path;
    #     webroot = null;
    #   };
    #   "garage.rifqoi.com" = {
    #     email = "rifqoi@rifqoi.com";
    #     dnsProvider = "cloudflare";
    #     dnsResolver = "1.1.1.1:53";
    #     credentialsFile = config.sops.secrets.cloudflare.path;
    #     webroot = null;
    #   };
    #   "garage-s3" = {
    #     email = "rifqoi@rifqoi.com";
    #     dnsProvider = "cloudflare";
    #     dnsResolver = "1.1.1.1:53";
    #     domain = "*.s3.garage.rifqoi.com";
    #     credentialsFile = config.sops.secrets.cloudflare.path;
    #
    #     extraDomainNames = ["s3.garage.rifqoi.com"];
    #     webroot = null;
    #   };
    #   "grafana.rifqoi.com" = {
    #     email = "rifqoi@rifqoi.com";
    #     dnsProvider = "cloudflare";
    #     dnsResolver = "1.1.1.1:53";
    #     credentialsFile = config.sops.secrets.cloudflare.path;
    #     webroot = null;
    #   };
    #   "pocket.rifqoi.com" = {
    #     email = "rifqoi@rifqoi.com";
    #     dnsProvider = "cloudflare";
    #     dnsResolver = "1.1.1.1:53";
    #     credentialsFile = config.sops.secrets.cloudflare.path;
    #     webroot = null;
    #   };
    #   "omni.rifqoi.com" = {
    #     email = "rifqoi@rifqoi.com";
    #     dnsProvider = "cloudflare";
    #     dnsResolver = "1.1.1.1:53";
    #     credentialsFile = config.sops.secrets.cloudflare.path;
    #     webroot = null;
    #   };
    # };
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
          extraConfig = nginxDefaultConfigs;
        };
      };
    };
    "s3.garage.rifqoi.com" = {
      forceSSL = true;

      useACMEHost = "garage-s3";
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.10:3900";
          extraConfig = nginxDefaultConfigs;
        };
      };
    };
    "*.s3.garage.rifqoi.com" = {
      forceSSL = true;
      useACMEHost = "garage-s3";
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.10:3900";
          extraConfig = nginxDefaultConfigs;
        };
      };
    };
    "grafana.rifqoi.com" = {
      forceSSL = true;
      enableACME = true;
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.12:3000";
          extraConfig = nginxDefaultConfigs;
        };
      };
    };
    "pocket.rifqoi.com" = {
      forceSSL = true;
      enableACME = true;
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.13:1411";
          extraConfig = nginxDefaultConfigs;
        };
      };
    };
    "omni.rifqoi.com" = {
      forceSSL = true;
      enableACME = true;
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.20:80";
          extraConfig = nginxDefaultConfigs;
        };
      };
    };
  };
}
