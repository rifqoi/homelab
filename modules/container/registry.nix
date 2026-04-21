{config, ...}: {
  imports = [./common.nix];

  networking.firewall.allowedTCPPorts = [5000];
  sops.secrets = {
    registry_htpasswd_auth = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "docker-registry";
      mode = "0400";
    };
  };

  services.dockerRegistry = {
    enable = true;

    enableDelete = true;
    listenAddress = "0.0.0.0";
    storagePath = "/var/lib/registry";
    openFirewall = true;
    extraConfig = {
      auth = {
        htpasswd = {
          realm = "Registry Realm";
          path = config.sops.secrets.registry_htpasswd_auth.path;
        };
      };
    };
  };
}
