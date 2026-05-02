{...}: {
  networking.firewall.allowedTCPPorts = [22];
  networking.firewall.allowedUDPPorts = [443 7844];
}
