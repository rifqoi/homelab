{...}: {
  imports = [./common.nix];

  networking.firewall.allowedTCPPorts = [5000];

  services.dockerRegistry = {
    enable = true;
    enableDelete = true;
    listenAddress = "0.0.0.0";
    storagePath = "/var/lib/registry";
  };
}