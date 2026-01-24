{pkgs, ...}: {
  users.users.rifqoi = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "libvirtd" "docker" "audio" "video" "render" "zfs" "incus-admin"];
    shell = pkgs.zsh;
    home = "/home/rifqoi";
    hashedPassword = "$y$j9T$gI0IkZGfLkKkywgyQgVbP.$gX9LyM78XxsqwckJdxmeJbFSi1h/eZz2OrDR1zVesj1";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDYn/VgsdSj/eBElypa+Pi6qmvNWhtSYWLI2Mas4ieL/S+qFcZz4v2f8HdCOwAAITRYhxvnY3n9QIBHoFJrfD0pFgIeOKloGUOZXrlWYl8kfUlvfOo3D1WsS+N4rl5AYH2lCDQ+Rg9rvYYxr06JhCb1/Zj0aI1RJs6gtofBnie2b6ezqleXpYBfKAYF/NQATk2x+2dckwSqjTDmvlXOWWBOMrgg6UB572D556QzqqaTyRmpGXtBgNQb/yWGG6fus20u/RiVKj60B5Vj0RqEfIGtOMVaRTyE0kGWuTDUP3WA4awiDRTEJqSRtTNFWWfd//Op3rAOndjcy4eP7LY8S0laKkTurV9FOYlZyBV5pFHgJto5XYUjG5HhIuzyVDWTbt47g07WOjGDj6Lis5OOkrtf56xF2NLJXtMpQwY8UMa/+6DZG7J0ixEqnYDvZ/J/fMQxmP51UEwHKh+3EYcMoB7twXUPlTqUhbhhZ4wOJZlqxwmrnSda5KkYJR7mGATbc60= rifqoi@home"
    ];

    packages = with pkgs; [
      tree
    ];
  };

  programs.zsh.enable = true;

  security.sudo.extraRules = [
    {
      users = ["rifqoi"];
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];
}
