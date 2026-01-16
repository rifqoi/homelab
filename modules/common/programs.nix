{pkgs, ...}: {
  programs = {
    zsh = {
      enable = true;
      histSize = 100000;
      autosuggestions.enable = true;
      ohMyZsh = {
        enable = true;
        theme = "agnoster";
        plugins = [
          "git"
          "zsh-autosuggestions"
          "bgnotify"
          "z"
          "zsh-completions"
          "zsh-vi-mode"
          "docker"
          "docker-compose"
          "zsh-syntax-highlighting"
          "kubectl"
        ];
      };
    };
    fzf = {
      fuzzyCompletion = true;
      keybindings = true;
    };

    starship = {
      enable = true;
    };
  };
}
