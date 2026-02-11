{pkgs, ...}: {
  imports = [./common.nix];
  networking.firewall.allowedTCPPorts = [9090];
  services.cockpit = {
    enable = true;
    plugins = [pkgs.cockpit-machines];
    port = 9090;
  };
}
