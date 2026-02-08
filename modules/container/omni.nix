{
  pkgs,
  config,
  ...
}: let
  omniDataDir = "/var/lib/omni";
  omniUser = "omni";
  omniGroup = "omni";
in {
  imports = [./common.nix];

  networking.firewall.allowedTCPPorts = [80];

  virtualisation.oci-containers = {
    backend = "podman";
    containers.nginx = {
      image = "nginx";
      ports = [
        "80:80"
      ];
      extraOptions = ["--net=host"]; # Let docker have the whole host NIC
    };
  };
}
