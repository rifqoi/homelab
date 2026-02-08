{
  pkgs,
  lib,
  config,
  ...
}: let
  certs = [
    "home.rifqoi.com"
    "garage.rifqoi.com"
    "garage-s3"
    "grafana.rifqoi.com"
    "pocket.rifqoi.com"
    "omni.rifqoi.com"
  ];

  mkCert = domains:
    lib.attrsets.genAttrs domains (domain: {
      email = "rifqoi@rifqoi.com";
      domain =
        if domain == "garage-s3"
        then "*.s3.garage.rifqoi.com"
        else domain;
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      credentialsFile = config.sops.secrets.cloudflare.path;
    });
in {
  sops.secrets.cloudflare = {
    sopsFile = ../../secrets/cloudflare.env;
    key = "";
    format = "dotenv";
  };

  security.acme = {
    acceptTerms = true;
    certs = mkCert certs;
  };
}
