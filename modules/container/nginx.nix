{...}: let
  nginxDefaultConfigs = ''
      proxy_set_header Host $host;
    client_max_body_size 0;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
  '';
  registryProxyConfigs =
    nginxDefaultConfigs
    + ''
      proxy_request_buffering off;
    '';
in {
  imports = [./common.nix];

  users.mutableUsers = false;
  users.users.nginx = {
    isSystemUser = true;
    group = "nginx";
    extraGroups = ["acme"];
  };
  users.groups.acme = {
    gid = 988; # Match host acme group
  };

  networking.firewall.allowedTCPPorts = [80 443];

  services.nginx.enable = true;
  services.nginx.virtualHosts = {
    "_" = {
      default = true;
      locations."/" = {
        return = "444"; # drop the connection
      };
    };
    "home.rifqoi.com" = {
      forceSSL = true;
      sslCertificate = "/var/lib/acme/home.rifqoi.com/cert.pem";
      sslCertificateKey = "/var/lib/acme/home.rifqoi.com/key.pem";
      locations."/" = {
        return = "301 https://rifqoi.com";
        # root = "/usr/share/nginx/html";
      };
    };
    "garage.rifqoi.com" = {
      forceSSL = true;
      sslCertificate = "/var/lib/acme/garage.rifqoi.com/cert.pem";
      sslCertificateKey = "/var/lib/acme/garage.rifqoi.com/key.pem";
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.10:3909";
          extraConfig = nginxDefaultConfigs;
        };
      };
    };
    "s3.garage.rifqoi.com" = {
      forceSSL = true;

      sslCertificate = "/var/lib/acme/s3.garage.rifqoi.com/cert.pem";
      sslCertificateKey = "/var/lib/acme/s3.garage.rifqoi.com/key.pem";
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.10:3900";
          extraConfig = nginxDefaultConfigs;
        };
      };
    };
    "*.s3.garage.rifqoi.com" = {
      forceSSL = true;
      sslCertificate = "/var/lib/acme/s3.garage.rifqoi.com/cert.pem";
      sslCertificateKey = "/var/lib/acme/s3.garage.rifqoi.com/key.pem";
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.10:3900";
          extraConfig = nginxDefaultConfigs;
        };
      };
    };
    "grafana.rifqoi.com" = {
      forceSSL = true;

      sslCertificate = "/var/lib/acme/grafana.rifqoi.com/cert.pem";
      sslCertificateKey = "/var/lib/acme/grafana.rifqoi.com/key.pem";
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.12:3000";
          extraConfig = nginxDefaultConfigs;
        };
      };
    };

    "registry.rifqoi.com" = {
      forceSSL = true;

      sslCertificate = "/var/lib/acme/registry.rifqoi.com/cert.pem";
      sslCertificateKey = "/var/lib/acme/registry.rifqoi.com/key.pem";
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.14:5000";
          extraConfig = registryProxyConfigs;
        };
      };
    };

    "pocket.rifqoi.com" = {
      forceSSL = true;
      sslCertificate = "/var/lib/acme/pocket.rifqoi.com/cert.pem";
      sslCertificateKey = "/var/lib/acme/pocket.rifqoi.com/key.pem";
      locations = {
        "/" = {
          proxyPass = "http://192.168.31.13:1411";
          extraConfig = nginxDefaultConfigs;
        };
      };
    };

    # "omni.rifqoi.com" = {
    #   forceSSL = true;
    #   sslCertificate = "/var/lib/acme/omni.rifqoi.com/cert.pem";
    #   sslCertificateKey = "/var/lib/acme/omni.rifqoi.com/key.pem";
    #   locations = {
    #     "/" = {
    #       proxyPass = "https://192.168.31.20:443";
    #       extraConfig = ''
    #         proxy_set_header Host $host;
    #         proxy_set_header X-Real-IP $remote_addr;
    #         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    #         proxy_set_header X-Forwarded-Proto $scheme;
    #
    #         # Optional: enables SNI (Server Name Indication) for upstream connections
    #         proxy_ssl_server_name on;
    #       '';
    #     };
    #   };
    # };
  };
}
