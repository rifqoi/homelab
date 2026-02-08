{
  pkgs,
  lib,
  config,
  ...
}: let
  nginxDefaultConfigs = ''
      proxy_set_header Host $host;
    client_max_body_size 0;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
  '';
in {
  imports = [./common.nix];

  users.users.nginx.extraGroups = ["acme"];

  networking.firewall.allowedTCPPorts = [80 443];

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
