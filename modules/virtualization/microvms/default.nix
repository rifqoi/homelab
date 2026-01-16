{
  inputs,
  lib,
  ...
}: let
  # Get all subdirectories in the microvms folder
  microvmsDir = ./.;
  allEntries = builtins.readDir microvmsDir;

  # Filter for directories only (excluding files like default.nix, microvm.nix)
  microVMDirs =
    lib.filterAttrs (
      name: type:
        type == "directory"
    )
    allEntries;

  # Import nixos.nix files from each microvm directory
  nixosModules =
    lib.mapAttrsToList (
      name: _: let
        nixosFile = microvmsDir + "/${name}/nixos.nix";
      in
        lib.optional (builtins.pathExists nixosFile) nixosFile
    )
    microVMDirs;

  # Flatten the list and remove empty entries
  flattenedModules = lib.flatten (lib.filter (x: x != []) nixosModules);
in {
  imports =
    [
      inputs.microvm.nixosModules.host
    ]
    ++ flattenedModules;
}
