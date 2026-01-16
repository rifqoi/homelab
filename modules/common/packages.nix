{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    vim
    wget
    neovim
    git
    tcpdump
    inetutils
    dnsutils
    host
    curl
    tmux
    lsof
    jq
    unixtools.netstat
    zsh-vi-mode
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-completions
  ];
}
