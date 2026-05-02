{
  config,
  pkgs,
  ...
}: {
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
          command = "${pkgs.zfs}/bin/zfs";
          options = ["NOPASSWD"];
        }
        {
          command = "${pkgs.zfs}/bin/zpool";
          options = ["NOPASSWD"];
        }
        {
          command = "${pkgs.targetcli}/bin/targetcli";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  # Silence MOTD for csi-user (prevents SSH output pollution)
  environment.etc."hushlogins".text = "";

  environment.systemPackages = with pkgs; [
    zfs
    targetcli
  ];

  # Open iSCSI port
  networking.firewall.allowedTCPPorts = [3260];
}
