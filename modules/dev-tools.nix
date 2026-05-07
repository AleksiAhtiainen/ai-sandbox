{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    chromium
    docker-compose
    jdk17
    (maven.override { jdk_headless = jdk17; })
    gnumake
    jq
    nodejs_24
    pdfgrep
    pnpm
    poppler-utils
    qpdf
  ];

  # Stable path for IDEA's "Add SDK" dialog; the Nix store path changes on rebuild.
  systemd.tmpfiles.rules = [
    "L+ /etc/jdks/jdk17 - - - - ${pkgs.jdk17.home}"
  ];
}
