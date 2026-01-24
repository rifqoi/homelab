{sops-nix, ...}: let
  defaultBindMounts = {
    "/var/lib/sops-nix/key.txt" = {
      hostPath = "/var/lib/sops-nix/keys-container.txt";
      isReadOnly = true;
    };
  };

  mkContainer = {
    hostBridge,
    localAddress,
    configModule,
    extraBindMounts ? {},
    autoStart ? true,
    privateNetwork ? true,
  }: {
    inherit autoStart privateNetwork hostBridge localAddress;
    bindMounts = defaultBindMounts // extraBindMounts;
    config = configModule;
    specialArgs = {inherit sops-nix;};
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
  };
}
