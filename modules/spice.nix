{ pkgs, ... }:

{
  services.spice-vdagentd.enable = true;

  environment.etc."xdg/autostart/spice-vdagent.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Exec=${pkgs.spice-vdagent}/bin/spice-vdagent
    Hidden=false
    NoDisplay=false
    X-GNOME-Autostart-enabled=true
    Name=SPICE Agent
  '';
}
