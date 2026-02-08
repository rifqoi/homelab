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
in {
  security.acme = {
    acceptTerms = true;
    certs = mkCert certs;
  };
}
