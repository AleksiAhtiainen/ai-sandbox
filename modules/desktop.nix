{ lib, pkgs, ... }:

{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "fi";
    variant = "mac";
  };

  programs.firefox.enable = true;

  # Pop Shell is installed but disabled by default. The on/off wrappers
  # flip a marker file on the share; an XDG autostart entry re-applies
  # that state at every login. Enabling also clears mutter's Super+arrow
  # grabs (half-screen snap, maximize/unmaximize) so Pop Shell's
  # focus-navigation bindings come through.
  #
  # Pop Shell's gsettings schema ships in the extension's own dir, not
  # the system schema path, so the gsettings CLI needs --schemadir to
  # find it.
  environment.systemPackages = let
    popShellSchemaDir = "${pkgs.gnomeExtensions.pop-shell}/share/gnome-shell/extensions/pop-shell@system76.com/schemas";
  in [
    pkgs.gnomeExtensions.pop-shell
    pkgs.pop-launcher
    (pkgs.writeShellScriptBin "pop-shell-apply" ''
      set -e
      state=off
      if [ -r /mnt/share/shared-config/.pop-shell ]; then
        state=$(tr -d '[:space:]' < /mnt/share/shared-config/.pop-shell)
      fi
      if [ "$state" = on ]; then
        gnome-extensions enable pop-shell@system76.com
        gsettings set org.gnome.mutter.keybindings toggle-tiled-left "@as []"
        gsettings set org.gnome.mutter.keybindings toggle-tiled-right "@as []"
        gsettings set org.gnome.desktop.wm.keybindings maximize "@as []"
        gsettings set org.gnome.desktop.wm.keybindings unmaximize "@as []"
        # Default Super+slash needs Shift on a Finnish keyboard; use Super+minus instead.
        gsettings --schemadir ${popShellSchemaDir} \
          set org.gnome.shell.extensions.pop-shell activate-launcher "['<Super>minus']"
      fi
    '')
    (pkgs.writeShellScriptBin "pop-shell-on" ''
      set -e
      install -d /mnt/share/shared-config
      echo on > /mnt/share/shared-config/.pop-shell
      pop-shell-apply
    '')
    (pkgs.writeShellScriptBin "pop-shell-off" ''
      set -e
      install -d /mnt/share/shared-config
      echo off > /mnt/share/shared-config/.pop-shell
      gnome-extensions disable pop-shell@system76.com 2>/dev/null || true
      gsettings reset org.gnome.mutter.keybindings toggle-tiled-left
      gsettings reset org.gnome.mutter.keybindings toggle-tiled-right
      gsettings reset org.gnome.desktop.wm.keybindings maximize
      gsettings reset org.gnome.desktop.wm.keybindings unmaximize
      gsettings --schemadir ${popShellSchemaDir} \
        reset org.gnome.shell.extensions.pop-shell activate-launcher
    '')
  ];

  environment.etc."xdg/autostart/pop-shell-apply.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Pop Shell state sync
    Exec=pop-shell-apply
    X-GNOME-Autostart-enabled=true
    OnlyShowIn=GNOME;
    NoDisplay=true
  '';

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
