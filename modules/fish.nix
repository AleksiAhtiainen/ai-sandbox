{ pkgs, lib, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/koski-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  bootstrap = pkgs.writeShellApplication {
    name = "koski-fish-bootstrap";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      share="/mnt/share/shared-config/fish_config"
      target="${homeDir}/.config/fish"

      # Source of truth lives on the share. If it isn't there, leave the
      # user's local fish config (if any) untouched.
      if [ ! -d "$share" ]; then
        exit 0
      fi

      install -d -o ${username} -g users -m 0755 "${homeDir}/.config"

      # Don't clobber a real, non-empty config dir the user set up locally.
      if [ -e "$target" ] && [ ! -L "$target" ]; then
        if [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
          echo "Refusing to replace existing $target — directory non-empty" >&2
          exit 0
        fi
        rmdir "$target"
      fi

      ln -sfn "$share" "$target"
      chown -h ${username}:users "$target"
    '';
  };
in
{
  # Enables fish system-wide and registers it in /etc/shells, so users can
  # opt in with `chsh -s $(which fish)`. The default login shell is left as
  # bash (set in user.nix / NixOS default).
  programs.fish.enable = true;

  systemd.services.koski-fish-bootstrap = {
    description = "Symlink ~/.config/fish to /mnt/share/shared-config/fish_config when available";
    after = [ "mnt-share.mount" ];
    wants = [ "mnt-share.mount" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/koski-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${bootstrap}/bin/koski-fish-bootstrap";
    };
  };
}
