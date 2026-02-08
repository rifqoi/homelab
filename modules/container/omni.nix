{
  pkgs,
  config,
  ...
}: {
  imports = [./common.nix];
  virtualisation.oci-containers = {
    backend = "podman"; # As of 23.11 Podman causes long container shutdown times, docker is quick.
    containers.hello-world = {
      image = "hello-world";
      extraOptions = ["--net=host"]; # Let docker have the whole host NIC
    };
  };
}
