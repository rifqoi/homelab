{
  pkgs,
  config,
  lib,
  ...
}: {
  sops.secrets.tailscale_auth_key = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "root";
    mode = "0400";
  };
  services.tailscale = {
    enable = true;
    package = pkgs.tailscale;
    # Accept MagicDNS while keeping the host's normal upstream DNS resolver.
    extraSetFlags = ["--accept-dns=true"];
    # Authenticate this node on first boot
    authKeyFile = config.sops.secrets.tailscale_auth_key.path;
  };

  networking.firewall = {
    trustedInterfaces = ["tailscale0"];
    allowedUDPPorts = [53];
    allowedTCPPorts = [53];
  };
}
