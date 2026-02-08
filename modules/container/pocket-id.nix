{
  pkgs,
  config,
  ...
}: {
  imports = [./common.nix];

  networking.firewall.allowedTCPPorts = [1411];

  sops.secrets.pocketid_encryption_key = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "pocket-id";
    mode = "0400";
  };

  services.pocket-id = {
    enable = true;
    dataDir = "/var/lib/pocket-id";
    settings = {
      APP_URL = "https://pocket.rifqoi.com";
      ENCRYPTION_KEY_FILE = config.sops.secrets.pocketid_encryption_key.path;
      TRUST_PROXY = true;
    };
  };
}
