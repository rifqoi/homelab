{pkgs, ...}: {
  services = {
    ## Enable gpg-agent with ssh support
    gpg-agent = {
      enable = true;
      enableSshSupport = true;
      enableZshIntegration = true;
      # pinentry is a collection of simple PIN or passphrase dialogs used for
      # password entry
      pinentryPackage = pkgs.pinentry-tty;
    };

    ## We will put our keygrip here
    gpg-agent.sshKeys = [];
  };

  environment.systemPackages = with pkgs; [
    gnupg
  ];
}
