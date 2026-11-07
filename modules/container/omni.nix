{
  pkgs,
  config,
  lib,
  ...
}: let
  omniDataDir = "/var/lib/omni";
  omniVersion = "v1.13.2";

  libvirtConfig = pkgs.writeText "libvirt-config" ''
    libvirt:
      uri: "qemu:///system"
  '';
in {
  imports = [./common.nix];

  networking.firewall.allowedTCPPorts = [80 443 8090 8091 8100 50180];

  # THIS IS REQUIRED FOR WIREGUARD SIDEROLINK
  networking.firewall.allowedUDPPorts = [50180];

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

  sops.secrets.registry_password = {
    sopsFile = ../../secrets/secrets.yaml;
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

      # Change to ghcr.io because of docker rate limits
      # Omni >= 1.13 has no EULA page in the UI and refuses to start until
      # the EULA (https://siderolabs.com/eula/) is accepted via these flags.
      cmd = [
        "--config-path=/omni-config.yaml"
        "--kubernetes-registry=ghcr.io/siderolabs/kubelet"
        "--eula-accept-name=Muhammad Rifqi Al Furqon"
        "--eula-accept-email=alfurqon.rifqi@gmail.com"
      ];
    };

    containers.omni-libvirt-provider = {
      # login = {
      #   username = "rifqoi-registry";
      #   passwordFile = config.sops.secrets.registry_password.path;
      #   registry = "https://registry.rifqoi.com";
      # };
      image = "ghcr.io/siderolabs/omni-infra-provider-libvirt:v0.3.0";
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

  # The provider exits immediately when Omni is not listening on :443 yet,
  # and five quick failures hit systemd's start limit, leaving it dead after
  # an Omni restart. Retry slowly and without a limit instead.
  systemd.services.podman-omni-libvirt-provider = {
    after = ["podman-omni.service"];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig.RestartSec = "10s";
  };
}
