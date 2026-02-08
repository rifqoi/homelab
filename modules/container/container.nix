{
  pkgs,
  sops-nix,
  ...
}: let
  acmeCertFolder = "/var/lib/acme";

  defaultBindMounts = {
    "/var/lib/sops-nix/key.txt" = {
      hostPath = "/var/lib/sops-nix/keys-container.txt";
      isReadOnly = true;
    };
    "${acmeCertFolder}" = {
      hostPath = acmeCertFolder;
      isReadOnly = false;
    };
  };

  mkContainer = {
    hostBridge,
    localAddress,
    configModule,
    extraBindMounts ? {},
    autoStart ? true,
    privateNetwork ? true,
    isDockerContainer ? false,
  }: {
    inherit autoStart privateNetwork hostBridge localAddress;
    bindMounts = defaultBindMounts // extraBindMounts;
    config = configModule;
    specialArgs = {inherit sops-nix;};
    extraFlags = pkgs.lib.mkIf isDockerContainer [
      # These extra flags are required for docker usage
      "--system-call-filter=keyctl"
      "--system-call-filter=bpf"
    ];
  };
in {
  containers = {
    garage-s3 = mkContainer {
      hostBridge = "br31";
      localAddress = "192.168.31.10/24";
      configModule = ./garage-s3.nix;
      extraBindMounts = {
        "/var/lib/garage" = {
          hostPath = "/var/lib/private/garage";
          isReadOnly = false;
        };
      };
    };

    blocky-dns = mkContainer {
      hostBridge = "br31";
      localAddress = "192.168.31.11/24";
      configModule = ./blocky-dns.nix;
    };

    grafana = mkContainer {
      hostBridge = "br31";
      localAddress = "192.168.31.12/24";
      configModule = ./grafana.nix;
    };

    nginx = mkContainer {
      hostBridge = "br31";
      localAddress = "192.168.31.30/24";
      configModule = ./nginx.nix;
    };

    pocket-id = mkContainer {
      hostBridge = "br31";
      localAddress = "192.168.31.13/24";
      configModule = ./pocket-id.nix;
    };

    omni = mkContainer {
      hostBridge = "br31";
      localAddress = "192.168.31.20/24";
      configModule = ./omni.nix;
      isDockerContainer = true;
    };
  };
}
