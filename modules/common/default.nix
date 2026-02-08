{...}: {
  imports = [
    ./locale.nix
    ./monitoring.nix
    ./networking.nix
    ./nix.nix
    ./packages.nix
    ./programs.nix
    ./services.nix
    ./users.nix
    ./acme.nix
  ];

  system.stateVersion = "25.11";
}
