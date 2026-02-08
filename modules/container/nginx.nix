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

  users.users.nginx.extraGroups = ["acme"];

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
      "garage-s3" = {
        email = "rifqoi@rifqoi.com";
        dnsProvider = "cloudflare";
        dnsResolver = "1.1.1.1:53";
        domain = "*.s3.garage.rifqoi.com";
        credentialsFile = config.sops.secrets.cloudflare.path;

        extraDomainNames = ["s3.garage.rifqoi.com"];
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
    "s3.garage.rifqoi.com" = {
      forceSSL = true;

      useACMEHost = "garage-s3";
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.10:3900";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            client_max_body_size 0;
          '';
        };
      };
    };
    "*.s3.garage.rifqoi.com" = {
      forceSSL = true;
      useACMEHost = "garage-s3";
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.10:3900";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            client_max_body_size 0;
          '';
        };
      };
    };
    "grafana.rifqoi.com" = {
      forceSSL = true;
      enableACME = true;
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.12:3000";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
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
