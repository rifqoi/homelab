{pkgs, ...}: {
  imports = [./common.nix];
  networking.firewall.allowedTCPPorts = [9090];
  services.cockpit = {
    enable = true;
    port = 9090;
  };
}
