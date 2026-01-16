{
  pkgs,
  lib,
  options,
  config,
  ...
}: let
  inherit (lib) mkOption mkEnableOption mkIf types;
  cfg = config.features.virtualization.incus;
in {
  ###########################
  # NIX OPTIONS
  ###########################
  options.features.virtualization.incus = {
    enable = mkEnableOption "Incus Virtualization";
    enableUI = mkEnableOption "Enable Incus UI";

    setUsersAsAdmin = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of users to include as 'incus-admin' group. To run incus as non-root.";
    };

    preseed = mkOption {
      type = types.attrs;
      default = {};
      description = "Preseed settings for incus. More info on https://wiki.nixos.org/wiki/Incus#Preseed.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.incus-lts;
      description = "Incus package to use ('incus', 'incus-lts'). Choose 'incus' for feature releases.";
    };

    networking = {
      allowedTCPPorts = mkOption {
        type = types.listOf types.int;
        default = [];
        description = "List of allowed tcp ports in incusbr0 bridge network.";
      };

      allowedUDPPorts = mkOption {
        type = types.listOf types.int;
        default = [];
        description = "List of allowed udp ports in incusbr0 bridge network.";
      };
    };
  };

  config = mkIf cfg.enable {
    ###########################
    # INCUS
    ###########################
    virtualisation.incus = {
      enable = true;
      ui.enable = true;
      package = pkgs.incus;
      preseed = cfg.preseed;
    };

    ###########################
    # NETWORKING
    ###########################
    networking.nftables.enable = true;

    networking.firewall.allowedTCPPorts = [8443 8999];

    networking.firewall.interfaces.incusbr0.allowedTCPPorts = [
      53
      67
    ];
    networking.firewall.interfaces.incusbr0.allowedUDPPorts = [
      53
      67
    ];

    # networking.firewall.incusbr0 = config.virtualisation.incus.preseed.networks {
    #   allowedTCPPorts = cfg.networking.allowedTCPPorts;
    #   allowedUDPPorts = cfg.networking.allowedUDPPorts;
    # };
  };
}
