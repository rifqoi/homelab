{...}: let
  mkContainer = {
    hostBridge,
    localAddress,
    config,
    bindMounts ? {},
    autoStart ? true,
    privateNetwork ? true,
  }: {
    inherit autoStart privateNetwork hostBridge localAddress;
    bindMounts =
      {
        "/var/lib/sops-nix/key.txt" = {
          hostPath = "/var/lib/sops-nix/keys-container.txt";
          isReadOnly = true;
        };
      }
      // bindMounts;
    config = config;
  };
in {
  containers = {
    garage-s3 = mkContainer {
      hostBridge = "br31";
      localAddress = "192.168.31.10/24";
      config = ./garage-s3.nix;
      bindMounts = {
        "/var/lib/garage" = {
          hostPath = "/var/lib/private/garage";
          isReadOnly = false;
        };
      };
    };
  };
}
