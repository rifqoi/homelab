{...}: {
  sops.secrets.cloudflare = {
    sopsFile = ../../secrets/cloudflare.env;
    key = "";
    format = "dotenv";
  };

  users.users.rifqoi.extraGroups = ["acme"];
  users.groups.acme = {
    gid = 988;
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "rifqoi@rifqoi.com";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      environmentFile = "/run/secrets/cloudflare";
      group = "acme";
    };
    certs = {
      "home.rifqoi.com" = {};
      "garage.rifqoi.com" = {};
      "s3.garage.rifqoi.com" = {
        domain = "*.s3.garage.rifqoi.com";
        extraDomainNames = ["s3.garage.rifqoi.com"];
      };
      "grafana.rifqoi.com" = {};
      "registry.rifqoi.com" = {};
      "pocket.rifqoi.com" = {};
      "omni.rifqoi.com" = {};
    };
  };
}
