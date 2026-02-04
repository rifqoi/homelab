{
  pkgs,
  config,
  ...
}: {
  imports = [./common.nix];

  sops.secrets.cloudflare = {
    key = "";
    file = "../../secrets/cloudflare.yaml";
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
    };
  };

  services.nginx.enable = true;
  services.nginx.virtualHosts = {
    "home.rifqoi.com" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://192.168.31.30:80";
      };
    };
  };
}
