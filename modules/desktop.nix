{ ... }:

{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "fi";
    variant = "mac";
  };

  console.keyMap = "fi";
}
