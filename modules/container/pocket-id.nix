{
  pkgs,
  config,
  ...
}: {
  imports = [./common.nix];

  networking.firewall.allowedTCPPorts = [1411];

  config.sops.secrets.pocketid_encription_key = {
    owner = "pocket-id";
    group = "pocket-id";
    mode = "0400";
  };

  services.pocket-id = {
    enable = true;
    dataDir = "/var/lib/pocket-id";
    settings = {
      APP_URL = "https://pocket.rifqoi.com";
      ENCRIPTION_KEY_FILE = config.sops.secrets.pocketid_encription_key.path;
      TRUST_PROXY = true;
    };
  };
}
