{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    chromium
    jdk17
    (maven.override { jdk_headless = jdk17; })
    gnumake
    nodejs_24
    pnpm
  ];
}
