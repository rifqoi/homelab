{
  config,
  pkgs,
  sops-nix,
  ...
}: {
  # Common container network configuration
  networking = {
    useHostResolvConf = false;
    nameservers = ["192.168.31.11" "1.1.1.1" "8.8.8.8"];
    firewall.enable = true;
    firewall.allowedTCPPorts = [22];
    defaultGateway = "192.168.31.1";
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    openFirewall = true;
    startWhenNeeded = false;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
    };
  };

  # Import common modules
  imports = [
    sops-nix.nixosModules.sops
    ../common/users.nix
  ];

  # SOPS configuration
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  # Common packages
  environment.systemPackages = with pkgs; [
    vim
    htop
    curl
    dnsutils
  ];

  system.stateVersion = "26.05";
}
