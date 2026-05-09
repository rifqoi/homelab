{
  config,
  pkgs,
  ...
}: let
  backupSaveconfig = pkgs.writeShellScriptBin "backup-saveconfig" (builtins.readFile ../../k8s/clusters/production/infrastructure/democratic-csi/backup-saveconfig.sh);
  restoreSaveconfig = pkgs.writeShellScriptBin "restore-saveconfig" (builtins.readFile ../../k8s/clusters/production/infrastructure/democratic-csi/restore-saveconfig.sh);
in {
  # iSCSI target (targetcli backend)
  services.target.enable = true;

  # SSH for democratic-csi
  services.openssh.enable = true;

  # Create the csi-user
  users.users.csi-user = {
    isNormalUser = true;
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM91mwnjXlzvHaUagzR0eCg9jWtPBzv0Ej5F3b0taY8r democratic-csi"
    ];
  };

  # Sudo permissions for csi-user
  security.sudo.extraRules = [
    {
      users = ["csi-user"];
      commands = [
        {
          command = "/run/current-system/sw/bin/zfs";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/zpool";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/targetcli";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/wrappers/bin/sudo";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  # Silence MOTD for csi-user (prevents SSH output pollution)
  environment.etc."hushlogins".text = "";

  # Backup helper script packaged and installed
  environment.systemPackages = with pkgs; [
    zfs
    targetcli-fb
    backupSaveconfig
    restoreSaveconfig
  ];

  systemd.services.iscsi-target = {
    after = ["zfs-import.target" "zfs.target" "network-online.target" "restore-target-saveconfig.service"];
    requires = ["zfs-import.target" "network-online.target" "restore-target-saveconfig.service"];
  };

  systemd.services.libvirtd = {
    after = [
      "iscsi-target.service"
      "network-online.target"
    ];
    requires = ["iscsi-target.service"];
    wants = ["network-online.target"];
  };

  # Run once at startup to restore saveconfig.json from latest backup when missing/empty/{}
  systemd.services.restore-target-saveconfig = {
    description = "Restore /etc/target/saveconfig.json from latest backup when needed";
    after = ["local-fs.target" "zfs-import.target" "zfs.target"];
    wants = ["zfs-import.target" "zfs.target"];
    before = ["iscsi-target.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${restoreSaveconfig}/bin/restore-saveconfig";
    };
    wantedBy = ["multi-user.target"];
  };

  # Hourly backup timer for /etc/target/saveconfig.json
  systemd.services.backup-target-saveconfig = {
    description = "Backup /etc/target/saveconfig.json to /etc/target/backups";
    after = ["local-fs.target" "zfs-import.target" "zfs.target"];
    wants = ["zfs-import.target" "zfs.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${backupSaveconfig}/bin/backup-saveconfig";
    };
    wantedBy = ["multi-user.target"];
  };

  systemd.timers.backup-target-saveconfig = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  # Open iSCSI port
  networking.firewall.allowedTCPPorts = [3260];
}
