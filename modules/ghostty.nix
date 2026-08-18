{ pkgs, lib, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/ai-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  ghosttyBootstrap = pkgs.writeShellApplication {
    name = "ai-sandbox-ghostty-bootstrap";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      share="/mnt/share/shared-config/ghostty"
      target="${homeDir}/.config/ghostty"

      install -d -o ${username} -g users -m 0755 /mnt/share/shared-config
      install -d -o ${username} -g users -m 0755 "$share"
      install -d -o ${username} -g users -m 0755 "${homeDir}/.config"

      if [ -e "$target" ] && [ ! -L "$target" ]; then
        if [ -d "$target" ]; then
          cp -an "$target"/. "$share"/ 2>/dev/null || true
        else
          cp -an "$target" "$share"/ 2>/dev/null || true
        fi
        rm -rf "$target"
      fi

      ln -sfn "$share" "$target"
      chown -h ${username}:users "$target"
    '';
  };
in
{
  environment.systemPackages = [ pkgs.ghostty ];

  systemd.services.ai-sandbox-ghostty-bootstrap = {
    description = "Symlink ~/.config/ghostty to /mnt/share/shared-config/ghostty";
    after = [ "mnt-share.mount" ];
    wants = [ "mnt-share.mount" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/ai-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${ghosttyBootstrap}/bin/ai-sandbox-ghostty-bootstrap";
    };
  };
}
