{ pkgs, unstablePkgs, ... }:

{
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Helsinki";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fi_FI.UTF-8";
    LC_IDENTIFICATION = "fi_FI.UTF-8";
    LC_MEASUREMENT = "fi_FI.UTF-8";
    LC_MONETARY = "fi_FI.UTF-8";
    LC_NAME = "fi_FI.UTF-8";
    LC_NUMERIC = "fi_FI.UTF-8";
    LC_PAPER = "fi_FI.UTF-8";
    LC_TELEPHONE = "fi_FI.UTF-8";
    LC_TIME = "fi_FI.UTF-8";
  };

  programs.firefox.enable = true;

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    vim
    curl
    wget
    git
    spice-vdagent
    chromium
    jdk17
    (maven.override { jdk_headless = jdk17; })
    gnumake
    nodejs_24
    pnpm
    docker-compose
    unstablePkgs.jetbrains.idea  # IU 2026.1 from nixos-unstable; needs UTM display set to virtio-gpu-pci (no -gl) to render properly
    # jetbrains-toolbox
  ];

  virtualisation.docker.enable = true;

  programs.nix-ld.enable = true;

  system.activationScripts.binbash = ''
    ln -sfn ${pkgs.bashInteractive}/bin/bash /bin/bash
  '';

  system.stateVersion = "25.11";
}
