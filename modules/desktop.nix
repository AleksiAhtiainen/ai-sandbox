{ lib, ... }:

{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "fi";
    variant = "mac";
  };

  programs.firefox.enable = true;

  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/peripherals/mouse".natural-scroll = true;
      settings."org/gnome/desktop/peripherals/keyboard" = {
        delay = lib.gvariant.mkUint32 250;
        repeat-interval = lib.gvariant.mkUint32 30;
      };
    }
  ];
}
