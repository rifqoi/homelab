{
  pkgs,
  config,
  lib,
  ...
}: let
  omniDataDir = "/var/lib/omni";
  omniVersion = "v1.5.0";

  libvirtConfig = pkgs.writeText "libvirt-config" ''
    libvirt:
      uri: "qemu:///system"
  '';
in {
  imports = [./common.nix];

  networking.firewall.allowedTCPPorts = [80 443 8090 8091 8100];

  sops.secrets.omni_config_file = {
    sopsFile = ../../secrets/omni/omni.yaml;
    key = "";
    format = "yaml";
  };

  sops.secrets.omni_libvirt_provider = {
    sopsFile = ../../secrets/omni/libvirt-provider.env;
    key = "";
    format = "dotenv";
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers.omni = {
      image = "ghcr.io/siderolabs/omni:${omniVersion}";

      extraOptions = [
        "--net=host"
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun"
      ];

      volumes = [
        "${omniDataDir}/etcd:/_out/etcd"
        "${omniDataDir}/db.sqlite3:/var/lib/omni/db.sqlite3"
        "/var/lib/acme/omni.rifqoi.com/cert.pem:/var/lib/acme/omni.rifqoi.com/cert.pem"
        "/var/lib/acme/omni.rifqoi.com/key.pem:/var/lib/acme/omni.rifqoi.com/key.pem"
        "/var/lib/omni/omni.asc:/omni.asc"
        "${config.sops.secrets.omni_config_file.path}:/omni-config.yaml:ro"
      ];

      cmd = ["--config-path=/omni-config.yaml"];
    };

    containers.omni-libvirt-provider = {
      image = "ghcr.io/siderolabs/omni-infra-provider-libvirt";
      volumes = [
        "${libvirtConfig}:/config.yaml"
        "/var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock:rw"
      ];
      environmentFiles = [
        config.sops.secrets.omni_libvirt_provider.path
      ];

      cmd = ["--config-file=/config.yaml"];
    };
  };
}
