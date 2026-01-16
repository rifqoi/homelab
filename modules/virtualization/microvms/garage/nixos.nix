{
  lib,
  config,
  ...
}: let
  vmName = "garage";
  cfg = config.features.microvm.garage;
in {
  options.features.microvm.garage = {
    enable = lib.mkEnableOption "Garage MicroVM";
  };

  config = lib.mkIf cfg.enable {
    # Create ZFS dataset for Garage if it doesn't exist
    # The dataset should be created manually: zfs create rpool/garage
    # Or add to disko configuration

    # Ensure the ZFS dataset is mounted
    fileSystems."/var/lib/private/garage" = {
      device = "rpool/garage";
      fsType = "zfs";
    };

    # Create necessary subdirectories
    systemd.tmpfiles.rules = [
      "d /var/lib/private/garage 0700 root root -"
      "d /var/lib/private/garage/data 0700 root root -"
      "d /var/lib/private/garage/metadata 0700 root root -"
      "d /persist/microvm/${vmName} 0700 root root -"
    ];

    # Add garage to microvm autostart
    microvm.autostart = [vmName];
  };
}
